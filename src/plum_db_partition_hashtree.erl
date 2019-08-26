%% =============================================================================
%%  plum_db_partition_hashtree.erl -
%%
%%  Copyright (c) 2013 Basho Technologies, Inc.  All Rights Reserved.
%%  Copyright (c) 2017-2019 Ngineo Limited t/a Leapsight. All rights reserved.
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

-module(plum_db_partition_hashtree).
-behaviour(gen_server).


%% default value for aae_hashtree_ttl config option
%% Time in milliseconds after which the hashtree will be reset
%% i.e. destroyed and rebuilt
-define(DEFAULT_TTL, 7 * 24 * 60 * 60). %% 1 week


%% API
-export([compare/4]).
-export([get_bucket/5]).
-export([insert/2]).
-export([insert/3]).
-export([insert/4]).
-export([key_hashes/4]).
-export([lock/1]).
-export([lock/2]).
-export([lock/3]).
-export([release_lock/1]).
-export([release_lock/2]).
-export([release_lock/3]).
-export([name/1]).
-export([prefix_hash/2]).
-export([start_link/1]).
-export([update/1]).
-export([update/2]).
-export([reset/1]).
-export([reset/2]).

%% gen_server callbacks
-export([init/1]).
-export([handle_call/3]).
-export([handle_cast/2]).
-export([handle_info/2]).
-export([terminate/2]).
-export([code_change/3]).

-include("plum_db.hrl").


-record(state, {
    id              ::  atom(),
    data_root       ::  file:filename(),
    %% the plum_db partition this hashtree represents
    partition       ::  non_neg_integer(),
    %% the tree managed by this process
    tree            ::  hashtree_tree:tree() | undefined,
    %% whether or not the tree has been built or a monitor ref
    %% if the tree is being built
    built           ::  boolean() | reference() | undefined,
    %% a monitor reference for a process that currently holds a
    %% lock on the tree
    lock            ::  {internal | external, reference(), pid()} | undefined,
    %% Timestamp when the tree was build. To be used together with ttl_secs
    %% to calculate if the hashtree has expired
    build_ts_secs   ::  non_neg_integer() | undefined,
    %% Time in milliseconds after which the hashtree will be reset
    ttl_secs        ::  non_neg_integer() | undefined,
    reset = false   ::  boolean(),
    timer           ::  reference() | undefined
}).



%%%===================================================================
%%% API
%%%===================================================================




%% -----------------------------------------------------------------------------
%% @doc Starts the process using {@link start_link/1}, passing in the
%% directory where other cluster data is stored in `hashtrees_dir'
%% as the data root.
%% @end
%% -----------------------------------------------------------------------------
-spec start_link(non_neg_integer()) -> {ok, pid()} | ignore | {error, term()}.

start_link(Partition) when is_integer(Partition) ->
    Dir = plum_db_config:get(hashtrees_dir),
    DataRoot = filename:join([Dir, integer_to_list(Partition)]),
    Name = name(Partition),
    gen_server:start_link({local, Name}, ?MODULE, [Partition, DataRoot], []).


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
name(Partition) ->
    list_to_atom(
        "plum_db_partition_" ++ integer_to_list(Partition) ++ "_hashtree").


%% -----------------------------------------------------------------------------
%% @doc Same as insert(PKey, Hash, false).
%% @end
%% -----------------------------------------------------------------------------
-spec insert(plum_db_pkey(), binary()) -> ok.
insert(PKey, Hash) ->
    insert(PKey, Hash, false).


%% -----------------------------------------------------------------------------
%% @doc Insert a hash for a full-prefix and key into the tree
%% managed by the process. If `IfMissing' is `true' the hash is only
%% inserted into the tree if the key is not already present.
%% @end
%% -----------------------------------------------------------------------------
-spec insert(plum_db_pkey(), binary(), boolean()) -> ok.
insert(PKey, Hash, IfMissing) ->
    Name = name(plum_db:get_partition(PKey)),
    gen_server:call(Name, {insert, PKey, Hash, IfMissing}, infinity).


