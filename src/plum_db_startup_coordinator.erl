%% =============================================================================
%%  plum_db_startup_coordinator.erl -
%%
%%  Copyright (c) 2016-2019 Leapsight t/a Leapsight. All rights reserved.
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
%% This is used by plum_db_app during the startup process to wait for the
%% following conditions:
%%
%% * Partition initisalisation – the worker subscribes to plum_db notifications
%% and keeps track of each partition initialisation until they are all
%% initialised (or failed to initilised) and replies to all watchers with a
%% `ok' or `{error, FailedPartitions}', where FailedPartitions is a map() which
%% keys are the partition number and the value is the reason for the failure.
%% * Partition hashtree build – the worker subscribes to plum_db notifications
%% and keeps track of each partition hashtree until they are all
%% built (or failed to build) and replies to all watchers with a
%% `ok' or `{error, FailedHashtrees}', where FailedHashtrees is a map() which
%% keys are the partition number and the value is the reason for the failure.
%%
%% A watcher is any process which calls the functions wait_for_partitions/0,1
%% and/or wait_for_hashtrees/0,1. Both functions will block the caller until
%% the above conditions are met.
%%
%% @end
%% -----------------------------------------------------------------------------
-module(plum_db_startup_coordinator).
-behaviour(gen_server).

-record(state, {
    remaining_partitions        ::  list(integer()),
    remaining_hashtrees         ::  list(integer()),
    partition_watchers = []     ::  list({pid(), any()}),
    hashtree_watchers = []      ::  list({pid(), any()}),
    failed_partitions = #{}     ::  map(),
    failed_hashtrees = #{}      ::  map()
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
-spec wait_for_partitions() ->
    ok | {error, timeout} | {error, FailedPartitions :: map()}.

wait_for_partitions() ->
    wait_for_partitions(infinity).


%% -----------------------------------------------------------------------------
%% @doc Blocks the caller until all partitions are initialised
%% or the timeout TImeout is reached.
%% @end
%% -----------------------------------------------------------------------------
-spec wait_for_partitions(Timeout :: timeout()) ->
    ok | {error, timeout} | {error, FailedPartitions :: map()}.

wait_for_partitions(Timeout)
when (is_integer(Timeout) andalso Timeout > 0) orelse Timeout == infinity ->
    {ok, Tag} = gen_server:call(?MODULE, wait_for_partitions),

    receive
        {plum_db_partitions_init_finished, Tag, Return} ->
            Return
    after
        Timeout ->
            {error, timeout}
    end.



%% -----------------------------------------------------------------------------
%% @doc Blocks the caller until all hastrees are built.
%% This is equivalent to calling `wait_for_hashtrees(infinity)'.
%% @end
%% -----------------------------------------------------------------------------
-spec wait_for_hashtrees() ->
    ok | {error, timeout} | {error, FailedHashtrees :: map()}.

wait_for_hashtrees() ->
    wait_for_hashtrees(infinity).


%% -----------------------------------------------------------------------------
%% @doc Blocks the caller until all hastrees are built or the timeout TImeout
%% is reached.
%% @end
%% -----------------------------------------------------------------------------
-spec wait_for_hashtrees(Timeout :: timeout()) ->
    ok | {error, timeout} | {error, FailedHashtrees :: map()}.

wait_for_hashtrees(Timeout)
when (is_integer(Timeout) andalso Timeout > 0) orelse Timeout == infinity ->
    {ok, Tag} = gen_server:call(?MODULE, wait_for_hashtrees),

    receive
        {plum_db_hashtrees_build_finished, Tag, Return} ->
            Return
    after
        Timeout ->
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
    wait_for_partitions, From, #state{remaining_partitions = []} = State) ->
    %% Nothing to wait for, so immediately reply
    Message = case State#state.failed_partitions of
        Map when map_size(Map) == 0 -> ok;
        Map -> {error, Map}
    end,
    Res = send(From, plum_db_partitions_init_finished, Message),
    {reply, Res, State};

handle_call(wait_for_partitions, {_, Tag} = From, State) ->
    L = [From | State#state.partition_watchers],
    {reply, {ok, Tag}, State#state{partition_watchers = L}};

handle_call(
    wait_for_hashtrees, From, #state{remaining_hashtrees = []} = State) ->
    %% Nothing to wait for, so immediately reply
    Message = case State#state.failed_hashtrees of
        Map when map_size(Map) == 0 -> ok;
        Map -> {error, Map}
    end,
    Res = send(From, plum_db_hashtrees_build_finished, Message),
    {reply, Res, State};

handle_call(wait_for_hashtrees, {_, Tag} = From, State) ->
    L = [From | State#state.hashtree_watchers],
    {reply, {ok, Tag}, State#state{hashtree_watchers = L}};

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
        {error, Reason, Partition} ->
            Map = maps:put(Partition, Reason, State#state.failed_partitions),
            NewState = State#state{failed_partitions = Map},
            {noreply, remove_partition(Partition, NewState)}
    end;

handle_info({plum_db_event, hashtree_build_finished, Result}, State) ->
    case Result of
        {ok, Partition} ->
            {noreply, remove_hashtree(Partition, State)};
        {error, Reason, Partition} ->
            Map = maps:put(Partition, Reason, State#state.failed_hashtrees),
            NewState = State#state{failed_partitions = Map},
            {noreply, NewState}
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

maybe_partitions_init_finished(
    #state{remaining_partitions = [], failed_partitions = Failed} = State)
    when map_size(Failed) == 0 ->
    _ = [
        send(Watcher, plum_db_partitions_init_finished, ok)
        || Watcher <- State#state.partition_watchers
    ],
    State#state{partition_watchers = []};

maybe_partitions_init_finished(#state{remaining_partitions = []} = State)->
    _ = [
        send(
            Watcher,
            plum_db_partitions_init_finished,
            {error, State#state.failed_partitions}
        )
        || Watcher <- State#state.partition_watchers
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

maybe_hashtrees_build_finished(
    #state{remaining_hashtrees = [], failed_hashtrees = Failed} = State)
    when map_size(Failed) == 0 ->
    _ = [
        send(Watcher, plum_db_hashtrees_build_finished, ok)
        || Watcher <- State#state.hashtree_watchers
    ],
    State#state{hashtree_watchers = []};

maybe_hashtrees_build_finished(#state{remaining_hashtrees = []} = State)->
    _ = [
        send(
            Watcher,
            plum_db_hashtrees_build_finished,
            {error, State#state.failed_hashtrees}
        )
        || Watcher <- State#state.hashtree_watchers
    ],
    State#state{hashtree_watchers = []};

maybe_hashtrees_build_finished(State) ->
    State.


%% @private
send({Pid, Tag}, Event, Message) ->
    Pid ! {Event, Tag, Message},
    {ok, Tag}.
