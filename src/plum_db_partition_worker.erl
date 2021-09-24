%% =============================================================================
%%  plum_db_partition_worker.erl -
%%
%%  Copyright (c) 2013 Basho Technologies, Inc.  All Rights Reserved.
%%  Copyright (c) 2017-2021 Leapsight. All rights reserved.
%%
%%  Licensed under the Apache License, Version 2.0 (the "License");
%%  you may not use this file except in compliance with the License.
%%  You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%%  Unless required by applicable law or agreed to in writing, software
%%  distributed under the License is distributed on an "AS IS" BASIS,
%%  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%%  See the License for the specific language governing permissions and
%%  limitations under the License.
%% =============================================================================

-module(plum_db_partition_worker).
-behaviour(gen_server).
-include("plum_db.hrl").


-record(state, {
    partition   :: non_neg_integer(),
    %% identifier used in logical clocks
    server_id   :: term()
}).

-type state()   :: #state{}.


-export([start_link/1]).
-export([name/1]).

%% gen_server callbacks
-export([init/1]).
-export([handle_call/3]).
-export([handle_cast/2]).
-export([handle_info/2]).
-export([terminate/2]).
-export([code_change/3]).


%% =============================================================================
%% API
%% =============================================================================



%% -----------------------------------------------------------------------------
%% @doc Start plum_db_partition_worker for the partition Id and link to calling
%% process.
%% @end
%% -----------------------------------------------------------------------------
-spec start_link(non_neg_integer()) -> {ok, pid()} | ignore | {error, term()}.

start_link(Id) ->
    gen_server:start_link({local, name(Id)}, ?MODULE, [Id], []).


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
%% @private
name(Id) ->
    list_to_atom("plum_db_partition_" ++ integer_to_list(Id) ++ "_worker").



%% =============================================================================
%% GEN_SERVER CALLBACKS
%% =============================================================================



-spec init([non_neg_integer()]) ->
    {ok, state()}
    | {ok, state(), non_neg_integer() | infinity}
    | ignore
    | {stop, term()}.

init([Id]) ->
    Nodename = {Id, node()},
    State = #state{partition = Id, server_id = Nodename},
    {ok, State}.



-spec handle_call(term(), {pid(), term()}, state()) ->
    {reply, term(), state()}
    | {reply, term(), state(), non_neg_integer()}
    | {noreply, state()}
    | {noreply, state(), non_neg_integer()}
    | {stop, term(), term(), state()}
    | {stop, term(), state()}.

handle_call({get_object, PKey}, _From, State) ->
    %% This is to support requests from another node
    Result = get_object(PKey, State),
    {reply, Result, State};

handle_call({put, PKey, Context, ValueOrFun}, _From, State) ->
    %% We implement puts here since we need to do a read followed by a write
    %% atomically, and we need to serialise them.
    {_, Result, NewState} = put(PKey, Context, ValueOrFun, State),
    {reply, Result, NewState};

handle_call({take, PKey, Context}, _From, State) ->
    {Existing, Result, NewState} = put(PKey, Context, ?TOMBSTONE, State),
    {reply, {Existing, Result}, NewState};

handle_call({merge, PKey, Obj}, _From, State0) ->
    %% We implement puts here since we need to do a read followed by a write
    %% atomically, and we need to serialise them.
    Existing = get_object(PKey, State0),
    case plum_db_object:reconcile(Obj, Existing) of
        false ->
            %% The remote object is an anscestor of or is equal to the local one
            {reply, false, State0};
        {true, Reconciled} ->
            {Reconciled, State1} = store(PKey, Reconciled, State0),
            %% We notify local subscribers and event handlers
            ok = plum_db_events:update({PKey, Reconciled, Existing}),
            {reply, true, State1}
    end.


-spec handle_cast(term(), state()) ->
    {noreply, state()}
    | {noreply, state(), non_neg_integer()}
    | {stop, term(), state()}.

handle_cast(_Msg, State) ->
    {noreply, State}.


-spec handle_info(term(), state()) ->
    {noreply, state()}
    | {noreply, state(), non_neg_integer()}
    | {stop, term(), state()}.

handle_info(_, State) ->
    {noreply, State}.


-spec terminate(term(), state()) -> term().

terminate(_Reason, _State) ->
    ok.


-spec code_change(term() | {down, term()}, state(), term()) -> {ok, state()}.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.



%% =============================================================================
%% PRIVATE
%% =============================================================================


%% @private
get_object(PKey, State) ->
    case plum_db_partition_server:get(State#state.partition, PKey) of
        {error, not_found} ->
            undefined;
        {ok, Existing} ->
            Existing
    end.


%% @private
store({_FullPrefix, _Key} = PKey, Obj, State) ->
    ok = case plum_db_config:get(aae_enabled) of
        true ->
            Hash = plum_db_object:hash(Obj),
            plum_db_partition_hashtree:insert(
                State#state.partition, PKey, Hash, false);
        false ->
            ok
    end,
    ok = plum_db_partition_server:put(State#state.partition, PKey, Obj),
    {Obj, State}.


put(PKey, Context, ValueOrFun, State) ->
    Existing = get_object(PKey, State),
    ServerId = State#state.server_id,
    Modified = plum_db_object:modify(Existing, Context, ValueOrFun, ServerId),
    {Result, NewState} = store(PKey, Modified, State),
    {Existing, Result, NewState}.