-spec insert(pbd:partition(), plum_db_pkey(), binary(), boolean()) -> ok.
insert(Partition, PKey, Hash, IfMissing) ->
    Name = name(Partition),
    gen_server:call(Name, {insert, PKey, Hash, IfMissing}, infinity).



%% -----------------------------------------------------------------------------
%% @doc Return the hash for the given prefix or full-prefix
%% @end
%% -----------------------------------------------------------------------------
-spec prefix_hash(
    plum_db:partition() | pid() | atom(),
    plum_db_prefix() | binary() | atom()) ->
    undefined | binary().

prefix_hash(Partition, Prefix) when is_integer(Partition) ->
    prefix_hash(name(Partition), Prefix);

prefix_hash(Server, Prefix) when is_pid(Server) orelse is_atom(Server) ->
    gen_server:call(Server, {prefix_hash, Prefix}, infinity).


%% -----------------------------------------------------------------------------
%% @doc Return the bucket for a node in the tree managed by this
%% process running on `Node'.
%% @end
%% -----------------------------------------------------------------------------
-spec get_bucket(
    node(),
    non_neg_integer(),
    hashtree_tree:tree_node(),
    non_neg_integer(),
    non_neg_integer()) -> orddict:orddict().

get_bucket(Node, Partition, Prefixes, Level, Bucket) ->
    gen_server:call(
        {name(Partition), Node},
        {get_bucket, Prefixes, Level, Bucket},
        infinity
    ).


%% -----------------------------------------------------------------------------
%% @doc Return the key hashes for a node in the tree managed by this
%% process running on `Node'.
%% @end
%% -----------------------------------------------------------------------------
-spec key_hashes(
    node(), non_neg_integer(), hashtree_tree:tree_node(), non_neg_integer()) -> orddict:orddict().

key_hashes(Node, Partition, Prefixes, Segment) ->
    gen_server:call(
        {name(Partition), Node}, {key_hashes, Prefixes, Segment}, infinity).


%% -----------------------------------------------------------------------------
%% @doc Locks the tree on this node for updating on behalf of the
%% calling process.
%% @see lock/3
%% @end
%% -----------------------------------------------------------------------------
-spec lock(plum_db:partition()) -> ok | not_built | locked.
lock(Partition) ->
    lock(node(), Partition).


%% -----------------------------------------------------------------------------
%% @doc Locks the tree on `Node' for updating on behalf of the calling
%% process.
%% @see lock/3
%% @end
%% -----------------------------------------------------------------------------
-spec lock(node(), plum_db:partition()) -> ok | not_built | locked.

lock(Node, Partition) ->
    lock(Node, Partition, self()).


%% -----------------------------------------------------------------------------
%% @doc Lock the tree for updating. This function must be called
%% before updating the tree with {@link update/1} or {@link
%% update/2}. If the tree is not built or already locked then the call
%% will fail and the appropriate atom is returned. Otherwise,
%% aqcuiring the lock succeeds and `ok' is returned.
%% @end
%% -----------------------------------------------------------------------------
-spec lock(node(), plum_db:partition(), pid()) -> ok | not_built | locked.

lock(Node, Partition, Pid) ->
    gen_server:call({name(Partition), Node}, {lock, Pid}, infinity).



%% -----------------------------------------------------------------------------
%% @doc Locks the tree on this node for updating on behalf of the
%% calling process.
%% @see lock/3
%% @end
%% -----------------------------------------------------------------------------
-spec release_lock(plum_db:partition()) -> ok.
release_lock(Partition) ->
    release_lock(node(), Partition).


