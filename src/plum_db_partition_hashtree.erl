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
-module(plum_db_partition_hashtree).
-behaviour(gen_server).


%% default value for aae_hashtree_ttl config option
%% Time in milliseconds after which the hashtree will be reset
%% i.e. destroyed and rebuilt
-define(DEFAULT_TTL, 604800000). %% 1 week


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
    data_root       ::  file:filename(),
    %% the plum_db partition this hashtree represents
    partition       ::  non_neg_integer(),
    %% the tree managed by this process
    tree            ::  hashtree_tree:tree(),
    %% whether or not the tree has been built or a monitor ref
    %% if the tree is being built
    built           ::  boolean() | reference(),
    %% Timestamp when the tree was build. To be used together with ttl
    %% to calculate if the hashtree has expired
    build_timestamp ::  non_neg_integer() | undefined,
    %% Time in milliseconds after which the hashtree will be reset
    ttl             ::  non_neg_integer(),
    %% a monitor reference for a process that currently holds a
    %% lock on the tree
    lock            ::  {internal | external, reference(), pid()} | undefined
}).



%%%===================================================================
%%% API
%%%===================================================================




%% -----------------------------------------------------------------------------
%% @doc Starts the process using {@link start_link/1}, passing in the
%% directory where other cluster data is stored in `data_dir'
%% as the data root.
%% @end
%% -----------------------------------------------------------------------------
-spec start_link(non_neg_integer()) -> {ok, pid()} | ignore | {error, term()}.

start_link(Partition) ->
    PRoot = app_helper:get_env(plum_db, data_dir),
    DataRoot = filename:join([PRoot, "trees", integer_to_list(Partition)]),
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

prefix_hash(Server, Prefix) when is_pid(Server); is_atom(Server) ->
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
-spec release_lock(node(), plum_db:partition(), pid()) -> ok.

release_lock(Node, Partition, Pid) ->
    Type = case node() of
        Node -> internal;
        _ -> external
    end,
    gen_server:call(
        {name(Partition), Node}, {release_lock, Type, Pid}, infinity).


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
    schedule_tick(),
    State = init_async(#state{data_root = DataRoot, partition = Partition}),
    {ok, State}.

handle_call({compare, RemoteFun, HandlerFun, HandlerAcc}, From, State) ->
    maybe_compare_async(From, RemoteFun, HandlerFun, HandlerAcc, State),
    {noreply, State};

handle_call(update, From, State) ->
    State1 = maybe_external_update(From, State),
    {noreply, State1};

handle_call({lock, Pid}, _From, State) ->
    {Reply, State1} = maybe_external_lock(Pid, State),
    {reply, Reply, State1};

handle_call({release_lock, Type, Pid}, _From, State) ->
    {Reply, State1} = do_release_lock(Type, Pid, State),
    {reply, Reply, State1};

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


handle_cast(reset, State0) ->
    _ = lager:info(
        "Resetting hashtree at node ~p due to user request", [node()]),
    State = reset_async(State0),
    {noreply, State};

handle_cast(_Msg, State) ->
    {noreply, State}.


handle_info(
    {'DOWN', BuildRef, process, _Pid, normal},
    #state{built=BuildRef} = State) ->
    State1 = build_done(State),
    {noreply, State1};

handle_info(
    {'DOWN', BuildRef, process, _Pid, Reason},
    #state{built=BuildRef} = State) ->
    lager:error("building tree failed: ~p", [Reason]),
    State1 = build_error(State),
    {noreply, State1};

handle_info(
    {'DOWN', LockRef, process, _Pid, _Reason},
    #state{lock = {_, LockRef, _}} = State) ->
    {_, State1} = do_release_lock(State),
    {noreply, State1};

handle_info(tick, State) ->
    schedule_tick(),
    State1 = maybe_reset_async(State),
    State2 = maybe_build_async(State1),
    State3 = maybe_update_async(State2),
    {noreply, State3}.


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
init_async(#state{data_root = DataRoot, partition = Partition} = State0) ->
    TreeId = list_to_atom("hashtree_" ++ integer_to_list(Partition)),
    Tree = hashtree_tree:new(TreeId, [{data_dir, DataRoot}, {num_levels, 2}]),
    TTL = application:get_env(plum_db, aae_hashtree_ttl, ?DEFAULT_TTL),
    State = State0#state{
        tree = Tree,
        built = false,
        build_timestamp = undefined,
        ttl = TTL,
        lock = undefined
    },
    build_async(State).


%% @private
reset_async(State) ->
    _ = hashtree_tree:destroy(State#state.tree),
    _ = lager:info(
        "Hashtree destroyed; partition=~p, node=~p",
        [State#state.partition, node()]
    ),
    schedule_tick(),
    init_async(State).


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
maybe_external_update(From, #state{built = true, lock = undefined} = State) ->
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
maybe_update_async(#state{built = true, lock = undefined} = State) ->
    update_async(State);

maybe_update_async(State) ->
    State.


%% @private
update_async(State) ->
    update_async(undefined, true, State).


%% @private
update_async(From, Lock, #state{tree = Tree} = State) ->
    Tree2 = hashtree_tree:update_snapshot(Tree),
    Pid = spawn_link(fun() ->
        hashtree_tree:update_perform(Tree2),
        case From of
            undefined -> ok;
            _ -> gen_server:reply(From, ok)
        end
    end),
    State1 = case Lock of
        true -> do_lock(Pid, internal, State);
        false -> State
    end,
    State1#state{tree=Tree2}.


%% @private
maybe_build_async(#state{built = false} = State) ->
    build_async(State);

maybe_build_async(State) ->
    State.

maybe_reset_async(#state{built = true} = State) ->
    Diff = timer:now_diff(os:timestamp(), State#state.build_timestamp),
    case Diff >= State#state.ttl of
        true ->
            reset_async(State);
        false ->
            State
    end;

maybe_reset_async(State) ->
    State.


%% @private
build_async(State) ->
    case application:get_env(plum_db, aae_enabled, true) of
        true ->
            {_Pid, Ref} = spawn_monitor(fun() ->
                Partition = State#state.partition,
                %% We iterate over the whole database
                FullPrefix = {undefined, undefined},
                Iterator = plum_db:iterator(FullPrefix, [{partitions, [Partition]}]),
                _ = lager:info(
                    "Starting hashtree build; partition=~p, node=~p",
                    [Partition, node()]
                ),
                Res = build(Partition, Iterator),
                _ = lager:info(
                    "Finished hashtree build; partition=~p, node=~p",
                    [Partition, node()]
                ),
                Res
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
    State#state{built = true, build_timestamp = os:timestamp()}.

%% @private
build_error(State) ->
    State#state{built=false}.


%% @private
maybe_external_lock(Pid, #state{lock = undefined, built = true} = State) ->
    {ok, do_lock(Pid, external, State)};

maybe_external_lock(_Pid, #state{built = true} = State) ->
    {locked, State};

maybe_external_lock(_Pid, State) ->
    {not_built, State}.


%% @private
do_lock(Pid, Type, State) ->
    LockRef = monitor(process, Pid),
    State#state{lock = {Type, LockRef, Pid}}.


%% @private
do_release_lock(Type, Pid, #state{lock = {Type, LockRef, Pid}} = State) ->
    true = demonitor(LockRef),
    do_release_lock(State);

do_release_lock(_, _, State) ->
    %% Type or Pid mismatch
    {error, State}.


%% @private
do_release_lock(State) ->
    {ok, State#state{lock = undefined}}.


%% @private
prefix_to_prefix_list(Prefix) when is_binary(Prefix) or is_atom(Prefix) ->
    [Prefix];
prefix_to_prefix_list({Prefix, SubPrefix}) ->
    [Prefix,SubPrefix].


%% @private
prepare_pkey({FullPrefix, Key}) ->
    {prefix_to_prefix_list(FullPrefix), term_to_binary(Key)}.


%% @private
schedule_tick() ->
    TickMs = app_helper:get_env(plum_db, hashtree_timer, 10000),
    erlang:send_after(TickMs, ?MODULE, tick).
