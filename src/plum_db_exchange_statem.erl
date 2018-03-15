-module(plum_db_exchange_statem).
-behaviour(gen_statem).

-record(state, {
    %% node the exchange is taking place with
    peer                        :: node(),
    %%  the partitions left
    partitions                  :: [plum_db:partition()],
    %% count of trees that have been buit
    local_tree_updated = false   ::  boolean(),
    remote_tree_updated = false ::  boolean(),
    %% length of time waited to aqcuire remote lock or
    %% update trees
    timeout                     :: pos_integer()
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
-spec start(node(), pos_integer()) -> {ok, pid()} | ignore | {error, term()}.

start(Peer, Timeout) ->
    gen_statem:start(?MODULE, [Peer, Timeout], []).



%% =============================================================================
%% GEN_STATEM CALLBACKS
%% =============================================================================



init([Peer, Timeout]) ->
    State = #state{
        peer = Peer,
        partitions = plum_db:partitions(),
        timeout = Timeout
    },
    {ok, acquiring_locks, State, [{next_event, internal, start}]}.


callback_mode() ->
    state_functions.


terminate(_Reason, _StateName, _State) ->
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
    ok = release_local_lock(State),
    _ = lager:info(
        "Exchange with peer timed out acquiring locks; peer=~p, partition=~p",
        [Peer, H]
    ),
    %% We try again with the remaining partitions
    NewState = State#state{partitions = T},
    {next_state, acquiring_locks, NewState, [{next_event, internal, start}]};

acquiring_locks(cast, {remote_lock, ok}, State) ->
    {next_state, updating_hashtrees, State, [{next_event, internal, start}]};

acquiring_locks(cast, {remote_lock, Reason}, State) ->
    ok = release_local_lock(State),
    [H|T] = State#state.partitions,
    _ = lager:info(
        "Failed to acquire remote lock; peer=~p, partition=~p, reason=~p",
        [State#state.peer, H, Reason]
    ),
    %% We try again with the remaining partitions
    NewState = State#state{partitions = T},
    {next_state, acquiring_locks, NewState, [{next_event, internal, start}]};

acquiring_locks(Type, Content, State) ->
    _ = log_event(acquiring_locks, Type, Content, State),
    {next_state, acquiring_locks, State}.


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
updating_hashtrees(internal, start, State) ->
    Partition = hd(State#state.partitions),
    %% Update local hastree
    ok = update_request(node(), Partition),
    %% Update remote hastree
    ok = update_request(State#state.peer, Partition),
    {next_state, updating_hashtrees, State, State#state.timeout};

updating_hashtrees(
    timeout, _, #state{peer = Peer, partitions = [H|T]} = State) ->
    _ = lager:error(
        "Exchange timed out updating trees; peer=~p, partition=~p",
        [Peer, H]),
    ok = release_locks(State),
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
    ok = release_locks(State),
    [H|T] = State#state.partitions,
    _ = lager:info(
        "Error while updating ~p hashtree; peer=~p, partition=~p, response=~p",
        [LocOrRemote, State#state.peer, H, Reason]
    ),
    %% We carry on with the remaining partitions
    NewState = State#state{partitions = T},
    {next_state, acquiring_locks, NewState, [{next_event, internal, start}]};

updating_hashtrees(Type, Content, State) ->
    _ = log_event(updating_hashtrees, Type, Content, State),
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
            plum_db_partition_hashtree:get_bucket(Peer, Partition, Prefixes, Level, Bucket);
        (Prefixes, {key_hashes, Segment}) ->
            plum_db_partition_hashtree:key_hashes(Peer, Partition, Prefixes, Segment)
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
                "Completed data exchange;"
                " partition=~p, peer=~p, missing_local_prefixes=0,"
                " missing_remote_prefixes=0, keys=0",
                [Partition, Peer]
            )
    end,
    ok = release_locks(State),
    case State#state.partitions of
        [Partition] ->
            {stop, normal, State};
        [Partition|T] ->
            %% We carry on with the remaining partitions
            NewState = State#state{partitions = T},
            {next_state, acquiring_locks, NewState, [
                {next_event, internal, start}]
            }
    end;

exchanging_data(Type, Content, State) ->
    _ = log_event(exchanging_data, Type, Content, State),
    {next_state, exchanging_data, State}.



%% =============================================================================
%% PRIVATE
%% =============================================================================


reset_state(State) ->
    State#state{
        local_tree_updated = false,
        remote_tree_updated = false
    }.


log_event(StateLabel, Type, Event, State) ->
    lager:info(
        "Invalid event; state=~p, type=~p, event=~p, state=~p",
        [Type, Event, StateLabel, State]
    ).



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
        Res = plum_db_partition_hashtree:lock(Peer, Partition, Self),
        {remote_lock, Res}
    end).


release_locks(State) ->
    Partition = hd(State#state.partitions),
    %% Release remote lock
    _ = plum_db_partition_hashtree:release_lock(State#state.peer, Partition),
    release_local_lock(State).


release_local_lock(State) ->
    _ = plum_db_partition_hashtree:release_lock(hd(State#state.partitions)),
    ok.


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
    ItType = repair_iterator_type(Type),
    repair_sub_prefixes(
        Type, Peer, Prefix, repair_iterator(ItType, Peer, Prefix));

repair_prefix(Peer, Type, [Prefix, SubPrefix]) ->
    FullPrefix = {Prefix, SubPrefix},
    ItType = repair_iterator_type(Type),
    repair_full_prefix(Type, Peer, FullPrefix, repair_iterator(ItType, Peer, FullPrefix)).


%% @private
repair_sub_prefixes(Type, Peer, Prefix, It) ->
    case plum_db:iterator_done(It) of
        true ->
            plum_db:iterator_close(It);
        false ->
            FullPrefix = {Prefix, _} = plum_db:iterator_prefix(It),
            ItType = repair_iterator_type(Type),
            ObjIt = repair_iterator(ItType, Peer, FullPrefix),
            repair_full_prefix(Type, Peer, FullPrefix, ObjIt),
            repair_sub_prefixes(Type, Peer, Prefix, plum_db:iterate(It))
    end.


%% @private
repair_full_prefix(Type, Peer, FullPrefix, ObjIt) ->
    case plum_db:iterator_done(ObjIt) of
        true ->
            plum_db:iterator_close(ObjIt);
        false ->
            {Key, Obj} = plum_db:iterator_value(ObjIt),
            repair_other(Type, Peer, {FullPrefix, Key}, Obj),
            repair_full_prefix(Type, Peer, FullPrefix, plum_db:iterate(ObjIt))
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
repair_iterator(local, _, Prefix)
when is_atom(Prefix) orelse is_binary(Prefix) ->
    plum_db:base_iterator(Prefix);
repair_iterator(local, _, FullPrefix) when is_tuple(FullPrefix) ->
    plum_db:base_iterator(FullPrefix, undefined);
repair_iterator(remote, Peer, PrefixOrFull) ->
    plum_db:remote_base_iterator(Peer, PrefixOrFull).


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