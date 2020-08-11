%% =============================================================================
%%  plum_db.erl -
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

-module(plum_db).
-behaviour(gen_server).
-behaviour(plumtree_broadcast_handler).
-include("plum_db.hrl").



-record(state, {
    %% an ets table to hold iterators opened
    %% by other nodes
    iterators           ::  ets:tab()
}).


-record(iterator, {
    %% The query
    match_prefix            ::  plum_db_prefix_pattern(),
    first                   ::  plum_db_pkey() | undefined,
    %% The actual partition iterator
    ref                     ::  plum_db_partition_server:iterator() | undefined,
    %% Pointers :: The current position decomposed into prefix, key and object
    prefix                  ::  plum_db_prefix() | undefined,
    key                     ::  plum_db_pkey() | undefined,
    object                  ::  plum_db_object() | undefined,
    %% Options
    keys_only = false       ::  boolean(),
    partitions              ::  [partition()],
    opts = []               ::  it_opts(),
    done = false            ::  boolean()
}).

-record(remote_iterator, {
    node                    ::  node(),
    ref                     ::  reference(),
    match_prefix            ::  plum_db_prefix() | atom() | binary()
}).

-record(continuation, {
    match_prefix            ::  plum_db_prefix_pattern(),
    match_key               ::  plum_db_pkey_pattern(),
    first                   ::  plum_db_pkey() | undefined,
    opts = []               ::  it_opts()
}).


-type prefix_type()         ::  ram | ram_disk | disk.
-type prefixes()            ::  #{binary() | atom() => prefix_type()}.

-type state()               ::  #state{}.
-type remote_iterator()     ::  #remote_iterator{}.
-opaque iterator()          ::  #iterator{}.
-opaque continuation()      ::  #continuation{}.


%% Get Option Types
-type iterator_element()    ::  {plum_db_pkey(), plum_db_object()}.
-type value_or_values()     ::  [plum_db_value() | plum_db_tombstone()]
                                | plum_db_value() | plum_db_tombstone().
-type fold_fun()            ::  fun(
                                ({plum_db_key(), value_or_values()}, any()) ->
                                    any()
                                ).
-type foreach_fun()         ::  fun(
                                    ({plum_db_key(), value_or_values()}) ->
                                    any()
                                ).
-type fold_elements_fun()    ::  fun(
                                ({plum_db_key(), plum_db_object()}, any()) ->
                                    any()
                                ).
-type get_opt_default_val() ::  {default, plum_db_value()}.
-type get_opt_resolver()    ::  {resolver, plum_db_resolver()}.
-type get_opt_allow_put()   ::  {allow_put, boolean()}.
-type get_opt()             ::  get_opt_default_val()
                                | get_opt_resolver()
                                | get_opt_allow_put().
-type get_opts()            ::  [get_opt()].

%% Iterator Types
-type it_opt_resolver()     ::  {resolver, plum_db_resolver() | lww}.
-type it_opt_default_fun()  ::  fun((plum_db_key()) -> plum_db_value()).
-type it_opt_default()      ::  {default,
                                    plum_db_value() | it_opt_default_fun()}.
-type it_opt_keymatch()     ::  {match, term()}.
-type it_opt_first()        ::  {first, term()}.
-type it_opt_keys_only()    ::  {keys_only, boolean()}.
-type it_opt_partitions()   ::  {partitions, [partition()]}.
-type match_opt_limit()     ::  pos_integer() | infinity.
-type match_opt_remove_tombstones()     ::  boolean().
-type it_opt()              ::  it_opt_resolver()
                                | it_opt_first()
                                | it_opt_default()
                                | it_opt_keymatch()
                                | it_opt_keys_only()
                                | it_opt_partitions().
-type it_opts()             ::  [it_opt()].
-type fold_opts()           ::  it_opts().
-type match_opts()          ::  [
                                    it_opt()
                                    | match_opt_limit()
                                    | match_opt_remove_tombstones()
                                ].
-type partition()           ::  non_neg_integer().

%% Put Option Types
-type put_opts()            :: [].

%% Delete Option types
-type delete_opts()         :: [].


-export_type([prefixes/0]).
-export_type([prefix_type/0]).
-export_type([partition/0]).
-export_type([iterator/0]).
-export_type([continuation/0]).

-export([delete/2]).
-export([delete/3]).
-export([fold/3]).
-export([fold/4]).
-export([foreach/2]).
-export([foreach/3]).
-export([fold_elements/3]).
-export([fold_elements/4]).
-export([get/2]).
-export([get/3]).
-export([match/1]).
-export([match/2]).
-export([match/3]).
-export([get_object/1]).
-export([get_object/2]).
-export([get_partition/1]).
-export([is_partition/1]).
-export([iterate/1]).
-export([iterator/0]).
-export([iterator/1]).
-export([iterator/2]).
-export([iterator_close/1]).
-export([iterator_default/1]).
-export([iterator_done/1]).
-export([iterator_element/1]).
-export([iterator_key/1]).
-export([iterator_key_value/1]).
-export([iterator_key_values/1]).
-export([iterator_prefix/1]).
-export([sync_exchange/1]).
-export([sync_exchange/2]).
-export([merge/3]).
-export([partition_count/0]).
-export([partitions/0]).
-export([prefix_hash/2]).
-export([prefixes/0]).
-export([prefix_type/1]).
-export([put/3]).
-export([put/4]).
-export([remote_iterator/1]).
-export([remote_iterator/2]).
-export([take/2]).
-export([take/3]).
-export([to_list/1]).
-export([to_list/2]).


-export([start_link/0]).

%% gen_server callbacks
-export([init/1]).
-export([handle_call/3]).
-export([handle_cast/2]).
-export([handle_info/2]).
-export([terminate/2]).
-export([code_change/3]).

%% plumtree_broadcast_handler callbacks
-export([broadcast_data/1]).
-export([exchange/1]).
-export([graft/1]).
-export([is_stale/1]).
-export([merge/2]).



%% =============================================================================
%% API
%% =============================================================================



%% -----------------------------------------------------------------------------
%% @doc Start plumtree_metadadata_manager and link to calling process.
%% @end
%% -----------------------------------------------------------------------------
-spec start_link() -> {ok, pid()} | ignore | {error, term()}.

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).


%% -----------------------------------------------------------------------------
%% @private
%% @doc Returns the server identifier assigned to the FullPrefix of the
%% provided Key
%% @end
%% -----------------------------------------------------------------------------
-spec get_partition(term()) -> partition().

