%% =============================================================================
%%  plum_db_exchange_statem.erl -
%%
%%  Copyright (c) 2018-2021 Leapsight. All rights reserved.
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

-module(plum_db_exchange_statem).
-behaviour(partisan_gen_statem).
-include_lib("kernel/include/logger.hrl").
-include("plum_db.hrl").

-record(state, {
    %% node the exchange is taking place with
    peer                            ::  node(),
    %% the remaining partitions to cover
    partitions                      ::  [plum_db:partition()],
    summary = #{}                   ::  summary(),
    %% count of trees that have been buit
    local_tree_updated = false      ::  boolean(),
    remote_tree_updated = false     ::  boolean(),
    %% length of time waited to acquire remote lock or update trees
    timeout                         ::  pos_integer()
}).

-record(exchange, {
    %% number of local prefixes repaired
    local   :: non_neg_integer(),
    %% number of remote prefixes repaired
    remote  :: non_neg_integer(),
    %% number of keys (missing, local, different) repaired,
    %% excluding those in prefixes counted by local/remote
    keys    :: non_neg_integer()
}).

-type summary() :: #{success | error | skipped => [plum_db:partition()]}.

%% API
-export([start/2]).
-export([start_link/2]).

%% gen_statem callbacks
-export([init/1]).
-export([callback_mode/0]).
-export([terminate/3]).
-export([code_change/4]).

%% gen_fsm states
-export([acquiring_locks/3]).
-export([updating_hashtrees/3]).
-export([exchanging_data/3]).




%% =============================================================================
%% API
%% =============================================================================


%% -----------------------------------------------------------------------------
%% @doc Start an exchange of plum_db hashtrees between this node
%% and `Peer' for a given `Partition'. `Timeout' is the number of milliseconds
%% the process will wait to aqcuire the remote lock or to update both trees.
%% @end
%% -----------------------------------------------------------------------------
-spec start(node(), list() | map()) -> {ok, pid()} | ignore | {error, term()}.

start(Peer, Opts) when is_list(Opts) ->
    start(Peer, maps:from_list(Opts));

start(Peer, Opts) when is_map(Opts) ->
    StartOpts = [{channel, plum_db_config:get(data_channel)}],
    partisan_gen_statem:start(?MODULE, [Peer, Opts], StartOpts).


-spec start_link(node(), list() | map()) ->
    {ok, pid()} | ignore | {error, term()}.

start_link(Peer, Opts) when is_list(Opts) ->
    start_link(Peer, maps:from_list(Opts));

start_link(Peer, Opts) when is_map(Opts) ->
    StartOpts = [{channel, plum_db_config:get(data_channel)}],
    partisan_gen_statem:start_link(?MODULE, [Peer, Opts], StartOpts).



%% =============================================================================
%% GEN_STATEM CALLBACKS
%% =============================================================================



init([Peer, Opts]) ->
    %% We monitor the remote peer so that we can cleanup locks in case we
    %% disconnect. If we do we will get {nodedown, Peer} info event.
    true = partisan:monitor_node(Peer, true),

    Partitions = maps:get(partitions, Opts, plum_db:partitions()),
    State = #state{
        peer = Peer,
        partitions = Partitions,
        summary = #{},
        timeout = maps:get(timeout, Opts, 60000)
    },

    %% We notify subscribers
    _ = plum_db_events:notify(exchange_started, {self(), Peer}),

    ?LOG_NOTICE(#{
        description => "AAE exchange starting",
        partitions => Partitions,
        peer => State#state.peer
    }),

    {ok, acquiring_locks, State, [{next_event, internal, next}]}.


callback_mode() ->
    state_functions.


terminate(Reason, _StateName, State) ->
    Peer = State#state.peer,
    _ = catch partisan:monitor_node(Peer, false),

    %% We notify subscribers
    _ = plum_db_events:notify(exchange_finished, {self(), Reason}),

    Summary = maps:map(fun(_, V) -> lists:sort(V) end, State#state.summary),

    ?LOG_NOTICE(#{
        description => "AAE exchange finished",
        peer => Peer,
        summary => Summary
    }),

    ok.


code_change(_OldVsn, StateName, State, _Extra) ->
    {ok, StateName, State}.



%% =============================================================================
%% STATE FUNCTIONS
%% =============================================================================



%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------