%% -----------------------------------------------------------------------------
%% @doc Locks the tree on `Node' for updating on behalf of the calling
%% process.
%% @see lock/3
%% @end
%% -----------------------------------------------------------------------------
-spec release_lock(node(), plum_db:partition()) -> ok.

release_lock(Node, Partition) ->
    release_lock(Node, Partition, self()).


%% -----------------------------------------------------------------------------
%% @doc Lock the tree for updating. This function must be called
%% before updating the tree with {@link update/1} or {@link
%% update/2}. If the tree is not built or already locked then the call
%% will fail and the appropriate atom is returned. Otherwise,
%% aqcuiring the lock succeeds and `ok' is returned.
%% @end
%% -----------------------------------------------------------------------------
-spec release_lock(node(), plum_db:partition(), pid()) ->
    ok | {error, not_locked | not_allowed}.

release_lock(Node, Partition, Pid) ->
    gen_server:call(
        {name(Partition), Node}, {release_lock, external, Pid}, infinity).


%% -----------------------------------------------------------------------------
%% @doc Updates the tree on this node.
%% @see update/2
%% @end
%% -----------------------------------------------------------------------------
-spec update(plum_db:partition()) ->
    ok | not_locked | not_built | ongoing_update.

update(Partition) ->
    update(node(), Partition).


%% -----------------------------------------------------------------------------
%% @doc Updates the tree on `Node'. The tree must be locked using one
%% of the lock functions. If the tree is not locked or built the
%% update will not be started and the appropriate atom is
%% returned. Although this function should not be called without a
%% lock, if it is and the tree is being updated by the background tick
%% then `ongoing_update' is returned. If the tree is built and a lock
%% has been acquired then the update is started and `ok' is
%% returned. The update is performed asynchronously and does not block
%% the process that manages the tree (e.g. future inserts).
%% @end
%% -----------------------------------------------------------------------------
-spec update(node(), plum_db:partition()) ->
    ok | not_locked | not_built | ongoing_update.

update(Node, Partition) ->
    gen_server:call({name(Partition), Node}, update, infinity).


%% -----------------------------------------------------------------------------
%% @doc Destroys the partition's hashtrees on the local node and rebuilds it.
%% @end
%% -----------------------------------------------------------------------------
-spec reset(plum_db:partition()) -> ok.

reset(Partition) ->
    reset(node(), Partition).


%% -----------------------------------------------------------------------------
%% @doc Destroys the partition's hashtrees on node `Node' and rebuilds it.
%% @end
%% -----------------------------------------------------------------------------
-spec reset(node(), plum_db:partition()) -> ok.

reset(Node, Partition) ->
    gen_server:cast({name(Partition), Node}, reset).