get_partition({{'_', _}, _}) ->
    error(badarg);

get_partition({{_, '_'}, _}) ->
    error(badarg);

get_partition({{_, _} = FP, _}) ->
    get_partition(plum_db_config:get(shard_by), FP);

get_partition({_, _} = FP) ->
      case partition_count() > 1 of
        true ->
            %% partition :: 0..(partition_count() - 1)
            erlang:phash2(FP, partition_count() - 1);
        false ->
            0
    end.


%% -----------------------------------------------------------------------------
%% @private
%% @doc
%% @end
%% -----------------------------------------------------------------------------
get_partition(prefix, {{_, _} = FP, _}) ->
    get_partition(FP);

get_partition(prefix, {_, _} = FP) ->
    get_partition(FP);

get_partition(key, {{_, _}, _} = Key) ->
    case partition_count() > 1 of
        true ->
            %% partition :: 0..(partition_count() - 1)
            erlang:phash2(Key, partition_count() - 1);
        false ->
            0
    end;

get_partition(undefined, Key) ->
    get_partition(prefix, Key).



%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
-spec partitions() -> [partition()].

partitions() ->
    [X || X <- lists:seq(0, partition_count() - 1)].


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
-spec partition_count() -> non_neg_integer().

partition_count() ->
    plum_db_config:get(partitions).


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
-spec is_partition(partition()) -> boolean().

is_partition(Id) ->
    Id >= 0 andalso Id =< (partition_count() - 1).



%% -----------------------------------------------------------------------------
%% @doc Same as get(FullPrefix, Key, [])
%% @end
%% -----------------------------------------------------------------------------
-spec get(plum_db_prefix(), plum_db_key()) -> plum_db_value() | undefined.

get(FullPrefix, Key) ->
    get(FullPrefix, Key, []).


%% -----------------------------------------------------------------------------
%% @doc Retrieves the local value stored at the given prefix and key.
%%
%% get/3 can take the following options:
%%
%% * `default': value to return if no value is found, `undefined' if not given.
%% * `resolver': A function that resolves conflicts if they are encountered. If
%% not given last-write-wins is used to resolve the conflicts
%% * `allow_put': whether or not to write and broadcast a resolved value.
%% defaults to `true'.
%%
%% NOTE: an update will be broadcast if conflicts are resolved and
%% `allow_put' is `true'. any further conflicts generated by
%% concurrent writes during resolution are not resolved
%% @end
%% -----------------------------------------------------------------------------
-spec get(plum_db_prefix(), plum_db_key(), get_opts()) ->
    plum_db_value() | undefined.

get({Prefix, SubPrefix} = FullPrefix, Key, Opts)
when (is_binary(Prefix) orelse is_atom(Prefix))
andalso (is_binary(SubPrefix) orelse is_atom(SubPrefix)) ->
    PKey = prefixed_key(FullPrefix, Key),
    Default = get_option(default, Opts, undefined),
    ResolveMethod = get_option(resolver, Opts, lww),
    AllowPut = get_option(allow_put, Opts, true),
    case get_object(PKey) of
        undefined ->
            Default;
        Existing ->
            %% Aa Dotted Version Vector Set is returned.
            %% When reading the value for a subsequent call to put/3 the
            %% context can be obtained using plum_db_object:context/1.
            %% Values can obtained w/ plum_db_object:values/1.
            maybe_tombstone(
                maybe_resolve(PKey, Existing, ResolveMethod, AllowPut), Default)
    end.


%% -----------------------------------------------------------------------------
%% @doc Returns a Dotted Version Vector Set or undefined.
%% When reading the value for a subsequent call to put/3 the
%% context can be obtained using plum_db_object:context/1. Values can
%% obtained w/ plum_db_object:values/1.
%% @end
%% -----------------------------------------------------------------------------
get_object({{Prefix, SubPrefix}, _Key} = PKey)
when (is_binary(Prefix) orelse is_atom(Prefix))
andalso (is_binary(SubPrefix) orelse is_atom(SubPrefix)) ->
    case plum_db_partition_server:get(PKey) of
        {error, not_found} ->
            undefined;
        {ok, Existing} ->
            Existing
    end.


