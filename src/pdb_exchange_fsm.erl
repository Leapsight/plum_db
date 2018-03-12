%% -------------------------------------------------------------------
%%
%% Copyright (c) 2013 Basho Technologies, Inc.  All Rights Reserved.
%%
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.
%%
%% -------------------------------------------------------------------
-module(pdb_exchange_fsm).
-behaviour(gen_fsm).


-define(SERVER, ?MODULE).

-record(state, {
    %% node the exchange is taking place with
    peer          :: node(),

    %%  the partitions left
    partitions    :: [pdb:partition()],

    %% count of trees that have been buit
    built         :: non_neg_integer(),

    %% length of time waited to aqcuire remote lock or
    %% update trees
    timeout       :: pos_integer()
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

%% gen_fsm callbacks
-export([init/1]).
-export([handle_event/3]).
-export([handle_sync_event/4]).
-export([handle_info/3]).
-export([terminate/3]).
-export([code_change/4]).

%% gen_fsm states
-export([prepare/2]).
-export([prepare/3]).
-export([update/2]).
-export([update/3]).
-export([exchange/2]).
-export([exchange/3]).


-ifdef(otp20).
-compile([
    {nowarn_deprecated_function, [
        {gen_fsm, start, 3},
        {gen_fsm, send_event, 2}
    ]}
]).
-endif.



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
    gen_fsm:start(?MODULE, [Peer, Timeout], []).



%% =============================================================================
%% GEN_FSM CALLBACKS
%% =============================================================================



init([Peer, Timeout]) ->
    gen_fsm:send_event(self(), start),
    State = #state{
        peer = Peer,
        partitions = pdb:partitions(),
        built = 0,
        timeout = Timeout
    },
    {ok, prepare, State}.


handle_event(_Event, StateName, State) ->
    {next_state, StateName, State}.


handle_sync_event(_Event, _From, StateName, State) ->
    Reply = ok,
    {reply, Reply, StateName, State}.


handle_info(_Info, StateName, State) ->
    {next_state, StateName, State}.


terminate(_Reason, _StateName, _State) ->
    ok.


code_change(_OldVsn, StateName, State, _Extra) ->
    {ok, StateName, State}.



%% =============================================================================
%% STATES
%% =============================================================================



prepare(start, #state{partitions = [H|_]} = State) ->
    %% get local lock
    case pdb_hashtree:lock(H) of
        ok ->
            %% get remote lock
            remote_lock_request(State#state.peer, H),
            {next_state, prepare, State, State#state.timeout};
        _Error ->
            {stop, normal, State}
    end;

prepare(timeout, State=#state{partitions = [Partition|_], peer = Peer}) ->
    %% getting remote lock timed out
    _ = lager:error(
        "Exchange with peer timed out acquiring locks; peer=~p, partition=~p",
        [Peer, Partition]
    ),
    {stop, normal, State};

prepare({remote_lock, ok}, State) ->
    %% getting remote lock succeeded
    update(start, State);

prepare({remote_lock, _Error}, State) ->
    %% failed to get remote lock
    {stop, normal, State}.


update(start, State) ->
    update_request(node(), hd(State#state.partitions)),
    update_request(State#state.peer, hd(State#state.partitions)),
    {next_state, update, State, State#state.timeout};

update(timeout, State=#state{peer=Peer}) ->
    lager:error("metadata exchange with ~p timed out updating trees", [Peer]),
    {stop, normal, State};

update(tree_updated, State) ->
    Built = State#state.built + 1,
    case Built of
        2 ->
            {next_state, exchange, State, 0};
        _ ->
            {next_state, update, State#state{built=Built}}
    end;

update({update_error, _Error}, State) ->
    {stop, normal, State}.


exchange(timeout, #state{peer = Peer, partitions = [Partition|_]} = State) ->
    RemoteFun = fun
        (Prefixes, {get_bucket, {Level, Bucket}}) ->
            pdb_hashtree:get_bucket(Peer, Partition, Prefixes, Level, Bucket);
        (Prefixes, {key_hashes, Segment}) ->
            pdb_hashtree:key_hashes(Peer, Partition, Prefixes, Segment)
    end,
    HandlerFun = fun(Diff, Acc) ->
        repair(Peer, Diff),
        track_repair(Diff, Acc)
    end,
    Res = pdb_hashtree:compare(
        Partition,
        RemoteFun,
        HandlerFun,
        #exchange{local = 0, remote = 0, keys = 0}
    ),
    #exchange{
        local = LocalPrefixes,
        remote = RemotePrefixes,
        keys = Keys} = Res,
    Total = LocalPrefixes + RemotePrefixes + Keys,
    case Total > 0 of
        true ->
            lager:info("completed metadata exchange with ~p. repaired ~p missing local prefixes, "
                       "~p missing remote prefixes, and ~p keys", [Peer, LocalPrefixes, RemotePrefixes, Keys]);
        false ->
            lager:debug("completed metadata exchange with ~p. nothing repaired", [Peer])
    end,
    case State#state.partitions of
        [_] ->
            {stop, normal, State};
        [_|T] ->
            %% We remove the covered partition and start again
            {next_state, prepare, State#state{partitions = T}}
    end.



prepare(_Event, _From, State) ->
    {reply, ok, prepare, State}.


update(_Event, _From, State) ->
    {reply, ok, update, State}.


exchange(_Event, _From, State) ->
    {reply, ok, exchange, State}.



%% =============================================================================
%% PRIVATE
%% =============================================================================



%% @private
repair(Peer, {missing_prefix, Type, Prefix}) ->
    repair_prefix(Peer, Type, Prefix);

repair(Peer, {key_diffs, Prefix, Diffs}) ->
    _ = [repair_keys(Peer, Prefix, Diff) || Diff <- Diffs],
    ok.


%% @private
repair_prefix(Peer, Type, [Prefix]) ->
    ItType = repair_iterator_type(Type),
    repair_sub_prefixes(Type, Peer, Prefix, repair_iterator(ItType, Peer, Prefix));

repair_prefix(Peer, Type, [Prefix, SubPrefix]) ->
    FullPrefix = {Prefix, SubPrefix},
    ItType = repair_iterator_type(Type),
    repair_full_prefix(Type, Peer, FullPrefix, repair_iterator(ItType, Peer, FullPrefix)).


%% @private
repair_sub_prefixes(Type, Peer, Prefix, It) ->
    case pdb:iterator_done(It) of
        true ->
            pdb:iterator_close(It);
        false ->
            SubPrefix = pdb:iterator_value(It),
            FullPrefix = {Prefix, SubPrefix},

            ItType = repair_iterator_type(Type),
            ObjIt = repair_iterator(ItType, Peer, FullPrefix),
            repair_full_prefix(Type, Peer, FullPrefix, ObjIt),
            repair_sub_prefixes(Type, Peer, Prefix, pdb:iterate(It))
    end.


%% @private
repair_full_prefix(Type, Peer, FullPrefix, ObjIt) ->
    case pdb:iterator_done(ObjIt) of
        true ->
            pdb:iterator_close(ObjIt);
        false ->
            {Key, Obj} = pdb:iterator_value(ObjIt),
            repair_other(Type, Peer, {FullPrefix, Key}, Obj),
            repair_full_prefix(Type, Peer, FullPrefix, pdb:iterate(ObjIt))
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
    LocalObj = pdb:get(PKey),
    RemoteObj = pdb:get(Peer, PKey),
    merge(undefined, PKey, RemoteObj),
    merge(Peer, PKey, LocalObj),
    ok.


%% @private
%% context is ignored since its in object, so pass undefined
merge(undefined, PKey, RemoteObj) ->
    pdb:merge({PKey, undefined}, RemoteObj);
merge(Peer, PKey, LocalObj) ->
    pdb:merge(Peer, {PKey, undefined}, LocalObj).


%% @private
repair_iterator(local, _, Prefix)
when is_atom(Prefix) orelse is_binary(Prefix) ->
    pdb:iterator(Prefix);
repair_iterator(local, _, Prefix) when is_tuple(Prefix) ->
    pdb:iterator(Prefix, undefined);
repair_iterator(remote, Peer, PrefixOrFull) ->
    pdb:remote_iterator(Peer, PrefixOrFull).


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


%% @private
remote_lock_request(Peer, Partition) ->
    Self = self(),
    as_event(fun() ->
        Res = pdb_hashtree:lock(Peer, Partition, Self),
        {remote_lock, Res}
    end).


%% @private
update_request(Node, Partition) ->
    as_event(fun() ->
        %% acquired lock so we know there is no other update
        %% and tree is built
        case pdb_hashtree:update(Node, Partition) of
            ok -> tree_updated;
            Error -> {update_error, Error}
        end
    end).


%% @private
%% "borrowed" from riak_kv_exchange_fsm
as_event(F) ->
    Self = self(),
    spawn_link(fun() ->
        Result = F(),
        gen_fsm:send_event(Self, Result)
    end),
    ok.