acquiring_locks(internal, next, #state{partitions = []} = State) ->
    %% We finished trying all partitions
    {stop, normal, State};

acquiring_locks(internal, next, #state{partitions = [H|T]} = State0) ->
    State1 = reset_state(State0),
    case plum_db_partition_hashtree:lock(H) of
        ok ->
            ?LOG_DEBUG(#{
                description => "Successfully acquired local lock",
                partition => H
            }),
            %% get corresponding remote lock
            ok = async_acquire_remote_lock(State1#state.peer, H),
            %% We wait for a remote lock event
            {next_state, acquiring_locks, State1, State1#state.timeout};
        Reason ->
            ?LOG_INFO(#{
                description => "Failed to acquire local lock, skipping partition",
                reason => Reason,
                partition => H
            }),
            %% We continue with the next partition
            State = add_summary(H, skipped, State1#state{partitions = T}),
            acquiring_locks(internal, next, State)
    end;

acquiring_locks(timeout, _, #state{partitions = []} = State) ->
    %% We finished trying all partitions
    {stop, normal, State};

acquiring_locks(timeout, _, #state{partitions = [H|T]} = State0) ->
    %% We timed out waiting for a remote lock for partition H
    ok = release_local_lock(H),
    ?LOG_INFO(#{
        description => "Failed to acquire remote lock, skipping partition",
        reason => timeout,
        partition => H,
        peer => State0#state.peer
    }),
    %% We try with the remaining partitions
    State = add_summary(H, skipped, State0#state{partitions = T}),
    {next_state, acquiring_locks, State, [{next_event, internal, next}]};

acquiring_locks(
    cast, {remote_lock_acquired, P}, #state{partitions = [P|_]} = State) ->
    ?LOG_DEBUG(#{
        description => "Successfully acquired remote lock",
        partition => P,
        peer => State#state.peer
    }),
    {next_state, updating_hashtrees, State, [{timeout, 0, start}]};

acquiring_locks(cast, {remote_lock_error, Reason}, State0) ->
    [H|T] = State0#state.partitions,
    ok = release_local_lock(H),
    ?LOG_INFO(#{
        description => "Failed to acquire remote lock, skipping partition",
        reason => Reason,
        partition => H,
        peer => State0#state.peer
    }),
    %% We try again with the remaining partitions
    State = add_summary(H, skipped, State0#state{partitions = T}),
    {next_state, acquiring_locks, State, [{next_event, internal, next}]};

acquiring_locks(Type, Content, State) ->
    handle_other_event(acquiring_locks, Type, Content, State).


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
updating_hashtrees(timeout, start, State) ->
    Partition = hd(State#state.partitions),
    %% Update local hashtree
    ok = update_request(node(), Partition),
    %% Update remote hashtree
    ok = update_request(State#state.peer, Partition),
    {next_state, updating_hashtrees, State, State#state.timeout};

updating_hashtrees(
    timeout, _, #state{peer = Peer, partitions = [H|T]} = State0) ->
    ?LOG_INFO(#{
        description => "Exchange timed out updating trees",
        reason => timeout,
        partition => H,
        node => Peer
    }),
    _ = catch release_locks(H, Peer),
    %% We try again with the remaining partitions
    State = add_summary(H, skipped, State0#state{partitions = T}),
    {next_state, acquiring_locks, State, [{next_event, internal, next}]};

updating_hashtrees(cast, local_tree_updated, State0) ->
    State1 = State0#state{local_tree_updated = true},
    case State1#state.remote_tree_updated of
        true ->
            {next_state, exchanging_data, State1, 0};
        false ->
            {next_state, updating_hashtrees, State1, State1#state.timeout}
    end;

updating_hashtrees(cast, remote_tree_updated, State0) ->
    State1 = State0#state{remote_tree_updated = true},
    case State1#state.local_tree_updated of
        true ->
            {next_state, exchanging_data, State1, 0};
        false ->
            {next_state, updating_hashtrees, State1, State1#state.timeout}
    end;

updating_hashtrees(cast, {error, {LocOrRemote, Reason}}, State) ->
    [H|T] = State#state.partitions,
    _ = catch release_locks(H, State#state.peer),
    ?LOG_ERROR(#{
        description => "Error while updating hashtree",
        hashtree => LocOrRemote,
        reason => Reason,
        partition => H,
        peer => State#state.peer
    }),
    %% We carry on with the remaining partitions
    NewState = add_summary(H, error, State#state{partitions = T}),
    {next_state, acquiring_locks, NewState, [{next_event, internal, next}]};

updating_hashtrees(Type, Content, State) ->
    handle_other_event(updating_hashtrees, Type, Content, State).


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
exchanging_data(timeout, _, #state{partitions = []} = State) ->
    {stop, normal, State};

exchanging_data(timeout, _, #state{partitions = [H|_]} = State) ->
    try
        Result = case perform_exchange(H, State) of
            #state{partitions = []} = NewState ->
                %% H was the last partition, so we stop
                {stop, normal, NewState};

            NewState ->
                %% We carry on with the remaining partitions
                {
                    next_state, acquiring_locks, NewState,
                    [{next_event, internal, next}]
                }
        end,

        release_locks(H, State#state.peer),

        Result

    catch
        exit:{nodedown, Peer} ->
            ?LOG_NOTICE(#{
                description => "AAE Exchange aborting, peer is down",
                partition => H,
                peer => Peer,
                reason => nodedown
            }),
            {stop, normal, State}
    end;

exchanging_data(Type, Content, State) ->
    handle_other_event(exchanging_data, Type, Content, State).



%% =============================================================================
%% PRIVATE
%% =============================================================================



%% @private
reset_state(State) ->
    State#state{
        local_tree_updated = false,
        remote_tree_updated = false
    }.


handle_other_event(_, cast, {remote_lock_acquired, Partition}, State) ->
    %% We received a late response to an async_acquire_remote_lock
    %% Unlock it.
    ok = release_remote_lock(Partition, State#state.peer),
    {keep_state, State};

handle_other_event(_, info, {nodedown, Peer}, #state{peer = Peer} = State0) ->
    [H|T] = State0#state.partitions,
    ok = release_local_lock(H),
    ?LOG_NOTICE(#{
        description => "AAE Exchange aborting, peer node down",
        reason => nodedown,
        peer => State0#state.peer
    }),
    %% We try with the remaining partitions
    State = add_summary(H, skipped, State0#state{partitions = T}),
    {stop, normal, State};

handle_other_event(StateLabel, Type, Event, State) ->
    ?LOG_INFO(#{
        reason => unsupported_event,
        state_name => StateLabel,
        event => Event,
        type => Type
    }),
    {keep_state, State}.


%% @private
async_acquire_remote_lock(Peer, Partition) ->
    Self = self(),
    do_async(fun() ->
        case plum_db_partition_hashtree:lock(Peer, Partition, Self) of
            ok ->
                {remote_lock_acquired, Partition};
            Res ->
                {remote_lock_error, Res}
        end
    end).


%% @private
release_locks(Partition, Peer) ->
    %% First release local lock as there are mote chances releasing the remote
    %% could fail
    ok = release_local_lock(Partition),
    ok = release_remote_lock(Partition, Peer).


%% @private
release_local_lock(Partition) ->
    plum_db_partition_hashtree:release_lock(Partition).


%% @private
release_remote_lock(Partition, Peer) ->
    plum_db_partition_hashtree:release_lock(Peer, Partition).


%% @private
update_request(Node, Partition) when Node =:= node() ->
    do_async(fun() ->
        %% acquired lock so we know there is no other update
        %% and tree is built
        case plum_db_partition_hashtree:update(Node, Partition) of
            ok -> local_tree_updated;
            Error -> {error, {local, Error}}
        end
    end);

update_request(Node, Partition) ->
    do_async(fun() ->
        %% acquired lock so we know there is no other update
        %% and tree is built
        case plum_db_partition_hashtree:update(Node, Partition) of
            ok -> remote_tree_updated;
            Error -> {error, {remote, Error}}
        end
    end).


%% @private
do_async(F) ->
    Statem = self(),

    _ = spawn_link(
        fun() -> partisan_gen_statem:cast(Statem, F(), ?CAST_OPTS) end
    ),
    ok.


perform_exchange(Partition, State) ->
    Peer = State#state.peer,

    RemoteFun = fun
        (Prefixes, {get_bucket, {Level, Bucket}}) ->
            plum_db_partition_hashtree:get_bucket(
                Peer, Partition, Prefixes, Level, Bucket
            );
        (Prefixes, {key_hashes, Segment}) ->
            plum_db_partition_hashtree:key_hashes(
                Peer, Partition, Prefixes, Segment
            )
    end,

    HandlerFun = fun(Diff, Acc) ->
        repair(Peer, Diff),
        track_repair(Diff, Acc)
    end,

    Res = plum_db_partition_hashtree:compare(
        Partition,
        RemoteFun,
        HandlerFun,
        #exchange{local = 0, remote = 0, keys = 0}
    ),

    #exchange{
        local = LocalPrefixes,
        remote = RemotePrefixes,
        keys = Keys
    } = Res,

    Total = LocalPrefixes + RemotePrefixes + Keys,

    case Total > 0 of
        true ->
            ?LOG_INFO(#{
                description => "Completed data exchange",
                partition => Partition,
                missing_local_prefixes => LocalPrefixes,
                missing_remote_prefixes => RemotePrefixes,
                keys => Keys,
                peer => Peer
            });
        false ->
            ?LOG_DEBUG(#{
                description => "Completed data exchange (no changes)",
                partition => Partition,
                peer => Peer
            })
    end,

    [H|T] = State#state.partitions,
    add_summary(H, success, State#state{partitions = T}).


%% @private
repair(Peer, {missing_prefix, Type, Prefix}) ->
    repair_prefix(Peer, Type, Prefix);

repair(Peer, {key_diffs, Prefix, Diffs}) ->
    _ = [repair_keys(Peer, Prefix, Diff) || Diff <- Diffs],
    ok.


%% @private
repair_prefix(Peer, Type, [Prefix]) ->
    repair_prefix(Peer, Type, [Prefix, '_']);

repair_prefix(Peer, Type, [Prefix, SubPrefix]) ->
    FullPrefix = {Prefix, SubPrefix},
    ItType = repair_iterator_type(Type),
    Iterator = repair_iterator(ItType, Peer, FullPrefix),

    try
        repair_full_prefix(Type, Peer, Iterator)
    catch
        Class:Reason:Stacktrace ->
            ?LOG_ERROR(#{
                description => "Error while repairing prefix.",
                prefix => FullPrefix,
                class => Class,
                reason => Reason,
                stacktrace => Stacktrace
            }),
            ok
    after
        plum_db:iterator_close(Iterator)
    end.


%% @private
repair_full_prefix(Type, Peer, Iterator) ->
    case plum_db:iterator_done(Iterator) of
        true ->
            ok;
        false ->
            {{FullPrefix, Key}, Obj} = plum_db:iterator_element(Iterator),
            repair_other(Type, Peer, {FullPrefix, Key}, Obj),
            repair_full_prefix(Type, Peer, plum_db:iterate(Iterator))
    end.


%% @private
repair_other(local, _Peer, PKey, Obj) ->
    %% local missing data, merge remote data locally
    merge(undefined, PKey, Obj);

repair_other(remote, Peer, PKey, Obj) ->
    %% remote missing data, merge local data into remote node
    merge(Peer, PKey, Obj).


%% @private
repair_keys(Peer, PrefixList, {_Type, KeyBin}) ->
    Key = binary_to_term(KeyBin),
    Prefix = list_to_tuple(PrefixList),
    PKey = {Prefix, Key},
    LocalObj = plum_db:get_object(PKey),
    RemoteObj = plum_db:get_remote_object(Peer, PKey, [], 30000),
    merge(undefined, PKey, RemoteObj),
    merge(Peer, PKey, LocalObj),
    ok.


%% @private
%% context is ignored since its in object, so pass undefined
merge(undefined, PKey, RemoteObj) ->
    plum_db:merge({PKey, undefined}, RemoteObj);

merge(Peer, PKey, LocalObj) ->
    plum_db:merge(Peer, {PKey, undefined}, LocalObj).


%% @private
repair_iterator(local, _, {_, _} = FullPrefix) ->
    plum_db:iterator(FullPrefix);

repair_iterator(remote, Peer, FullPrefix) ->
    plum_db:remote_iterator(Peer, FullPrefix).


%% @private
repair_iterator_type(local) ->
    %% local node missing prefix, need to iterate remote
    remote;
repair_iterator_type(remote) ->
    %% remote node missing prefix, need to iterate local
    local.


%% @private
track_repair({missing_prefix, local, Prefix}, #exchange{local = Local} = Acc) ->
    ?LOG_DEBUG(#{
        description => "Local store is missing data for prefix",
        prefix => Prefix
    }),
    Acc#exchange{local = Local + 1};

track_repair(
    {missing_prefix, remote, Prefix}, #exchange{remote = Remote} = Acc) ->
    ?LOG_DEBUG(#{
        description => "Remote store is missing data for prefix",
        prefix => Prefix
    }),
    Acc#exchange{remote = Remote + 1};

track_repair({key_diffs, _, Diffs}, #exchange{keys = Keys} = Acc) ->
    Acc#exchange{keys = Keys + length(Diffs)}.


%% @private
add_summary(Partition, Status, State)
when Status == success; Status == error; Status == skipped ->
    Summary = State#state.summary,
    State#state{summary = maps_utils:append(Status, Partition, Summary)}.