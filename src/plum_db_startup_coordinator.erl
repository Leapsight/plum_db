%% =============================================================================
%%  plum_db_startup_coordinator.erl -
%%
%%  Copyright (c) 2016-2019 Ngineo Limited t/a Leapsight. All rights reserved.
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

%% -----------------------------------------------------------------------------
%% @doc A transient worker that is used to listen to certain plum_db events and
%% allow watchers to wait (blocking the caller) for certain conditions.
%% This is used by plum_db_app during the startup process to wait for these
%% conditions.
%% @end
%% -----------------------------------------------------------------------------
-module(plum_db_startup_coordinator).
-behaviour(gen_server).

-record(state, {
    remaining_partitions        ::  list(integer()),
    remaining_hashtrees         ::  list(integer()),
    partition_watchers = []     ::  list(pid()),
    hashtree_watchers  = []     ::  list(pid())
}).

-type state()                   ::  #state{}.


-export([start_link/0]).
-export([stop/0]).
-export([wait_for_partitions/0]).
-export([wait_for_partitions/1]).
-export([wait_for_hashtrees/0]).
-export([wait_for_hashtrees/1]).

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
%% @doc Start plumtree_partitions_coordinator and link to calling process.
%% @end
%% -----------------------------------------------------------------------------
-spec start_link() -> {ok, pid()} | ignore | {error, term()}.

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
-spec stop() -> ok.

stop() ->
    gen_server:stop(?MODULE).


%% -----------------------------------------------------------------------------
%% @doc Blocks the caller until all partitions are initialised.
%% This is equivalent to calling `wait_for_partitions(infinity)'.
%% @end
%% -----------------------------------------------------------------------------
-spec wait_for_partitions() -> ok.

wait_for_partitions() ->
    wait_for_partitions(infinity).


%% -----------------------------------------------------------------------------
%% @doc Blocks the caller until all partitions are initialised
%% or the timeout TImeout is reached.
%% @end
%% -----------------------------------------------------------------------------
-spec wait_for_partitions(Timeout :: timeout()) -> ok | {error, timeout}.

wait_for_partitions(Timeout)
when (is_integer(Timeout) andalso Timeout > 0) orelse Timeout == infinity ->
    ok = gen_server:call(?MODULE, wait_for_partitions),

    receive
        {plum_db_partitions_init_finished, _Partitions} ->
            ok
    after Timeout ->
        {error, timeout}
    end.



%% -----------------------------------------------------------------------------
%% @doc Blocks the caller until all hastrees are built.
%% This is equivalent to calling `wait_for_hashtrees(infinity)'.
%% @end
%% -----------------------------------------------------------------------------
-spec wait_for_hashtrees() -> ok.

wait_for_hashtrees() ->
    wait_for_hashtrees(infinity).


%% -----------------------------------------------------------------------------
%% @doc Blocks the caller until all hastrees are built or the timeout TImeout
%% is reached.
%% @end
%% -----------------------------------------------------------------------------
-spec wait_for_hashtrees(Timeout :: timeout()) -> ok | {error, timeout}.

wait_for_hashtrees(Timeout)
when (is_integer(Timeout) andalso Timeout > 0) orelse Timeout == infinity ->
    ok = gen_server:call(?MODULE, wait_for_hashtrees),

    receive
        {plum_db_hashtrees_build_finished, _Partitions} ->
            ok
    after Timeout ->
        {error, timeout}
    end.



%% =============================================================================
%% GEN_SERVER_ CALLBACKS
%% =============================================================================



%% @private
-spec init([]) ->
    {ok, state()}
    | {ok, state(), non_neg_integer() | infinity}
    | ignore
    | {stop, term()}.

init([]) ->
    Partitions = plum_db:partitions(),
    State = #state{
        remaining_partitions = Partitions,
        remaining_hashtrees = Partitions
    },
    _ = plum_db_events:subscribe(partition_init_finished),
    _ = plum_db_events:subscribe(hashtree_build_finished),
    {ok, State}.


%% @private
-spec handle_call(term(), {pid(), term()}, state()) ->
    {reply, term(), state()}
    | {reply, term(), state(), non_neg_integer()}
    | {noreply, state()}
    | {noreply, state(), non_neg_integer()}
    | {stop, term(), term(), state()}
    | {stop, term(), state()}.

