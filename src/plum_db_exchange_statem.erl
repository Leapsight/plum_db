-module(plum_db_exchange_statem).
-behaviour(gen_statem).

-record(state, {
    %% node the exchange is taking place with
    peer                            :: node(),
    %% the remaining partitions to cover
    partitions                      :: [plum_db:partition()],
    %% count of trees that have been buit
    local_tree_updated = false      ::  boolean(),
    remote_tree_updated = false     ::  boolean(),
    %% length of time waited to aqcuire remote lock or update trees
    timeout                         :: pos_integer()
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
%% @doc Start an exchange of Cluster Metadata hashtrees between this node
%% and `Peer' for a given `Partition'. `Timeout' is the number of milliseconds
%% the process will wait to aqcuire the remote lock or to upate both trees.
%% @end
%% -----------------------------------------------------------------------------
-spec start(node(), list() | map()) -> {ok, pid()} | ignore | {error, term()}.

start(Peer, Opts) when is_list(Opts) ->
    start(Peer, maps:from_list(Opts));

start(Peer, Opts) when is_map(Opts) ->
    gen_statem:start(?MODULE, [Peer, Opts], []).


-spec start_link(node(), list() | map()) ->
    {ok, pid()} | ignore | {error, term()}.

start_link(Peer, Opts) when is_list(Opts) ->
    start_link(Peer, maps:from_list(Opts));

start_link(Peer, Opts) when is_map(Opts) ->
    gen_statem:start_link(?MODULE, [Peer, Opts], []).



%% =============================================================================
%% GEN_STATEM CALLBACKS
%% =============================================================================



init([Peer, Opts]) ->
    State = #state{
        peer = Peer,
        partitions = maps:get(partitions, Opts, plum_db:partitions()),
        timeout = maps:get(timeout, Opts, 60000)
    },

    %% We notify subscribers
    _ = plum_db_events:notify(exchange_started, Peer),

    {ok, acquiring_locks, State, [{next_event, internal, start}]}.


callback_mode() ->
    state_functions.


terminate(Reason, _StateName, _State) ->
    %% We notify subscribers
    _ = plum_db_events:notify(exchange_finished, Reason),
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
acquiring_locks(internal, start, State) ->
    State0 = reset_state(State),
    case acquire_local_lock(State0) of
        {ok, Partition, State1} ->
            %% get corresponding remote lock
            ok = async_acquire_remote_lock(State1#state.peer, Partition),
            {next_state, acquiring_locks, State1, State1#state.timeout};
        {error, Reason, State1} ->
            _ = lager:warning(
                "Exchange with peer timed out acquiring locks; peer=~p",
                [State1#state.peer]
            ),
            {stop, Reason, State1}
    end;

acquiring_locks(
    timeout, _, #state{partitions = [H|T], peer = Peer} = State) ->
    %% getting remote lock timed out
    ok = release_local_lock(H),
    _ = lager:info(
        "Exchange with peer timed out acquiring locks; peer=~p, partition=~p",
        [Peer, H]
    ),
    %% We try again with the remaining partitions
    NewState = State#state{partitions = T},
    {next_state, acquiring_locks, NewState, [{next_event, internal, start}]};

acquiring_locks(
    cast, {remote_lock_acquired, P}, #state{partitions = [P|_]} = State) ->
    {next_state, updating_hashtrees, State, [{next_event, internal, start}]};

acquiring_locks(cast, {remote_lock_error, Reason}, State) ->
    [H|T] = State#state.partitions,
    ok = release_local_lock(H),

    _ = lager:info(
        "Failed to acquire remote lock; peer=~p, partition=~p, reason=~p",
        [State#state.peer, H, Reason]
    ),
    %% We try again with the remaining partitions
    NewState = State#state{partitions = T},
    {next_state, acquiring_locks, NewState, [{next_event, internal, start}]};

acquiring_locks(Type, Content, State) ->
    _ = handle_event(acquiring_locks, Type, Content, State),
    {next_state, acquiring_locks, State}.


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
updating_hashtrees(internal, start, State) ->
    Partition = hd(State#state.partitions),
    %% Update local hashtree
    ok = update_request(node(), Partition),
    %% Update remote hashtree
    ok = update_request(State#state.peer, Partition),
    {next_state, updating_hashtrees, State, State#state.timeout};

updating_hashtrees(
    timeout, _, #state{peer = Peer, partitions = [H|T]} = State) ->
    _ = lager:error(
        "Exchange timed out updating trees; peer=~p, partition=~p",
        [Peer, H]),
    ok = release_locks(H, Peer),
    %% We try again with the remaining partitions
    NewState = State#state{partitions = T},
    {next_state, acquiring_locks, NewState, [{next_event, internal, start}]};

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
    ok = release_locks(H, State#state.peer),
    _ = lager:info(
        "Error while updating ~p hashtree; peer=~p, partition=~p, response=~p",
        [LocOrRemote, State#state.peer, H, Reason]
    ),
    %% We carry on with the remaining partitions
    NewState = State#state{partitions = T},
    {next_state, acquiring_locks, NewState, [{next_event, internal, start}]};

updating_hashtrees(Type, Content, State) ->
    _ = handle_event(updating_hashtrees, Type, Content, State),
    {next_state, updating_hashtrees, State}.


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
exchanging_data(timeout, _, State) ->
    Peer = State#state.peer,
    Partition = hd(State#state.partitions),

    RemoteFun = fun
        (Prefixes, {get_bucket, {Level, Bucket}}) ->
            plum_db_partition_hashtree:get_bucket(
                Peer, Partition, Prefixes, Level, Bucket);
        (Prefixes, {key_hashes, Segment}) ->
            plum_db_partition_hashtree:key_hashes(
                Peer, Partition, Prefixes, Segment)
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
            _ = lager:info(
                "Completed data exchange;"
                " partition=~p, peer=~p, missing_local_prefixes=~p,"
                " missing_remote_prefixes=~p, keys=~p",
                [Partition, Peer, LocalPrefixes, RemotePrefixes, Keys]
            );
        false ->
            _ = lager:info(
                "Completed data exchange; partition=~p, peer=~p",
                [Partition, Peer]
            )
    end,

    [H|T] = State#state.partitions,
    ok = release_locks(H, Peer),

    case T of
        [] ->
            %% H was the last partition, so we stop
            {stop, normal, State};
        _ ->
            %% We carry on with the remaining partitions
            NewState = State#state{partitions = T},
            {next_state, acquiring_locks, NewState, [
                {next_event, internal, start}]
            }
    end;

exchanging_data(Type, Content, State) ->
    _ = handle_event(exchanging_data, Type, Content, State),
    {next_state, exchanging_data, State}.



%% =============================================================================
%% PRIVATE
%% =============================================================================



reset_state(State) ->
    State#state{
        local_tree_updated = false,
        remote_tree_updated = false
    }.


handle_event(_, cast, {remote_lock_acquired, Partition}, State) ->
    %% We received a late respose to an async_acquire_remote_lock
    %% Unlock it.
    release_remote_lock(Partition, State#state.peer);

handle_event(StateLabel, Type, Event, State) ->
    _ = lager:info(
        "Invalid event; state=~p, type=~p, event=~p, state=~p",
        [Type, Event, StateLabel, State]
    ),
    ok.


acquire_local_lock(#state{partitions = [H|T]} = State) ->
    %% get local lock
    case plum_db_partition_hashtree:lock(H) of
        ok ->
            {ok, H, State};
        Error ->
            _ = lager:info(
                "Skipping partition, could not acquire local lock;"
                " partition=~p, reason=~p",
                [H, Error]),
            acquire_local_lock(State#state{partitions = T})
    end;

acquire_local_lock(#state{partitions = []} = State) ->
    {error, normal, State}.


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
    ok = release_remote_lock(Partition, Peer),
    release_local_lock(Partition).


%% @private
release_local_lock(Partition) ->
    _ = plum_db_partition_hashtree:release_lock(Partition),
    ok.

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
%% "borrowed" from riak_kv_exchange_fsm
do_async(F) ->
    Statem = self(),
    _ = spawn_link(fun() -> gen_statem:cast(Statem, F()) end),
    ok.


%% @private
repair(Peer, {missing_prefix, Type, Prefix}) ->
    repair_prefix(Peer, Type, Prefix);

repair(Peer, {key_diffs, Prefix, Diffs}) ->
    _ = [repair_keys(Peer, Prefix, Diff) || Diff <- Diffs],
    ok.


%% @private
repair_prefix(Peer, Type, [Prefix]) ->
    repair_prefix(Peer, Type, [Prefix, undefined]);

repair_prefix(Peer, Type, [Prefix, SubPrefix]) ->
    FullPrefix = {Prefix, SubPrefix},
    ItType = repair_iterator_type(Type),
    Iterator = repair_iterator(ItType, Peer, FullPrefix),
    repair_full_prefix(Type, Peer, Iterator).


%% @private
repair_full_prefix(Type, Peer, Iterator) ->
    case plum_db:iterator_done(Iterator) of
        true ->
            plum_db:iterator_close(Iterator);
        false ->
            {{FullPrefix, Key}, Obj} = plum_db:iterator_element(Iterator),
            repair_other(Type, Peer, {FullPrefix, Key}, Obj),
            repair_full_prefix(
                Type, Peer, plum_db:iterate(Iterator))
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
    RemoteObj = plum_db:get_object(Peer, PKey),
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
track_repair({missing_prefix, local, _}, Acc=#exchange{local=Local}) ->
    Acc#exchange{local=Local+1};

track_repair({missing_prefix, remote, _}, Acc=#exchange{remote=Remote}) ->
    Acc#exchange{remote=Remote+1};

track_repair({key_diffs, _, Diffs}, Acc=#exchange{keys=Keys}) ->
    Acc#exchange{keys = Keys + length(Diffs)}.