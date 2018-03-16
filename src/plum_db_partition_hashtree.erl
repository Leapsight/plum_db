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

%% gen_server callbacks
-export([init/1]).
-export([handle_call/3]).
-export([handle_cast/2]).
-export([handle_info/2]).
-export([terminate/2]).
-export([code_change/3]).

-include("plum_db.hrl").


-record(state, {
    partition   :: non_neg_integer(),

    %% the tree managed by this process
    tree        :: hashtree_tree:tree(),

    %% whether or not the tree has been built or a monitor ref
    %% if the tree is being built
    built       :: boolean() | reference(),

    %% a monitor reference for a process that currently holds a
    %% lock on the tree. undefined otherwise
    lock        :: {internal | external, reference(), pid()} | undefined
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
    plum_db:partition() | pid() | atom(), plum_db_prefix() | binary() | atom()) ->
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
        Node ->
            internal;
        _ ->
            external
    end,
    gen_server:call(
        {name(Partition), Node}, {release_lock, Type, Pid}, infinity).


%% -----------------------------------------------------------------------------
%% @doc Updates the tree on this node.
%% @see update/2
%% @end
%% -----------------------------------------------------------------------------
-spec update(plum_db:partition()) -> ok | not_locked | not_built | ongoing_update.
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
    TreeId = list_to_atom("hashtree_" ++ integer_to_list(Partition)),
    Tree = hashtree_tree:new(TreeId, [{data_dir, DataRoot}, {num_levels, 2}]),
    State = #state{
        partition = Partition,
        tree = Tree,
        built = false,
        lock = undefined
    },
    State1 = build_async(State),
    {ok, State1}.

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

handle_call({prefix_hash, Prefix}, _From, State=#state{tree = Tree}) ->
    PrefixList = prefix_to_prefix_list(Prefix),
    PrefixHash = hashtree_tree:prefix_hash(PrefixList, Tree),
    {reply, PrefixHash, State};

handle_call({insert, PKey, Hash, IfMissing}, _From, State=#state{tree = Tree}) ->
    {Prefixes, Key} = prepare_pkey(PKey),
    Tree1 = hashtree_tree:insert(Prefixes, Key, Hash, [{if_missing, IfMissing}], Tree),
    {reply, ok, State#state{tree=Tree1}}.


handle_cast(_Msg, State) ->
    {noreply, State}.


handle_info(
    {'DOWN', BuildRef, process, _Pid, normal}, State=#state{built=BuildRef}) ->
    State1 = build_done(State),
    {noreply, State1};

handle_info(
    {'DOWN', BuildRef, process, _Pid, Reason}, State=#state{built=BuildRef}) ->
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
    State1 = maybe_build_async(State),
    State2 = maybe_update_async(State1),
    {noreply, State2}.


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
maybe_compare_async(
    From, RemoteFun, HandlerFun, HandlerAcc,
    State=#state{built = true, lock = {external, _, _}}) ->
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
maybe_external_update(From, State=#state{built = true, lock = undefined}) ->
    gen_server:reply(From, not_locked),
    State;

maybe_external_update(From, State=#state{built = true, lock = {internal, _, _}}) ->
    gen_server:reply(From, ongoing_update),
    State;

maybe_external_update(From, State=#state{built = true, lock = {external, _, _}}) ->
    update_async(From, false, State);

maybe_external_update(From, State) ->
    gen_server:reply(From, not_built),
    State.


%% @private
maybe_update_async(State=#state{built = true, lock = undefined}) ->
    update_async(State);

maybe_update_async(State) ->
    State.


%% @private
update_async(State) ->
    update_async(undefined, true, State).


%% @private
update_async(From, Lock, State=#state{tree = Tree}) ->
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
maybe_build_async(State=#state{built=false}) ->
    build_async(State);
maybe_build_async(State) ->
    State.


%% @private
build_async(State) ->
    {_Pid, Ref} = spawn_monitor(fun() ->
        Partition = State#state.partition,
        PrefixIt = plum_db:base_iterator(
            {undefined, undefined}, undefined, Partition),
        build(Partition, PrefixIt)
    end),
    State#state{built=Ref}.



%% @private
build(Partition, PrefixIt) ->
    case plum_db:iterator_done(PrefixIt) of
        true ->
            plum_db:iterator_close(PrefixIt);
        false ->
            Prefix = plum_db:iterator_prefix(PrefixIt),
            ObjIt = plum_db:base_iterator(Prefix, undefined, Partition),
            build(Partition, PrefixIt, ObjIt)
    end.


%% @private
build(Partition, PrefixIt, ObjIt) ->
    case plum_db:iterator_done(ObjIt) of
        true ->
            plum_db:iterator_close(ObjIt),
            build(Partition, plum_db:iterate(PrefixIt));
        false ->
            FullPrefix = plum_db:base_iterator_prefix(ObjIt),
            {{_, Key}, Obj} = plum_db:iterator_object(ObjIt),
            Hash = plum_db_object:hash(Obj),
            %% insert only if missing to not clash w/ newer writes during build
            ?MODULE:insert({FullPrefix, Key}, Hash, true),
            build(Partition, PrefixIt, plum_db:iterate(ObjIt))
    end.

%% @private
build_done(State) ->
    State#state{built = true}.

%% @private
build_error(State) ->
    State#state{built=false}.


%% @private
maybe_external_lock(Pid, State=#state{lock = undefined, built = true}) ->
    {ok, do_lock(Pid, external, State)};

maybe_external_lock(_Pid, State=#state{built = true}) ->
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