%% -----------------------------------------------------------------------------
%% @doc Same as get/1 but reads the value from `Node'
%% This is function is used by plum_db_exchange_statem.
%% @end
%% -----------------------------------------------------------------------------
-spec get_object(node(), plum_db_pkey()) -> plum_db_object() | undefined.

get_object(Node, PKey) when node() =:= Node ->
    get_object(PKey);

get_object(Node, {{Prefix, SubPrefix}, _Key} = PKey)
when (is_binary(Prefix) orelse is_atom(Prefix))
andalso (is_binary(SubPrefix) orelse is_atom(SubPrefix)) ->
    %% We call the corresponding plum_db_partition_worker instance
    %% in the remote node.
    %% This assumes all nodes have the same number of plum_db partitions.
    gen_server:call(
        {plum_db_partition_worker:name(get_partition(PKey)), Node},
        {get_object, PKey},
        infinity
    ).


%% -----------------------------------------------------------------------------
%% @doc Same as fold(Fun, Acc0, FullPrefix, []).
%% @end
%% -----------------------------------------------------------------------------
-spec fold(fold_fun(), any(), plum_db_prefix_pattern()) -> any().
fold(Fun, Acc0, FullPrefixPattern) ->
    fold(Fun, Acc0, FullPrefixPattern, []).


%% -----------------------------------------------------------------------------
%% @doc Fold over all keys and values stored under a given prefix/subprefix.
%% Available options are the same as those provided to iterator/2. To return
%% early, throw {break, Result} in your fold function.
%% @end
%% -----------------------------------------------------------------------------
-spec fold(fold_fun(), any(), plum_db_prefix_pattern(), fold_opts()) -> any().

fold(Fun, Acc0, FullPrefixPattern, Opts) ->
    It = iterator(FullPrefixPattern, Opts),
    try
        do_fold(Fun, Acc0, It)
    catch
        {break, Result} -> Result
    after
        ok = iterator_close(It)
    end.

%% @private
do_fold(Fun, Acc, It) ->
    case iterator_done(It) of
        true ->
            Acc;
        false ->
            Acc1 = Fun(iterator_key_values(It), Acc),
            do_fold(Fun, Acc1, iterate(It))
    end.



%% -----------------------------------------------------------------------------
%% @doc Same as fold(Fun, Acc0, FullPrefix, []).
%% @end
%% -----------------------------------------------------------------------------
-spec foreach(foreach_fun(), plum_db_prefix_pattern()) -> any().

foreach(Fun, FullPrefixPattern) ->
    foreach(Fun, FullPrefixPattern, []).


%% -----------------------------------------------------------------------------
%% @doc Fold over all keys and values stored under a given prefix/subprefix.
%% Available options are the same as those provided to iterator/2. To return
%% early, throw {break, Result} in your fold function.
%% @end
%% -----------------------------------------------------------------------------
-spec foreach(foreach_fun(), plum_db_prefix_pattern(), fold_opts()) -> any().

foreach(Fun, FullPrefixPattern, Opts) ->
    It = iterator(FullPrefixPattern, Opts),
    try
        do_foreach(Fun, It)
    after
        ok = iterator_close(It)
    end.


%% @private
do_foreach(Fun, It) ->
    case iterator_done(It) of
        true ->
            ok;
        false ->
            _ = Fun(iterator_key_values(It)),
            do_foreach(Fun, iterate(It))
    end.


%% -----------------------------------------------------------------------------
%% @doc Same as fold_elements(Fun, Acc0, FullPrefix, []).
%% @end
%% -----------------------------------------------------------------------------
-spec fold_elements(fold_elements_fun(), any(), plum_db_prefix()) -> any().

fold_elements(Fun, Acc0, FullPrefix) ->
    fold_elements(Fun, Acc0, FullPrefix, []).


%% -----------------------------------------------------------------------------
%% @doc Fold over all elements stored under a given prefix/subprefix.
%% Available options are the same as those provided to iterator/2. To return
%% early, throw {break, Result} in your fold function.
%% @end
%% -----------------------------------------------------------------------------
-spec fold_elements(
    fold_elements_fun(), any(), plum_db_prefix(), fold_opts()) ->
    any().

fold_elements(Fun, Acc0, FullPrefix, Opts) ->
    It = iterator(FullPrefix, Opts),
    try
        do_fold_elements(Fun, Acc0, It)
    catch
        {break, Result} -> Result
    after
        ok = iterator_close(It)
    end.

%% @private
do_fold_elements(Fun, Acc, It) ->
    case iterator_done(It) of
        true ->
            Acc;
        false ->
            Next = Fun(iterator_element(It), Acc),
            do_fold_elements(Fun, Next, iterate(It))
    end.


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
-spec match(continuation()) ->
    {[{plum_db_key(), value_or_values()}], continuation()}
    | ?EOT.

match(#continuation{} = Cont) ->
    FullPrefix = Cont#continuation.match_prefix,
    KeyPattern = Cont#continuation.match_key,
    Opts = Cont#continuation.opts,
    match(FullPrefix, KeyPattern, Opts).


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
-spec match(plum_db_prefix_pattern(), plum_db_pkey_pattern()) ->
    [{plum_db_key(), value_or_values()}].

match(FullPrefix, KeyPattern) ->
    match(FullPrefix, KeyPattern, []).


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
-spec match(plum_db_prefix_pattern(), plum_db_pkey_pattern(), match_opts()) ->
    [{plum_db_key(), value_or_values()}]
    | {[{plum_db_key(), value_or_values()}], continuation()}
    | ?EOT.

match(FullPrefix0, KeyPattern, Opts0) ->
    FullPrefix = normalise_prefix(FullPrefix0),
    %% KeyPattern overrides any match option present in Opts0
    Opts1 = [{match, KeyPattern} | lists:keydelete(match, 1, Opts0)],
    Limit = get_option(limit, Opts1, infinity),
    RemoveTombstones = case get_option(resolver, Opts1, undefined) of
        undefined ->
            false;
        _ ->
            get_option(remove_tombstones, Opts1, false)
    end,
    Fun = fun
        ({_, ?TOMBSTONE}, {Acc, Cnt})
        when Cnt =< Limit andalso RemoveTombstones ->
            {Acc, Cnt};
        ({Key, ValOrVals}, {Acc, Cnt}) when Cnt < Limit ->
            {[{Key, ValOrVals} | Acc], Cnt + 1};
        ({Key, _}, {Acc, _}) ->
            Cont = #continuation{
                match_prefix = FullPrefix,
                match_key = KeyPattern,
                opts = [{first, Key} | Opts1]
            },
            throw({break, {Acc, Cont}})
        end,
    case fold(Fun, {[], 0}, FullPrefix, Opts1) of
        {_, #continuation{}} = Res ->
            Res;
        {[], _} when is_integer(Limit) ->
            ?EOT;
        {L, _} when is_integer(Limit) ->
            {L, ?EOT};
        {L, _} ->
            L
    end.


%% -----------------------------------------------------------------------------
%% @doc Same as to_list(FullPrefix, [])
%% @end
%% -----------------------------------------------------------------------------
-spec to_list(plum_db_prefix()) -> [{plum_db_key(), value_or_values()}].

to_list(FullPrefix) ->
    to_list(FullPrefix, []).


%% -----------------------------------------------------------------------------
%% @doc Return a list of all keys and values stored under a given
%% prefix/subprefix. Available options are the same as those provided to
%% iterator/2.
%% @end
%% -----------------------------------------------------------------------------
-spec to_list(FullPrefix :: plum_db_prefix(), Opts :: fold_opts()) ->
    [{plum_db_key(), value_or_values()}].

to_list(FullPrefix0, Opts) ->
    FullPrefix = normalise_prefix(FullPrefix0),
    Fun = fun({Key, ValOrVals}, Acc) -> [{Key, ValOrVals} | Acc] end,
    fold(Fun, [], FullPrefix, Opts).


%% -----------------------------------------------------------------------------
%% @doc Returns a full-prefix iterator: an iterator for all full-prefixes that
%% have keys stored under them.
%% When done with the iterator, iterator_close/1 must be called.
%% This iterator works across all existing store partitions, treating the set
%% of partitions as a single logical database. As a result, ordering is partial
%% per partition and not global across them.
%%
%% Same as calling `iterator({undefined, undefined})'.
%% @end
%% -----------------------------------------------------------------------------
-spec iterator() -> iterator().

iterator() ->
    iterator({?WILDCARD, ?WILDCARD}).