handle_call(
    wait_for_partitions, {Pid, _}, #state{remaining_partitions = []} = State) ->
    %% Nothing to wait for, so immediately reply
    ok = send_partitions_init_finished(Pid),
    {reply, ok, State};

handle_call(wait_for_partitions, {Pid, _}, State) ->
    L = [Pid | State#state.partition_watchers],
    {reply, ok, State#state{partition_watchers = L}};

handle_call(
    wait_for_hashtrees, {Pid, _}, #state{remaining_hashtrees = []} = State) ->
    %% Nothing to wait for, so immediately reply
    ok = send_hashtrees_build_finished(Pid),
    {reply, ok, State};

handle_call(wait_for_hashtrees, {Pid, _}, State) ->
    L = [Pid | State#state.hashtree_watchers],
    {reply, ok, State#state{hashtree_watchers = L}};

handle_call(remaining_partitions, _From, State) ->
    Res = State#state.remaining_partitions,
    {reply, Res, State};

handle_call(remaining_hashtrees, _From, State) ->
    Res = State#state.remaining_hashtrees,
    {reply, Res, State};

handle_call(_Event, _From, State) ->
    Res = ok,
    {reply, Res, State}.


%% @private
-spec handle_cast(term(), state()) ->
    {noreply, state()}
    | {noreply, state(), non_neg_integer()}
    | {stop, term(), state()}.

handle_cast(_Msg, State) ->
    {noreply, State}.


%% @private
-spec handle_info(term(), state()) ->
    {noreply, state()}
    | {noreply, state(), non_neg_integer()}
    | {stop, term(), state()}.

handle_info({plum_db_event, partition_init_finished, Result}, State) ->
    case Result of
        {ok, Partition} ->
            {noreply, remove_partition(Partition, State)};
        {error, _Reason, _Partition} ->
            %% ok = notify_error(Reason, Partition, State),
            %% Let the supervisor retry and eventually crash, and keep
            %% waiting?
            {noreply, State}
    end;

handle_info({plum_db_event, hashtree_build_finished, Result}, State) ->
    case Result of
        {ok, Partition} ->
            {noreply, remove_hashtree(Partition, State)};
        {error, _Reason, _Partition} ->
            %% ok = notify_error(Reason, Partition, State),
            %% Let the supervisor retry and eventually crash, and keep
            %% waiting?
            {noreply, State}
    end;


handle_info(Event, State) ->
    _ = lager:info("Received unknown info event; event=~p", [Event]),
    {noreply, State}.


%% @private
-spec terminate(term(), state()) -> term().

terminate(_Reason, _State) ->
    _ = plum_db_events:unsubscribe(partition_init_finished),
    _ = plum_db_events:unsubscribe(hashtree_build_finished),
    ok.


%% @private
-spec code_change(term() | {down, term()}, state(), term()) -> {ok, state()}.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.



%% =============================================================================
%% PRIVATE
%% =============================================================================



%% @private
remove_partition(_, #state{remaining_partitions = []} = State) ->
    State;

remove_partition(Partition, #state{} = State0) ->
    Remaining = lists:delete(Partition, State0#state.remaining_partitions),
    State1 = State0#state{remaining_partitions = Remaining},
    maybe_partitions_init_finished(State1).


%% @private
maybe_partitions_init_finished(#state{partition_watchers = []} = State) ->
    State;

maybe_partitions_init_finished(#state{remaining_partitions = []} = State) ->
    _ = [
        send_partitions_init_finished(Pid)
        || Pid <- State#state.partition_watchers
    ],
    State#state{partition_watchers = []};

maybe_partitions_init_finished(State) ->
    State.


%% @private
remove_hashtree(_, #state{remaining_hashtrees = []} = State) ->
    State;

remove_hashtree(Partition, #state{} = State0) ->
    Remaining = lists:delete(Partition, State0#state.remaining_hashtrees),
    State1 = State0#state{remaining_hashtrees = Remaining},
    maybe_hashtrees_build_finished(State1).


%% @private
maybe_hashtrees_build_finished(#state{hashtree_watchers = []} = State) ->
    State;

maybe_hashtrees_build_finished(#state{remaining_hashtrees = []} = State) ->
    _ = [
        send_hashtrees_build_finished(Pid)
        || Pid <- State#state.hashtree_watchers
    ],
    State#state{hashtree_watchers = []};

maybe_hashtrees_build_finished(State) ->
    State.


%% @private
send_partitions_init_finished(To) ->
    To ! {plum_db_partitions_init_finished, plum_db:partitions()},
    ok.

%% @private
send_hashtrees_build_finished(To) ->
    To ! {plum_db_hashtrees_build_finished, plum_db:partitions()},
    ok.