%% -----------------------------------------------------------------------------
%% @doc Compare the local tree managed by this process with the remote
%% tree also managed by a hashtree process. `RemoteFun' is
%% used to access the buckets and segments of nodes in the remote tree
%% and should usually call {@link get_bucket/5} and {@link
%% key_hashes/4}. `HandlerFun' is used to process the differences
%% found between the two trees. `HandlerAcc' is passed to the first
%% invocation of `HandlerFun'. Subsequent calls are passed the return
%% value from the previous call.  This function returns the return
%% value from the last call to `HandlerFun'. {@link hashtree_tree} for
%% more details on `RemoteFun', `HandlerFun' and `HandlerAcc'.
%% @end
%% -----------------------------------------------------------------------------
-spec compare(
    plum_db:partition(),
    hashtree_tree:remote_fun(),
    hashtree_tree:handler_fun(X),
    X) -> X.

compare(Partition, RemoteFun, HandlerFun, HandlerAcc) ->
    gen_server:call(
        name(Partition),
        {compare, RemoteFun, HandlerFun, HandlerAcc},
        infinity).



%% =============================================================================
%% GEN_SERVER CALLBACKS
%% =============================================================================



init([Partition, DataRoot]) ->
    Id = name(Partition),
    State = do_init(#state{
        id = Id, data_root = DataRoot, partition = Partition
    }),
    {ok, State}.

handle_call({compare, RemoteFun, HandlerFun, HandlerAcc}, From, State) ->
    maybe_compare_async(From, RemoteFun, HandlerFun, HandlerAcc, State),
    {noreply, State};

handle_call(update, From, State0) ->
    State1 = maybe_external_update(From, State0),
    {noreply, State1};

handle_call({lock, Pid}, From, State0) ->
    State1 = maybe_external_lock(Pid, From, State0),
    State2 = maybe_reset(State1),
    {noreply, State2};

handle_call({release_lock, Type, Pid}, From, State0) ->
    {Reply, State1} = do_release_lock(Type, Pid, State0),
    gen_server:reply(From, Reply),
    State2 = maybe_reset(State1),
    {noreply, State2};

handle_call({get_bucket, Prefixes, Level, Bucket}, _From, State) ->
    Res = hashtree_tree:get_bucket(Prefixes, Level, Bucket, State#state.tree),
    {reply, Res, State};

handle_call({key_hashes, Prefixes, Segment}, _From, State) ->
    [{_, Res}] = hashtree_tree:key_hashes(Prefixes, Segment, State#state.tree),
    {reply, Res, State};

handle_call({prefix_hash, Prefix}, _From, #state{tree = Tree} = State) ->
    PrefixList = prefix_to_prefix_list(Prefix),
    PrefixHash = hashtree_tree:prefix_hash(PrefixList, Tree),
    {reply, PrefixHash, State};

handle_call(
    {insert, PKey, Hash, IfMissing}, _From, #state{tree = Tree} = State) ->
    {Prefixes, Key} = prepare_pkey(PKey),
    Tree1 = hashtree_tree:insert(Prefixes, Key, Hash, [{if_missing, IfMissing}], Tree),
    {reply, ok, State#state{tree=Tree1}}.


handle_cast(reset, #state{built = true, lock = undefined} = State0) ->
    State1 = do_reset(State0),
    {stop, normal, State1};

handle_cast(reset, #state{built = true, lock = {internal, _, Pid}} = State) ->
    _ = lager:info(
        "Postponing hashtree reset; reason=ongoing_update, lock_owner=~p, "
        "partition=~p, node=~p",
        [Pid, State#state.partition, node()]
    ),
    NewState = schedule_reset(State),
    {noreply, NewState};

handle_cast(reset, #state{built = true, lock = {external, _, Pid}} = State) ->
    _ = lager:info(
        "Postponing hashtree reset; reason=locked, lock_owner=~p, "
        "partition=~p, node=~p",
        [Pid, State#state.partition, node()]
    ),
    NewState = schedule_reset(State),
    {noreply, NewState};

handle_cast(reset, #state{built = false} = State) ->
    _ = lager:info(
        "Skipping hashtree reset; reason=not_built, "
        "partition=~p, node=~p",
        [State#state.partition, node()]
    ),
    {noreply, State#state{reset = false}};

handle_cast(_Msg, State) ->
    {noreply, State}.


handle_info(
    {'DOWN', BuildRef, process, _Pid, normal},
    #state{built=BuildRef} = State) ->
    State1 = build_done(State),
    {noreply, State1};

handle_info(
    {'DOWN', BuildRef, process, _Pid, Reason},
    #state{built = BuildRef} = State) ->

    State1 = build_error(Reason, State),
    {noreply, State1};

handle_info(
    {'DOWN', LockRef, process, Pid, _Reason},
    #state{lock = {Type, LockRef, _}} = State) ->
    {_, State1} = do_release_lock(Type, Pid, State),
    {noreply, State1};

handle_info({timeout, Ref, tick}, #state{timer = Ref} = State) ->
    State1 = maybe_reset(State),
    %% Reset should happen before scheduling tick
    State2 = schedule_tick(State1),
    State3 = maybe_build_async(State2),
    State4 = maybe_update_async(State3),
    {noreply, State4};

handle_info(Event, State) ->
    _ = lager:info("Received unknown event; event=~p", [Event]),
    {noreply, State}.


terminate(_Reason, State0) ->
    {_, State1} = do_release_lock(State0),
    hashtree_tree:destroy(State1#state.tree),
    ok.


code_change(_OldVsn, State, _Extra) ->
    {ok, State}.



%% =============================================================================
%% PRIVATE
%% =============================================================================



%% @private
do_init(#state{data_root = DataRoot, partition = Partition} = State0) ->

    try
        TreeId = list_to_atom("hashtree_" ++ integer_to_list(Partition)),
        Tree = hashtree_tree:new(
            TreeId, [{data_dir, DataRoot}, {num_levels, 2}]),
        TTL = plum_db_config:get(aae_hashtree_ttl, ?DEFAULT_TTL),
        State = State0#state{
            tree = Tree,
            built = false,
            build_ts_secs = undefined,
            ttl_secs = TTL,
            lock = undefined,
            reset = false
        },
        NewState = build_async(State),
        schedule_tick(NewState)
    catch
        _:Reason ->
            {stop, Reason}
    end.


%% @private
do_reset(#state{lock = undefined} = State) ->
    _ = hashtree_tree:destroy(State#state.tree),
    _ = lager:info(
        "Resetting hashtree; partition=~p, node=~p",
        [State#state.partition, node()]
    ),
    do_init(State).


%% @private
maybe_compare_async(
    From, RemoteFun, HandlerFun, HandlerAcc,
    #state{built = true, lock = {external, _, _}} = State) ->
    compare_async(From, RemoteFun, HandlerFun, HandlerAcc, State);

maybe_compare_async(From, _, _, HandlerAcc, _State) ->
    gen_server:reply(From, HandlerAcc).


%% @private
compare_async(From, RemoteFun, HandlerFun, HandlerAcc, #state{tree = Tree}) ->
    spawn_link(fun() ->
        Res = hashtree_tree:compare(Tree, RemoteFun, HandlerFun, HandlerAcc),
        gen_server:reply(From, Res)
    end).


%% @private


maybe_external_update(
    From, #state{built = true, lock = undefined, reset = true} = State) ->
    gen_server:reply(From, ongoing_update),
    %% We will reset on next tick
    State;

maybe_external_update(
    From, #state{built = true, lock = undefined} = State) ->
    gen_server:reply(From, not_locked),
    State;

maybe_external_update(
    From, #state{built = true, lock = {internal, _, _}} = State) ->
    gen_server:reply(From, ongoing_update),
    State;

maybe_external_update(
    From, #state{built = true, lock = {external, _, _}} = State) ->
    update_async(From, false, State);

maybe_external_update(From, State) ->
    gen_server:reply(From, not_built),
    State.


%% @private
maybe_update_async(
    #state{built = true, reset = false, lock = undefined} = State) ->
    update_async(State);

maybe_update_async(State) ->
    State.


%% @private
update_async(State) ->
    update_async(undefined, true, State).


%% @private
update_async(From, Lock, #state{tree = Tree} = State) ->
    Tree2 = hashtree_tree:update_snapshot(Tree),
    Pid = spawn_link(
        fun() ->
            hashtree_tree:update_perform(Tree2),
            case From of
                undefined -> ok;
                _ -> gen_server:reply(From, ok)
            end
        end
    ),
    State1 = case Lock of
        true ->
            %% Lock will be released on process `DOWN` message
            %% by handle_info/2
            do_lock(Pid, internal, State);
        false ->
            State
    end,
    State1#state{tree=Tree2}.


%% @private
maybe_build_async(#state{built = false} = State) ->
    build_async(State);

maybe_build_async(State) ->
    State.


%% @private
maybe_reset(#state{built = true, reset = true, lock = undefined} = State) ->
    do_reset(State);

maybe_reset(#state{built = true, reset = false, lock = undefined} = State) ->
    Diff = erlang:system_time(second) - State#state.build_ts_secs,
    case Diff >= State#state.ttl_secs of
        true ->
            do_reset(State);
        false ->
            State
    end;

maybe_reset(#state{built = false} = State) ->
    State#state{reset = false};

maybe_reset(State) ->
    State.


%% @private
build_async(State) ->
    case plum_db_config:get(aae_enabled, true) of
        true ->
            {_Pid, Ref} = spawn_monitor(fun() ->
                Partition = State#state.partition,
                %% We iterate over the whole database
                FullPrefix = {?WILDCARD, ?WILDCARD},
                Iterator = plum_db:iterator(
                    FullPrefix, [{partitions, [Partition]}]),
                _ = lager:info(
                    "Starting hashtree build; partition=~p, node=~p",
                    [Partition, node()]
                ),
                build(Partition, Iterator)
            end),
            State#state{built = Ref};
        false ->
            State
    end.


%% @private
build(Partition, Iterator) ->
    case plum_db:iterator_done(Iterator) of
        true ->
            plum_db:iterator_close(Iterator);
        false ->
            {{FullPrefix, Key}, Obj} = plum_db:iterator_element(Iterator),
            Hash = plum_db_object:hash(Obj),
            %% insert only if missing to not clash w/ newer writes during build
            ?MODULE:insert(Partition, {FullPrefix, Key}, Hash, true),
            build(Partition, plum_db:iterate(Iterator))
    end.

%% @private
build_done(State) ->
    _ = lager:info(
        "Finished hashtree build; partition=~p, node=~p",
        [State#state.partition, node()]
    ),
    _ = plum_db_events:notify(
        hashtree_build_finished, {ok, State#state.partition}),
    State#state{built = true, build_ts_secs = erlang:system_time(second)}.

%% @private
build_error(Reason, State) ->
    _ = lager:error(
        "Building tree failed; reason=~p, partition=~p",
        [Reason, State#state.partition]
    ),
    _ = plum_db_events:notify(
        hashtree_build_finished, {ok, State#state.partition}),
    State#state{built = false}.


%% @private
maybe_external_lock(
    Pid, From, #state{lock = undefined, built = true} = State) ->
    NewState = do_lock(Pid, external, State),
    gen_server:reply(From, ok),
    NewState;

maybe_external_lock(_, From, #state{built = true} = State) ->
    gen_server:reply(From, locked),
    State;

maybe_external_lock(_, From, State) ->
    gen_server:reply(From, not_built),
    State.


%% @privateaybe
do_lock(Pid, Type, State) ->
    LockRef = monitor(process, Pid),
    State#state{lock = {Type, LockRef, Pid}}.


%% @private
do_release_lock(Type, Pid, #state{lock = {Type, LockRef, Pid}} = State) ->
    true = demonitor(LockRef),
    {ok, State#state{lock = undefined}};

do_release_lock(_, _, #state{lock = undefined} = State) ->
    {{error, not_locked}, State};

do_release_lock(_, _, State) ->
    {{error, not_allowed}, State}.


%% @private
do_release_lock(State) ->
    do_release_lock(internal, self(), State).


%% @private
prefix_to_prefix_list(Prefix) when is_binary(Prefix) or is_atom(Prefix) ->
    [Prefix];
prefix_to_prefix_list({Prefix, SubPrefix}) ->
    [Prefix, SubPrefix].


%% @private
prepare_pkey({FullPrefix, Key}) ->
    {prefix_to_prefix_list(FullPrefix), term_to_binary(Key)}.



%% @private
schedule_reset(State) ->
    schedule_tick(State#state{reset = true}).


%% @private
schedule_tick(State) ->
    ok = cancel_timer(State#state.timer),
    Ms = case State#state.reset of
        true -> 1000;
        false -> plum_db_config:get(hashtree_timer)
    end,
    Ref = erlang:start_timer(Ms, State#state.id, tick),
    State#state{timer = Ref}.


%% @private
cancel_timer(undefined) ->
    ok;
cancel_timer(Ref) ->
    _ = erlang:cancel_timer(Ref),
    ok.