%% -----------------------------------------------------------------------------
%% @doc Same as calling `iterator(FullPrefix, [])'.
%% @end
%% -----------------------------------------------------------------------------
-spec iterator(plum_db_prefix()) -> iterator().

iterator(FullPrefix) ->
    iterator(FullPrefix, []).


%% -----------------------------------------------------------------------------
%% @doc Return an iterator pointing to the first key stored under a prefix
%%
%% This function can take the following options:
%%
%% * `resolver': either the atom `lww' or a function that resolves conflicts if
%% they are encounted (see get/3 for more details). Conflict resolution is
%% performed when values are retrieved (see iterator_key_value/1 and iterator_key_values/1).
%% If no resolver is provided no resolution is performed. The default is to not
%% provide a resolver.
%% * `allow_put': whether or not to write and broadcast a resolved value.
%% defaults to `true'.
%% * `default': Used when the value an iterator points to is a tombstone. default
%% is either an arity-1 function or a value. If a function, the key the
%% iterator points to is passed as the argument and the result is returned in
%% place of the tombstone. If default is a value, the value is returned in
%% place of the tombstone. This applies when using functions such as
%% iterator_key_values/1 and iterator_key_values/1.
%% * `first' - the key this iterator should start at, equivalent to calling
%% iterator_move/2 passing the key as the second argument.
%% * `match': If match is undefined then all keys will may be visted by the
%% iterator, match can be:
%%     * an erlang term - which will be matched exactly against a key
%%     * '_' - the wilcard term which matches anything
%%     * an erlang tuple containing terms and '_' - if tuples are used as keys
%%     this can be used to iterate over some subset of keys
%% * `partitions': The list of partitions this iterator should cover. If
%% undefined it will cover all partitions (`pdb:partitions/0')
%% * `keys_only': wether to iterate only on keys (default: false)
%%
%% @end
%% -----------------------------------------------------------------------------
-spec iterator(plum_db_prefix_pattern(), it_opts()) -> iterator().

iterator({Prefix, SubPrefix} = FullPrefix, Opts)
when (is_binary(Prefix) orelse is_atom(Prefix))
andalso (is_binary(SubPrefix) orelse is_atom(SubPrefix)) ->
    new_iterator(FullPrefix, Opts).


%% -----------------------------------------------------------------------------
%% @doc Create an iterator on `Node'. This allows for remote iteration by having
%% the worker keep track of the actual iterator (since ets
%% continuations cannot cross node boundaries). The iterator created iterates
%% all full-prefixes.
%% Once created the rest of the iterator API may be used as usual. When done
%% with the iterator, iterator_close/1 must be called
%% @end
%% -----------------------------------------------------------------------------
-spec remote_iterator(node()) -> remote_iterator().

remote_iterator(Node) ->
    remote_iterator(Node, {?WILDCARD, ?WILDCARD}).


-spec remote_iterator(node(), plum_db_prefix()) -> remote_iterator().
remote_iterator(Node, FullPrefix) ->
    remote_iterator(Node, FullPrefix, []).


%% -----------------------------------------------------------------------------
%% @doc Create an iterator on `Node'. This allows for remote iteration
%% by having the worker keep track of the actual iterator
%% (since ets continuations cannot cross node boundaries). When
%% `Perfix' is not a full prefix, the iterator created iterates all
%% sub-prefixes under `Prefix'. Otherse, the iterator iterates all keys
%% under a prefix. Once created the rest of the iterator API may be used as
%% usual.
%% When done with the iterator, iterator_close/1 must be called
%% @end
%% -----------------------------------------------------------------------------
-spec remote_iterator(node(), plum_db_prefix_pattern(), it_opts()) ->
    remote_iterator().

remote_iterator(Node, FullPrefix, Opts) when is_tuple(FullPrefix) ->
    Ref = gen_server:call(
        {?MODULE, Node},
        {open_remote_iterator, self(), FullPrefix, Opts},
        infinity
    ),
    #remote_iterator{ref = Ref, match_prefix = FullPrefix, node = Node}.



%% -----------------------------------------------------------------------------
%% @doc Advances the iterator by one key, full-prefix or sub-prefix
%% @end
%% -----------------------------------------------------------------------------
-spec iterate(iterator() | remote_iterator()) -> iterator() | remote_iterator().

iterate(#remote_iterator{ref = Ref, node = Node} = I) ->
    _ = gen_server:call({?MODULE, Node}, {iterate, Ref}, infinity),
    I;

iterate(#iterator{done = true} = I) ->
    %% No more partitions to cover, we are done
    I;

iterate(#iterator{ref = undefined, partitions = []} = I) ->
    %% No more partitions to cover, we are done
    I#iterator{done = true};

iterate(#iterator{ref = undefined, partitions = [H|_]} = I0) ->
    %% We finished with the previous partition and we still have
    %% more partitions to cover
    FullPrefix = I0#iterator.match_prefix,
    Opts = I0#iterator.opts,
    Ref = case I0#iterator.keys_only of
        true ->
            plum_db_partition_server:key_iterator(H, FullPrefix, Opts);
        false ->
            plum_db_partition_server:iterator(H, FullPrefix, Opts)
    end,
    Res = plum_db_partition_server:iterator_move(Ref, I0#iterator.first),
    iterate(Res, I0#iterator{ref = Ref});

iterate(#iterator{ref = Ref} = I) ->
    iterate(plum_db_partition_server:iterator_move(Ref, prefetch), I).


%% @private
-spec iterate(plum_db_partition_server:iterator_move_result(), iterator()) ->
    iterator().

iterate({error, no_match, Ref1}, I0) ->
    %% We carry on trying to match the remaining keys
    iterate(I0#iterator{ref = Ref1});

iterate({error, _, Ref1}, #iterator{partitions = [H|T]} = I) ->
    %% There are no more elements in the partition
    ok = plum_db_partition_server:iterator_close(H, Ref1),
    I1 = iterator_reset_pointers(
        I#iterator{ref = undefined, partitions = T}),
    iterate(I1);

iterate({ok, PKey, Ref1}, I0) ->
    {Prefix, Key} = PKey,
    I0#iterator{
        ref = Ref1,
        prefix = Prefix,
        key = Key,
        object = undefined
    };

iterate({ok, PKey, V, Ref1}, I0) ->
    {Prefix, Key} = PKey,
    I0#iterator{
        ref = Ref1,
        prefix = Prefix,
        key = Key,
        object = V
    }.


%% -----------------------------------------------------------------------------
%% @doc Closes the iterator. This function must be called on all open iterators
%% @end
%% -----------------------------------------------------------------------------
-spec iterator_close(iterator() | iterator() | remote_iterator()) -> ok.

iterator_close(#remote_iterator{ref = Ref, node = Node}) ->
    gen_server:call({?MODULE, Node}, {iterator_close, Ref}, infinity);

iterator_close(#iterator{ref = undefined}) ->
    ok;

iterator_close(#iterator{ref = DBIter, partitions = [H|_]}) ->
    plum_db_partition_server:iterator_close(H, DBIter).


%% -----------------------------------------------------------------------------
%% @doc Returns true if there is nothing more to iterate over
%% @end
%% -----------------------------------------------------------------------------
-spec iterator_done(iterator() | iterator() | remote_iterator()) -> boolean().

iterator_done(#remote_iterator{ref = Ref, node = Node}) ->
    gen_server:call({?MODULE, Node}, {iterator_done, Ref}, infinity);

iterator_done(#iterator{done = true}) ->
    true;

iterator_done(#iterator{ref = undefined, partitions = []}) ->
    true;

iterator_done(#iterator{}) ->
    false.


%% -----------------------------------------------------------------------------
%% @doc Returns the full-prefix being iterated by this iterator.
%% @end
%% -----------------------------------------------------------------------------
-spec iterator_prefix(iterator() | remote_iterator()) -> plum_db_prefix().

iterator_prefix(#remote_iterator{ref = Ref, node = Node}) ->
    gen_server:call({?MODULE, Node}, {prefix, Ref}, infinity);

iterator_prefix(#iterator{prefix = Prefix}) ->
    Prefix.




%% -----------------------------------------------------------------------------
%% @doc Return the key pointed at by the iterator. Before calling this function,
%% check the iterator is not complete w/ iterator_done/1. No conflict resolution
%% will be performed as a result of calling this function.
%% @end
%% -----------------------------------------------------------------------------
-spec iterator_key(iterator()) -> plum_db_key() | undefined.

iterator_key(#iterator{key = Key}) ->
    Key.


%% -----------------------------------------------------------------------------
%% @doc Returns a single value pointed at by the iterator.
%% If there are conflicts and a resolver was
%% specified in the options when creating this iterator, they will be resolved.
%% Otherwise, and error is returned.
%% If conflicts are resolved, the resolved value is written locally and a
%% broadcast is performed to update other nodes
%% in the cluster if `allow_put' is `true' (the default value). If `allow_put'
%% is `false', values are resolved but not written or broadcast.
%%
%% NOTE: if resolution may be performed this function must be called at most
%% once before calling iterate/1 on the iterator (at which point the function
%% can be called once more).
%% @end
%% -----------------------------------------------------------------------------
-spec iterator_key_value(iterator() | remote_iterator() | iterator()) ->
    {plum_db_key() , plum_db_value()} | {error, conflict}.

iterator_key_value(#iterator{opts = Opts} = I) ->
    Default = iterator_default(I),
    Key = I#iterator.key,
    PKey = {I#iterator.prefix, Key},
    Obj = I#iterator.object,
    AllowPut = get_option(allow_put, Opts, true),
    case get_option(resolver, Opts, undefined) of
        undefined ->
            case plum_db_object:value_count(Obj) of
                1 ->
                    Value = maybe_tombstone(plum_db_object:value(Obj), Default),
                    {Key, Value};
                _ ->
                    {error, conflict}
            end;
        Resolver ->
            Value = maybe_tombstone(
                maybe_resolve(PKey, Obj, Resolver, AllowPut), Default),
            {Key, Value}
    end;

iterator_key_value(#remote_iterator{ref = Ref, node = Node}) ->
    gen_server:call({?MODULE, Node}, {iterator_key_value, Ref}, infinity).


%% -----------------------------------------------------------------------------
%% @doc Return the key and all sibling values pointed at by the iterator.
%% Before calling this function, check the iterator is not complete w/
%% iterator_done/1.
%% If a resolver was passed to iterator/0 when creating the given iterator,
%% siblings will be resolved using the given function or last-write-wins (if
%% `lww' is passed as the resolver). If no resolver was used then no conflict
%% resolution will take place.
%% If conflicts are resolved, the resolved value is written to
%% local store and a broadcast is submitted to update other nodes in the
%% cluster if `allow_put' is `true'. If `allow_put' is `false' the values are
%% resolved but are not written or broadcast. A single value is returned as the
%% second element of the tuple in the case values are resolved. If no
%% resolution takes place then a list of values will be returned as the second
%% element (even if there is only a single sibling).
%%
%% NOTE: if resolution may be performed this function must be called at most
%% once before calling iterate/1 on the iterator (at which point the function
%% can be called once more).
%% @end
%% -----------------------------------------------------------------------------
-spec iterator_key_values(iterator()) -> {plum_db_key(), value_or_values()}.

iterator_key_values(#iterator{opts = Opts} = I) ->
    Default = iterator_default(I),
    Key = I#iterator.key,
    Obj = I#iterator.object,
    AllowPut = get_option(allow_put, Opts, true),
    case get_option(resolver, Opts, undefined) of
        undefined ->
            {Key, maybe_tombstones(plum_db_object:values(Obj), Default)};
        Resolver ->
            Prefix = I#iterator.prefix,
            Value = maybe_tombstone(
                maybe_resolve({Prefix, Key}, Obj, Resolver, AllowPut), Default),
            {Key, Value}
    end.


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
-spec iterator_element(iterator() | iterator() | remote_iterator()) ->
    iterator_element().

iterator_element(#remote_iterator{ref = Ref, node = Node}) ->
    gen_server:call({?MODULE, Node}, {iterator_element, Ref}, infinity);

iterator_element(#iterator{prefix = P, key = K, object = Obj}) ->
    {{P, K}, Obj}.


%% -----------------------------------------------------------------------------
%% @doc Returns the value returned when an iterator points to a tombstone. If
%% the default used when creating the given iterator is a function it will be
%% applied to the current key the iterator points at. If no default was
%% provided the tombstone value was returned.
%% This function should only be called after checking iterator_done/1.
%% @end
%% -----------------------------------------------------------------------------
-spec iterator_default(iterator() | iterator()) ->
    plum_db_tombstone() | plum_db_value() | it_opt_default_fun().

iterator_default(#iterator{opts = []}) ->
    ?TOMBSTONE;

iterator_default(#iterator{opts = Opts} = I) ->
    case proplists:get_value(default, Opts, ?TOMBSTONE) of
        Fun when is_function(Fun) ->
            Fun(iterator_key(I));
        Val -> Val
    end.


%% -----------------------------------------------------------------------------
%% @doc Return the local hash associated with a full-prefix or prefix. The hash
%% value is updated periodically and does not always reflect the most recent
%% value. This function can be used to determine when keys stored under a
%% full-prefix or prefix have changed.
%% If the tree has not yet been updated or there are no keys stored the given
%% (full-)prefix. `undefined' is returned.
%% @end
%% -----------------------------------------------------------------------------
-spec prefix_hash(partition(), plum_db_prefix()) -> binary() | undefined.

prefix_hash(Partition, {_, _} = Prefix) ->
    plum_db_partition_hashtree:prefix_hash(Partition, Prefix).


%% -----------------------------------------------------------------------------
%% @doc Returns a mapping of prefixes (the first element of a plum_db_prefix()
%% tuple) to prefix_type() only for those prefixes for which a type was
%% declared using the application optiont `prefixes'.
%% @end
%% -----------------------------------------------------------------------------
-spec prefixes() -> prefixes().

prefixes() ->
    plum_db_config:get(prefixes).


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
-spec prefix_type(term()) -> prefix_type() | undefined.

prefix_type(Prefix) ->
    maps:get(Prefix, plum_db_config:get(prefixes), undefined).


%% -----------------------------------------------------------------------------
%% @doc Same as put(FullPrefix, Key, Value, [])
%% @end
%% -----------------------------------------------------------------------------
-spec put(
    plum_db_prefix(), plum_db_key(), plum_db_value() | plum_db_modifier()) -> ok.

put(FullPrefix, Key, ValueOrFun) ->
    put(FullPrefix, Key, ValueOrFun, []).


%% -----------------------------------------------------------------------------
%% @doc Stores or updates the value at the given prefix and key locally and then
%% triggers a broadcast to notify other nodes in the cluster. Currently, there
%% are no put options.
%%
%% NOTE: because the third argument to this function can be a plum_db_modifier(),
%% used to resolve conflicts on write, values cannot be functions.
%% To store functions wrap them in another type like a tuple.
%% @end
%% -----------------------------------------------------------------------------
-spec put(
    plum_db_prefix(),
    plum_db_key(),
    plum_db_value() | plum_db_modifier(),
    put_opts()) ->
    ok.

put({Prefix, SubPrefix} = FullPrefix, Key, ValueOrFun, _Opts)
when (is_binary(Prefix) orelse is_atom(Prefix))
andalso (is_binary(SubPrefix) orelse is_atom(SubPrefix)) ->
    PKey = prefixed_key(FullPrefix, Key),
    Context = current_context(PKey),
    Updated = put_with_context(PKey, Context, ValueOrFun),
    broadcast(PKey, Updated).


%% -----------------------------------------------------------------------------
%% @doc Same as delete(FullPrefix, Key, [])
%% @end
%% -----------------------------------------------------------------------------
-spec delete(plum_db_prefix(), plum_db_key()) -> ok.

delete(FullPrefix, Key) ->
    delete(FullPrefix, Key, []).


%% -----------------------------------------------------------------------------
%% @doc Logically deletes the value associated with the given prefix
%% and key locally and then triggers a broradcast to notify other nodes in the
%% cluster. Currently there are no delete options.
%%
%% NOTE: currently deletion is logical and no GC is performed.
%% @end
%% -----------------------------------------------------------------------------
-spec delete(plum_db_prefix(), plum_db_key(), delete_opts()) -> ok.

delete(FullPrefix, Key, _Opts) ->
    put(FullPrefix, Key, ?TOMBSTONE, []).


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
-spec take(plum_db_prefix(), plum_db_key()) -> plum_db_value() | undefined.

take(FullPrefix, Key) ->
    take(FullPrefix, Key, []).


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
-spec take(plum_db_prefix(), plum_db_key(), get_opts()) ->
    plum_db_value() | undefined.

take({Prefix, SubPrefix} = FullPrefix, Key, Opts)
when (is_binary(Prefix) orelse is_atom(Prefix))
andalso (is_binary(SubPrefix) orelse is_atom(SubPrefix)) ->
    PKey = prefixed_key(FullPrefix, Key),
    Context = current_context(PKey),
    {Existing, Updated} = take_with_context(PKey, Context),
    _ = broadcast(PKey, Updated),

    case Existing of
        undefined ->
            undefined;
        Existing ->
            %% Aa Dotted Version Vector Set is returned.
            %% When reading the value for a subsequent call to put/3 the
            %% context can be obtained using plum_db_object:context/1.
            %% Values can obtained w/ plum_db_object:values/1.
            Default = get_option(default, Opts, undefined),
            ResolveMethod = get_option(resolver, Opts, lww),
            %% We do not want to resolve, since we just deleted and broadcasted
            AllowPut = false,
            maybe_tombstone(
                maybe_resolve(PKey, Existing, ResolveMethod, AllowPut), Default)
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
    ?MODULE = ets:new(
        ?MODULE,
        [
            named_table,
            {keypos, 1},
            {read_concurrency, true},
            {write_concurrency, true}
        ]
    ),
    State = #state{iterators = ?MODULE},
    {ok, State}.


%% @private
-spec handle_call(term(), {pid(), term()}, state()) ->
    {reply, term(), state()}
    | {reply, term(), state(), non_neg_integer()}
    | {noreply, state()}
    | {noreply, state(), non_neg_integer()}
    | {stop, term(), term(), state()}
    | {stop, term(), state()}.

handle_call({open_remote_iterator, Pid, FullPrefix, Opts}, _From, State) ->
    Iterator = new_remote_iterator(Pid, FullPrefix, Opts, State),
    {reply, Iterator, State};

handle_call({iterate, RemoteRef}, _From, State) ->
    Res = from_remote_iterator(fun iterate/1, RemoteRef, State),
    {reply, Res, State};

handle_call({iterator_key_value, RemoteRef}, _From, State) ->
    Res = from_remote_iterator(fun iterator_key_value/1, RemoteRef, State),
    {reply, Res, State};

handle_call({iterator_element, RemoteRef}, _From, State) ->
    Res = from_remote_iterator(fun iterator_element/1, RemoteRef, State),
    {reply, Res, State};

handle_call({iterator_prefix, RemoteRef}, _From, State) ->
    Res = from_remote_iterator(fun iterator_prefix/1, RemoteRef, State),
    {reply, Res, State};

handle_call({iterator_done, RemoteRef}, _From, State) ->
    Res = case
        from_remote_iterator(fun iterator_done/1, RemoteRef, State)
    of
        undefined -> true; % if we don't know about iterator, treat it as done
        Other -> Other
    end,
    {reply, Res, State};

handle_call({iterator_close, RemoteRef}, _From, State) ->
    close_remote_iterator(RemoteRef, State),
    {reply, ok, State}.


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

handle_info({'DOWN', ItRef, process, _Pid, _Reason}, State) ->
    close_remote_iterator(ItRef, State),
    {noreply, State}.


%% @private
-spec terminate(term(), state()) -> term().

terminate(_Reason, _State) ->
    ok.


%% @private
-spec code_change(term() | {down, term()}, state(), term()) -> {ok, state()}.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.



%% =============================================================================
%% API: PLUMTREE_BROADCAST_HANDLER CALLBACKS
%% =============================================================================



%% -----------------------------------------------------------------------------
%% @doc Deconstructs a broadcast that is sent using
%% `broadcast/2' as the handling module returning the message id
%% and payload.
%% @end
%% -----------------------------------------------------------------------------
-spec broadcast_data(plum_db_broadcast()) ->
    {{plum_db_pkey(), plum_db_context()}, plum_db_object()}.

broadcast_data(#plum_db_broadcast{pkey = Key, obj = Obj}) ->
    Context = plum_db_object:context(Obj),
    {{Key, Context}, Obj}.


%% -----------------------------------------------------------------------------
%% @doc Merges a remote copy of an object record sent via broadcast w/ the
%% local view for the key contained in the message id. If the remote copy is
%% causally older than the current data stored then `false' is returned and no
%% updates are merged. Otherwise, the remote copy is merged (possibly
%% generating siblings) and `true' is returned.
%% @end
%% -----------------------------------------------------------------------------
-spec merge(
    {plum_db_pkey(), undefined | plum_db_context()},
    undefined | plum_db_object()) -> boolean().

merge({PKey, _Context}, Obj) ->
    gen_server:call(
        plum_db_partition_worker:name(get_partition(PKey)),
        {merge, PKey, Obj},
        infinity
    ).


%% -----------------------------------------------------------------------------
%% @doc Same as merge/2 but merges the object on `Node'
%% @end
%% -----------------------------------------------------------------------------
-spec merge(
    node(),
    {plum_db_pkey(), undefined | plum_db_context()},
    plum_db_object()) ->
    boolean().

merge(Node, {PKey, _Context}, Obj) ->
    Partition = get_partition(PKey),
    %% Merge is implemented by the worker as an atomic read-merge-write op
    %% TODO: Evaluate using the merge operation in RocksDB when available
    gen_server:call(
        {plum_db_partition_worker:name(Partition), Node},
        {merge, PKey, Obj},
        infinity
    ).


%% -----------------------------------------------------------------------------
%% @doc Returns false if the update (or a causally newer update) has already
%% been received (stored locally).
%% @end
%% -----------------------------------------------------------------------------
-spec is_stale({plum_db_pkey(), plum_db_context()}) -> boolean().

is_stale({PKey, Context}) ->
    Existing = case ?MODULE:get_object(PKey) of
        {error, not_found} -> undefined;
        Obj -> Obj
    end,
    plum_db_object:is_stale(Context, Existing).


%% -----------------------------------------------------------------------------
%% @doc Returns the object associated with the given key and context
%% (message id) if the currently stored version has an equal context. Otherwise
%% stale is returned.
%% Because it assumed that a grafted context can only be causally older than
%% the local view a stale response means there is another message that subsumes
%% the grafted one.
%% @end
%% -----------------------------------------------------------------------------
-spec graft({plum_db_pkey(), plum_db_context()}) ->
    stale | {ok, plum_db_object()} | {error, term()}.

graft({PKey, Context}) ->
    case ?MODULE:get_object(PKey) of
        {error, not_found} ->
            %% There would have to be a serious error in implementation to hit
            %% this case.
            %% Catch if here b/c it would be much harder to detect
            _ = lager:error(
                "Object not found during graft; key=~p", [PKey]),
            {error, {not_found, PKey}};
         Obj ->
            graft(Context, Obj)
    end.

graft(Context, Obj) ->
    case plum_db_object:equal_context(Context, Obj) of
        false ->
            %% when grafting the context will never be causally newer
            %% than what we have locally. Since its not equal, it must be
            %% an ancestor. Thus we've sent another, newer update that contains
            %% this context's information in addition to its own.  This graft
            %% is deemed stale
            stale;
        true ->
            {ok, Obj}
    end.


%% -----------------------------------------------------------------------------
%% @doc Triggers an asynchronous exchange
%% @end
%% -----------------------------------------------------------------------------
-spec exchange(node()) -> {ok, pid()} | {error, term()}.

exchange(Peer) ->
    exchange(Peer, #{}).


%% -----------------------------------------------------------------------------
%% @doc Triggers an asynchronous exchange
%% @end
%% -----------------------------------------------------------------------------
-spec exchange(node(), map()) -> {ok, pid()} | {error, term()}.

exchange(Peer, Opts0) ->
    case plum_db_config:get(aae_enabled, true) of
        true ->
            Opts1 = maps:merge(#{timeout => 60000}, Opts0),

            case plum_db_exchanges_sup:start_exchange(Peer, Opts1) of
                {ok, Pid} ->
                    {ok, Pid};
                {error, Reason} ->
                    {error, Reason}
            end;
        false ->
            {error, aae_disabled}
    end.



%% -----------------------------------------------------------------------------
%% @doc Triggers a synchronous exchange
%% @end
%% -----------------------------------------------------------------------------
-spec sync_exchange(node()) -> ok | {error, term()}.

sync_exchange(Peer) ->
    sync_exchange(Peer, #{}).


%% -----------------------------------------------------------------------------
%% @doc Triggers a synchronous exchange
%% @end
%% -----------------------------------------------------------------------------
-spec sync_exchange(node(), map()) -> ok | {error, term()}.

sync_exchange(Peer, Opts0) ->
    Timeout = 60000,
    Opts1 = maps:merge(#{timeout => Timeout}, Opts0),

    case plum_db_exchanges_sup:start_exchange(Peer, Opts1) of
        {ok, Pid} ->
            Ref = erlang:monitor(process, Pid),
            receive
                {'DOWN', Ref, process, Pid, normal} ->
                    ok;
                {'DOWN', Ref, process, Pid, Reason} ->
                    {error, Reason}
            after
                Timeout + 1000 ->
                    {error, timeout}
            end;
        {error, Reason} ->
            {error, Reason}
    end.



%% =============================================================================
%% PRIVATE
%% =============================================================================



%% @private
iterator_reset_pointers(#iterator{} = I) ->
    I#iterator{prefix = undefined, key = undefined, object = undefined}.


%% @private
current_context(PKey) ->
    case plum_db_partition_server:get(PKey) of
        {ok, CurrentMeta} -> plum_db_object:context(CurrentMeta);
        {error, not_found} -> plum_db_object:empty_context()
    end.


%% -----------------------------------------------------------------------------
%% @private
%% @doc The most recently read context
%% should be passed as the second argument to prevent unneccessary
%% siblings.
%% Context is a dvvset.
%% @end
%% -----------------------------------------------------------------------------
-spec put_with_context(
    plum_db_pkey_pattern(), undefined | plum_db_context(), term()) -> plum_db_object().

put_with_context({?WILDCARD, _} = PKey, _, _) ->
    error(badarg, [PKey]);

put_with_context({{_, _}, _} = PKey, undefined, ValueOrFun) ->
    %% empty list is an empty dvvset
    put_with_context(PKey, [], ValueOrFun);

put_with_context({{Prefix, SubPrefix}, _Key} = PKey, Context, ValueOrFun)
when (is_binary(Prefix) orelse is_atom(Prefix))
andalso (is_binary(SubPrefix) orelse is_atom(SubPrefix)) ->
    gen_server:call(
        plum_db_partition_worker:name(get_partition(PKey)),
        {put, PKey, Context, ValueOrFun},
        infinity
    ).



-spec take_with_context(
    plum_db_pkey_pattern(), undefined | plum_db_context()) ->
        {Existing :: plum_db_object() | undefined, New :: plum_db_object()}.

take_with_context({?WILDCARD, _} = PKey, _) ->
    error(badarg, [PKey]);

take_with_context({{_, _}, _} = PKey, undefined) ->
    %% empty list is an empty dvvset
    take_with_context(PKey, []);

take_with_context({{Prefix, SubPrefix}, _Key} = PKey, Context)
when (is_binary(Prefix) orelse is_atom(Prefix))
andalso (is_binary(SubPrefix) orelse is_atom(SubPrefix)) ->
    gen_server:call(
        plum_db_partition_worker:name(get_partition(PKey)),
        {take, PKey, Context},
        infinity
    ).


%% @private
maybe_resolve(PKey, Existing, Method, AllowPut) ->
    SibCount = plum_db_object:value_count(Existing),
    maybe_resolve(PKey, Existing, SibCount, Method, AllowPut).


%% @private
maybe_resolve(_PKey, Existing, 1, _Method, _AllowPut) ->
    plum_db_object:value(Existing);

maybe_resolve(PKey, Existing, _, Method, AllowPut) ->
    Reconciled = plum_db_object:resolve(Existing, Method),
    RContext = plum_db_object:context(Reconciled),
    RValue = plum_db_object:value(Reconciled),
    case AllowPut of
        false ->
            ok;
        true ->
            Stored = put_with_context(PKey, RContext, RValue),
            broadcast(PKey, Stored)
    end,
    RValue.


%% @private
maybe_tombstones(Values, Default) ->
    [maybe_tombstone(Value, Default) || Value <- Values].


%% @private
maybe_tombstone(?TOMBSTONE, Default) ->
    Default;
maybe_tombstone(Value, _Default) ->
    Value.


%% @private
broadcast(PKey, Obj) ->
    case plum_db_config:get(aae_enabled, true) of
        true ->
            Broadcast = #plum_db_broadcast{pkey = PKey, obj = Obj},
            plumtree_broadcast:broadcast(Broadcast, plum_db);
        false ->
            ok
    end.


%% @private
-spec prefixed_key(plum_db_prefix(), plum_db_key()) -> plum_db_pkey().
prefixed_key(FullPrefix, Key) ->
    {FullPrefix, Key}.


%% @private
get_option(Key, Opts, Default) ->
    case lists:keyfind(Key, 1, Opts) of
        {Key, Value} ->
            Value;
        _ ->
            Default
    end.

%% @private
new_remote_iterator(Pid, FullPrefix, Opts, #state{iterators = Iterators}) ->
    Ref = monitor(process, Pid),
    Iterator = new_iterator(FullPrefix, Opts),
    ets:insert(Iterators, [{Ref, Iterator}]),
    Ref.


%% @private
from_remote_iterator(Fun, Ref, State) ->
    case ets:lookup(State#state.iterators, Ref) of
        [] ->
            undefined;
        [{Ref, It}] ->
            case Fun(It) of
                #iterator{} = It1 ->
                    true = ets:insert(State#state.iterators, [{Ref, It1}]),
                    It1;
                Other ->
                    Other
            end
    end.


%% @private
close_remote_iterator(Ref, #state{iterators = Iterators} = State) ->
    from_remote_iterator(fun iterator_close/1, Ref, State),
    ets:delete(Iterators, Ref).


%% @private
new_iterator(FullPrefix, Opts) ->
    FirstKey = case proplists:get_value(first, Opts, undefined) of
        undefined -> FullPrefix;
        Key -> {FullPrefix, Key}
    end,
    KeysOnly = proplists:get_value(keys_only, Opts, false),
    Partitions = case get_option(partitions, Opts, undefined) of
        undefined ->
            get_covering_partitions(FullPrefix);
        L ->
            All = sets:from_list(plum_db:partitions()),
            sets:is_subset(sets:from_list(L), All) orelse
            error(badarg, partitions),
            L
    end,
    I = #iterator{
        match_prefix = FullPrefix,
        first = FirstKey,
        keys_only = KeysOnly,
        partitions = Partitions,
        opts = Opts
    },
    %% We fetch the first key
    iterate(I).



%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
get_covering_partitions({'_', _}) ->
    partitions();
get_covering_partitions({_, '_'}) ->
    partitions();
get_covering_partitions(FullPrefix) ->
    [get_partition(FullPrefix)].


%% @private
normalise_prefix({?WILDCARD, _})  ->
    %% If the Prefix is a wilcard the fullprefix is a wilcard
    {?WILDCARD, ?WILDCARD};
normalise_prefix(FullPrefix) when tuple_size(FullPrefix) =:= 2 ->
    FullPrefix.
