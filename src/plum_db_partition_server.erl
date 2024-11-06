%% =============================================================================
%%  plum_db_partition_server.erl -
%%
%%  Copyright (c) 2017-2021 Leapsight. All rights reserved.
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
%% @doc  A wrapper for an elevelb instance.
%% @end
%% -----------------------------------------------------------------------------
-module(plum_db_partition_server).
-behaviour(partisan_gen_server).
-include_lib("kernel/include/logger.hrl").
-include_lib("partisan/include/partisan.hrl").
-include("plum_db.hrl").
%% -include("utils.hrl").

%% leveldb uses $\0 but since external term format will contain nulls
%% we need an additional separator. We use the ASCII unit separator
%% ($\31) that was design to separate fields of a record.
%% -define(KEY_SEPARATOR, <<0, $\31, 0>>).

-record(state, {
    name                                ::  atom(),
    partition                           ::  non_neg_integer(),
    actor_id                            ::  optional({integer(), node()}),
    db_info                             ::  db_info(),
	config = []							::	opts(),
	data_root							::	file:filename(),
	open_opts = []						::	opts(),
    iterators = #{}                     ::  iterators(),
    helper = undefined                  ::  optional(pid()),
    key_encoder                         ::  plum_db_key:encoder(),
    key_decoder                         ::  plum_db_key:decoder(),
    prefix_encoder                      ::  plum_db_key:prefix_encoder()
}).

-record(db_info, {
    db_ref 								::	optional(rocksdb:db_handle()),
    ram_tab                             ::  atom(),
    ram_disk_tab                        ::  atom(),
	read_opts = []						::	opts(),
    write_opts = []						::	opts(),
    fold_opts = [{fill_cache, false}]	::	opts(),
    key_encoder                         ::  plum_db_key:encoder()
}).

-record(partition_iterator, {
    owner_mref              ::  reference(),
    partition               ::  non_neg_integer(),
    disk                    ::  optional(rocksdb:itr_handle()),
    ram_tab                 ::  optional(ets:tab()),
    ram_disk_tab            ::  optional(ets:tab()),
    full_prefix             ::  plum_db_prefix_pattern(),
    match_pattern           ::  term(),
    bin_prefix              ::  binary(),
    match_spec              ::  optional(ets:comp_match_spec()),
    keys_only = false       ::  boolean(),
    key_decoder             ::  plum_db_key:decoder(),
    prefix_encoder          ::  plum_db_key:prefix_encoder(),
    %% plum_db_pkey() when iterating over ets, but binary() when iterating over
    %% rocksdb
    prev_key                ::  optional(plum_db_pkey() | binary()),
    disk_done = true        ::  boolean(),
    ram_disk_done = true    ::  boolean(),
    ram_done = true         ::  boolean(),
    ram                     ::  optional(key | {cont, any()}),
    ram_disk                ::  optional(key | {cont, any()})
}).

-type state()                   ::  #state{}.
-type opts()                    :: 	[{atom(), term()}].
-type db_info()                 ::  #db_info{}.
-type iterator()                ::  #partition_iterator{}.
-type iterators()               ::  #{reference() => iterator()}.
-type iterator_action()         ::  first | last | next | prev.
-type iterator_action_ext()     ::  iterator_action()
                                    | plum_db_prefix()
                                    | plum_db_pkey()
                                    | binary().
-type iterator_move_result()    ::  {ok,
                                        Key :: binary() | plum_db_pkey(),
                                        Value :: plum_db_object:t(),
                                        iterator()
                                    }
                                    | {ok,
                                        Key :: binary() | plum_db_pkey(),
                                        iterator()
                                    }
                                    | {error, invalid_iterator, iterator()}
                                    | {error, iterator_closed, iterator()}
                                    | {error, no_match, iterator()}.

-export_type([db_info/0]).
-export_type([iterator/0]).
-export_type([iterator_action/0]).
-export_type([iterator_action_ext/0]).
-export_type([iterator_move_result/0]).

-export([byte_size/1]).
-export([dirty_put/5]).
-export([erase/3]).
-export([get/2]).
-export([get/3]).
-export([get/4]).
-export([is_empty/1]).
-export([iterator/2]).
-export([iterator/3]).
-export([iterator_close/2]).
-export([iterator_move/2]).
-export([key_iterator/2]).
-export([key_iterator/3]).
-export([merge/3]).
-export([merge/4]).
-export([name/1]).
-export([put/3]).
-export([put/4]).
-export([put/5]).
-export([start_link/2]).
-export([take/2]).
-export([take/3]).
-export([take/4]).
-export([stats/1]).


%% GEN_SERVER CALLBACKS
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
%% @doc
%% @end
%% -----------------------------------------------------------------------------
-spec start_link(Partition :: non_neg_integer(), Opts :: opts()) -> any().

start_link(Partition, Opts) ->
    Name = name(Partition),
    StartOpts = [
        {channel,  plum_db_config:get(data_channel)},
        {spawn_opt, ?PARALLEL_SIGNAL_OPTIMISATION([{min_heap_size, 1598}])}
    ],
    partisan_gen_server:start_link(
        {local, Name},
        ?MODULE,
        [Name, Partition, Opts],
        StartOpts
    ).


%% -----------------------------------------------------------------------------
%% @doc Fails with `badarg' exception if `Partition' is an invalid partition
%% number.
%% @end
%% -----------------------------------------------------------------------------
%% @private
name(Partition) ->
    Key = {?MODULE, Partition},

    case persistent_term:get(Key, undefined) of
        undefined ->
            plum_db:is_partition(Partition)
                orelse error(badarg),

            Name = list_to_atom(
                "plum_db_partition_" ++ integer_to_list(Partition) ++
                "_server"
            ),
            _ = persistent_term:put(Key, Name),
            Name;
        Name ->
            Name
    end.


stats(Partition) when is_integer(Partition) ->
    stats(name(Partition));

stats(Name) ->
    try get_db_info(Name) of
        #db_info{db_ref = DbRef} ->
            rocksdb:stats(DbRef)
    catch
        _Class:Reason ->
            {error, Reason}
    end.


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
get(Name, PKey) ->
    get(Name, PKey, [], infinity).


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
get(Name, PKey, Opts) ->
    get(Name, PKey, Opts, infinity).


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
get({Name, _} = ServerRef, PKey, Opts, Timeout) when is_atom(Name) ->
    %% A call to a remote node
    partisan_gen_server:call(ServerRef, {get, PKey, Opts}, ?CALL_OPTS(Timeout));

get(Name, PKey, Opts, Timeout) when is_atom(Name) ->
    case key_value:get(allow_put, Opts, false) of
        true ->
            partisan_gen_server:call(Name, {get, PKey, Opts}, Timeout);
        false ->
            try get_db_info(Name) of
                DBInfo ->
                    case do_get(PKey, DBInfo) of
                        {ok, Object} ->
                            maybe_resolve(Object, Opts);
                        {error, _} = Error ->
                            Error
                    end
            catch
                _Class:Reason ->
                    {error, Reason}
            end

    end.


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
put(Name, PKey, ValueOrFun) ->
    put(Name, PKey, ValueOrFun, [], infinity).


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
put(Name, PKey, ValueOrFun, Opts) ->
    put(Name, PKey, ValueOrFun, Opts, infinity).


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
put(Name, PKey, ValueOrFun, Opts, Timeout) when is_atom(Name) ->
    partisan_gen_server:call(Name, {put, PKey, ValueOrFun, Opts}, Timeout).


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
dirty_put(Name, PKey, Object, Opts, Timeout) when is_atom(Name) ->
    partisan_gen_server:call(Name, {dirty_put, PKey, Object, Opts}, Timeout).


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
merge(Name, PKey, Obj) ->
    merge(Name, PKey, Obj, infinity).


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
merge({Name, _} = ServerRef, PKey, Obj, Timeout) when is_atom(Name) ->
    partisan_gen_server:call(ServerRef, {merge, PKey, Obj}, Timeout);

merge(Name, PKey, Obj, Timeout) ->
    partisan_gen_server:call(Name, {merge, PKey, Obj}, ?CALL_OPTS(Timeout)).


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
take(Name, PKey) ->
    take(Name, PKey, [], infinity).


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
take(Name, PKey, Opts) ->
    take(Name, PKey, Opts, infinity).


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
take(Name, PKey, Opts, Timeout) ->
    partisan_gen_server:call(Name, {take, PKey, Opts}, Timeout).


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
erase(Partition, Key, Timeout) when is_integer(Partition) ->
    erase(name(Partition), Key, Timeout);

erase(Name, PKey, Timeout) when is_atom(Name) ->
    partisan_gen_server:call(Name, {erase, PKey}, Timeout).


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
is_empty(Id) when is_integer(Id) ->
    is_empty(name(Id));

is_empty(Store) when is_pid(Store); is_atom(Store) ->
    partisan_gen_server:call(Store, is_empty, infinity).


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
byte_size(Id) when is_integer(Id) ->
    ?MODULE:byte_size(name(Id));

byte_size(Store) when is_pid(Store); is_atom(Store) ->
    partisan_gen_server:call(Store, byte_size, infinity).



%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
iterator(Id, FullPrefix) when is_integer(Id) ->
    iterator(name(Id), FullPrefix);


iterator(Name, FullPrefix) when is_atom(Name) ->
    iterator(Name, FullPrefix, []).


%% -----------------------------------------------------------------------------
%% @doc If the prefix is ground, it restricts the iteration on keys belonging
%% to that prefix and the storage type of the prefix if known. If prefix is
%% undefined or storage type of is undefined, then it starts with disk and
%% follows with ram. It does not cover ram_disk as all data in ram_disk is in
%% disk.
%% @end
%% -----------------------------------------------------------------------------
iterator(Id, FullPrefix, Opts) when is_integer(Id) ->
    iterator(name(Id), FullPrefix, Opts);

iterator(Name, FullPrefix, Opts) when is_atom(Name) andalso is_list(Opts) ->
    Cmd = {iterator, self(), FullPrefix, [{keys_only, false}|Opts]},
    Iter = partisan_gen_server:call(Name, Cmd, infinity),
    true = maybe_safe_fixtables(Iter, true),
    Iter.


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
key_iterator(Id, FullPrefix) when is_integer(Id) ->
    key_iterator(name(Id), FullPrefix);

key_iterator(Name, FullPrefix) when is_atom(Name) ->
    key_iterator(Name, FullPrefix, []).


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
key_iterator(Id, FullPrefix, Opts) when is_integer(Id) ->
    key_iterator(name(Id), FullPrefix, Opts);

key_iterator(Name, FullPrefix, Opts) when is_atom(Name) andalso is_list(Opts) ->
    Cmd = {iterator, self(), FullPrefix, [{keys_only, true}|Opts]},
    Iter = partisan_gen_server:call(Name, Cmd, infinity),
    true = maybe_safe_fixtables(Iter, true),
    Iter.


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
iterator_close(Id, Iter) when is_integer(Id) ->
    iterator_close(name(Id), Iter);

iterator_close(Store, #partition_iterator{} = Iter) when is_atom(Store) ->
    Res = partisan_gen_server:call(Store, {iterator_close, Iter}, infinity),
    true = maybe_safe_fixtables(Iter, false),
    Res.



%% -----------------------------------------------------------------------------
%% @doc Iterates over the storage stack in order (disk -> ram_disk -> ram).
%% @end
%% -----------------------------------------------------------------------------
-spec iterator_move(iterator(), iterator_action_ext()) -> iterator_move_result().

iterator_move(
    #partition_iterator{disk_done = true} = Iter, {undefined, undefined}) ->
    %% We continue with ets so we translate the action
    iterator_move(Iter, first);


iterator_move(#partition_iterator{disk_done = false} = Iter, Term) ->

    DbIter = Iter#partition_iterator.disk,

    case disk_iterator_move(DbIter, rocksdb_action(Term, Iter)) of
        {ok, K, _} when Iter#partition_iterator.keys_only ->
            NewIter = Iter#partition_iterator{prev_key = K},
            case matches_key(K, Iter) of
                {true, Key} ->
                    {ok, Key, NewIter};
                {false, _} ->
                    {error, no_match, NewIter};
                ?EOT ->
                    {error, invalid_iterator, NewIter}
            end;
        {ok, K, Value} ->
            NewIter = Iter#partition_iterator{prev_key = K},
            case matches_key(K, Iter) of
                {true, Key} ->
                    {ok, Key, binary_to_term(Value), NewIter};
                {false, _} ->
                    {error, no_match, NewIter};
                ?EOT ->
                    {error, invalid_iterator, NewIter}
            end;

        {error, Reason}  ->
            %% No more data in rocksdb, maybe we continue with ets
            case next_iterator(disk, Iter) of
                undefined ->
                    {error, Reason, Iter};
                NewIter ->
                    %% We continue in ets so we need to reposition the iterator
                    %% to the first key of the full_prefix
                    iterator_move(NewIter, Iter#partition_iterator.full_prefix)
            end
    end;

iterator_move(#partition_iterator{ram_disk_done = false} = Iter, Action) ->
    ets_iterator_move(ram_disk, Iter#partition_iterator.ram_disk, Iter, Action);

iterator_move(#partition_iterator{ram_done = false} = Iter, Action) ->
    ets_iterator_move(ram, Iter#partition_iterator.ram, Iter, Action);

iterator_move(
    #partition_iterator{
        disk_done = true, ram_done = true, ram_disk_done = true
    } = Iter,
     _) ->
    {error, invalid_iterator, Iter}.



disk_iterator_move(undefined, _) ->
    {error, invalid_iterator};

disk_iterator_move(DbIter, Term) ->
    rocksdb:iterator_move(DbIter, Term).


%% @private
ets_iterator_move(Type, _, Iter, first) ->
    KeysOnly = Iter#partition_iterator.keys_only,
    Tab = table_name(Iter, Type),

    case ets:first(Tab) of
        ?EOT ->
            {error, invalid_iterator, Iter};
        K when KeysOnly ->
            NewIter = update_iterator(Type, Iter, K, key),
            case matches_key(K, Iter) of
                {true, K} ->
                    {ok, K, NewIter};
                {false, _} ->
                    {error, no_match, NewIter};
                ?EOT ->
                    {error, invalid_iterator, NewIter}
            end;
        K ->
            [{K, V}] = ets:lookup(Tab, K),
            NewIter = update_iterator(Type, Iter, K, key),
            case matches_key(K, Iter) of
                {true, K} ->
                    {ok, K, V, NewIter};
                {false, _} ->
                    {error, no_match, NewIter};
                ?EOT ->
                    {error, invalid_iterator, NewIter}
            end
    end;

ets_iterator_move(Type, key, #partition_iterator{} = Iter, next)
when Iter#partition_iterator.prev_key == undefined ->
    ets_iterator_move(Type, key, Iter, first);

ets_iterator_move(Type, _, Iter, last) ->
    KeysOnly = Iter#partition_iterator.keys_only,
    Tab = table_name(Iter, Type),

    case ets:last(Tab) of
        ?EOT ->
            {error, invalid_iterator, Iter};
        K when KeysOnly ->
            NewIter = update_iterator(Type, Iter, K, key),
            case matches_key(K, Iter) of
                {true, K} ->
                    {ok, K, NewIter};
                {false, _} ->
                    {error, no_match, NewIter};
                ?EOT ->
                    {error, invalid_iterator, NewIter}
            end;
        K ->
            [{K, V}] = ets:lookup(Tab, K),
            NewIter = update_iterator(Type, Iter, K, key),
            case matches_key(K, Iter) of
                {true, K} ->
                    {ok, K, V, NewIter};
                {false, _} ->
                    {error, no_match, NewIter};
                ?EOT ->
                    {error, invalid_iterator, NewIter}
            end
    end;
ets_iterator_move(Type, key, #partition_iterator{} = Iter, prev)
when Iter#partition_iterator.prev_key == undefined ->
    ets_iterator_move(Type, key, Iter, last);

ets_iterator_move(Type, key, Iter, next) ->
    KeysOnly = Iter#partition_iterator.keys_only,
    Tab = table_name(Iter, Type),

    case ets:next(Tab, Iter#partition_iterator.prev_key) of
        ?EOT ->
            {error, invalid_iterator, Iter};
        K when KeysOnly ->
            NewIter = update_iterator(Type, Iter, K, key),
            case matches_key(K, Iter) of
                {true, K} ->
                    {ok, K, NewIter};
                {false, _} ->
                    {error, no_match, NewIter};
                ?EOT ->
                    {error, invalid_iterator, NewIter}
            end;
        K ->
            [{K, V}] = ets:lookup(Tab, K),
            NewIter = update_iterator(Type, Iter, K, key),
            case matches_key(K, Iter) of
                {true, K} ->
                    {ok, K, V, NewIter};
                {false, K} ->
                    {error, no_match, NewIter};
                ?EOT ->
                    {error, invalid_iterator, NewIter}
            end
    end;

ets_iterator_move(Type, {cont, Cont0}, Iter, next) ->
    KeysOnly = Iter#partition_iterator.keys_only,

    case ets:select(Cont0) of
        ?EOT ->
            case next_iterator(Type, Iter) of
                undefined ->
                    {error, invalid_iterator, Iter};
                NewIter ->
                    %% We continue in ets so we need to reposition the iterator
                    %% to the first key of the full_prefix
                    iterator_move(NewIter, Iter#partition_iterator.full_prefix)
            end;
        {[{{_, _}, _} = K], Cont1} when KeysOnly == true ->
            NewIter = update_iterator(Type, Iter, K, {cont, Cont1}),
            {ok, K, NewIter};

        {[{{{_, _}, _} = K, V}], Cont1} when KeysOnly == false ->
            NewIter = update_iterator(Type, Iter, K, {cont, Cont1}),
            {ok, K, V, NewIter}
    end;

ets_iterator_move(Type, key, Iter, prev) ->
    KeysOnly = Iter#partition_iterator.keys_only,
    Tab = table_name(Iter, Type),

    case ets:prev(Tab, Iter#partition_iterator.prev_key) of
        ?EOT ->
            %% No more data in ets, maybe we continue with rocksdb
            case prev_iterator(Type, Iter) of
                undefined ->
                    {error, invalid_iterator, Iter};
                NewIter ->
                    iterator_move(NewIter, prev)
            end;

        K when KeysOnly ->
            NewIter = update_iterator(Type, Iter, K, key),
            %% eqwalizer:ignore K
            case matches_key(K, Iter) of
                {true, K} ->
                    {ok, K, NewIter};
                {false, K} ->
                    {error, no_match, NewIter};
                ?EOT ->
                    {error, invalid_iterator, NewIter}
            end;

        K ->
            [{K, V}] = ets:lookup(Tab, K),
            NewIter = update_iterator(Type, Iter, K, key),
            case matches_key(K, Iter) of
                {true, K} ->
                    {ok, K, V, NewIter};
                {false, K} ->
                    {error, no_match, NewIter};
                ?EOT ->
                    {error, invalid_iterator, NewIter}
            end
    end;

ets_iterator_move(Type, {cont, _}, Iter, prev) ->
    %% We were using ets:select/1, to go backwards we need to switch to
    %% key iteration
    K = Iter#partition_iterator.prev_key,
    NewIter = update_iterator(Type, Iter, K, key),
    iterator_move(NewIter, prev);

ets_iterator_move(Type, Cont, Iter, {{_, _} = FullPrefix, ?WILDCARD}) ->
    ets_iterator_move(Type, Cont, Iter, FullPrefix);

ets_iterator_move(Type, _, Iter, {{A, B}, Key}) ->
    Tab = table_name(Iter, Type),
    KeysOnly = Iter#partition_iterator.keys_only,

    Pattern = {{{A, B}, '$1'}, ?WILDCARD},

    Projection = case KeysOnly of
        true ->
            [{element, 1, '$_'}];
        false ->
            ['$_']
    end,


    % We use it as prefix to find first
    Conds = [{'>=', '$1', {const, Key}}],

    MS = [
        {Pattern, Conds, Projection}
    ],

    case ets:select(Tab, MS, 1) of
        ?EOT ->
            {error, invalid_iterator, Iter};

        {[{{_, _}, _} = K], _} when KeysOnly == true ->
            NewIter = update_iterator(Type, Iter, K, key),
            case matches_key(K, Iter) of
                {true, K} ->
                    {ok, K, NewIter};
                {false, K} ->
                    {error, no_match, NewIter};
                ?EOT ->
                    {error, invalid_iterator, NewIter}
            end;

        {[{{{_, _}, _} = K, V}], _} when KeysOnly == false ->
            NewIter = update_iterator(Type, Iter, K, key),
            case matches_key(K, Iter) of
                {true, K} ->
                    {ok, K, V, NewIter};
                {false, K} ->
                    {error, no_match, NewIter};
                ?EOT ->
                    {error, invalid_iterator, NewIter}
            end
    end;

ets_iterator_move(Type, _, Iter, {_, _} = FullPrefix) ->
    Tab = table_name(Iter, Type),
    KeysOnly = Iter#partition_iterator.keys_only,

    Pattern = case Iter#partition_iterator.match_pattern of
        undefined -> FullPrefix;
        KeyPattern -> {FullPrefix, KeyPattern}
    end,

    MatchSpec = ets_match_spec(Pattern, KeysOnly),

    case ets:select(Tab, MatchSpec, 1) of
        ?EOT ->
            {error, invalid_iterator, Iter};

        {[{{_, _}, _} = K], Cont1} when KeysOnly == true ->
            NewIter = update_iterator(Type, Iter, K, {cont, Cont1}),
            {ok, K, NewIter};

        {[{{{_, _}, _} = K, V}], Cont1} when KeysOnly == false ->
            NewIter = update_iterator(Type, Iter, K, {cont, Cont1}),
            {ok, K, V, NewIter}
    end.



%% =============================================================================
%% GEN_SERVER CALLBACKS
%% =============================================================================



init([Name, Partition, Opts]) ->
    %% Seed the random number generator.
    partisan_config:seed(),

    process_flag(trap_exit, true),

    %% eqwalizer:ignore
    DataRoot = filename:join([
        plum_db_config:get(db_dir),
        integer_to_list(Partition)
    ]),

	case filelib:ensure_dir(DataRoot) of
        ok ->
            State0 = init_state(Name, Partition, DataRoot, Opts),
            case open_db(State0) of
                {ok, State1} ->
                    State2 = spawn_helper(State1),
                    ok = set_db_info(Name, State2#state.db_info),
                    {ok, State2};
                {error, Reason} ->
                    {stop, Reason}
            end;
		{error, Reason} ->
		 	{stop, Reason}
    end.


handle_call({get, PKey, Opts}, _From, State) ->
    Reply = case do_get(PKey, State) of
        {ok, Object} ->
            case maybe_resolve(Object, Opts) of
                {ok, Resolved} ->
                    ok = maybe_modify(PKey, Object, Opts, State, Resolved),
                    {ok, Resolved};
                {error, _} = Error ->
                    Error
            end;
        {error, _} = Error ->
            Error
    end,

    {reply, Reply, State};

handle_call({put, PKey, ValueOrFun, Opts}, _From, State) ->
    Reply =
        case modify(PKey, ValueOrFun, Opts, State) of
            {ok, Existing, Result} ->
                ok = on_update(PKey, Result, Existing),
                {ok, Result};
            {error, _} = Error ->
                Error
        end,
    {reply, Reply, State};


handle_call({dirty_put, PKey, Object, Opts}, _From, State) ->
    %% This will crash if error when reason =/= not_found
    {ok, Existing} = do_get(PKey, State, undefined),

    Reply =
        try
            case do_put(PKey, Object, State) of
                ok ->
                    ok = maybe_broadcast(PKey, Object, Opts),
                    ok = on_update(PKey, Object, Existing),
                    {ok, Object};

                {error, _} = Error ->
                    Error
            end
        catch
            Class:Reason:Stacktrace ->
                ?LOG_ERROR(#{
                    description =>
                        "Error while performing a dirty_put operation",
                    class => Class,
                    reason => Reason,
                    stacktrace => Stacktrace,
                    pkey => PKey,
                    object => Object,
                    options => Opts
                }),
                {error, Reason}
        end,
    {reply, Reply, State};

handle_call({take, PKey, Opts}, _From, State) ->
    Reply =
    case modify(PKey, ?TOMBSTONE, Opts, State) of
        {ok, Existing, Result} ->
            ok = on_update(PKey, Result, Existing),
            case maybe_resolve(Existing, Opts) of
                {ok, Resolved} ->
                    {ok, {Resolved, Result}};
                {error, _} = Error ->
                    Error
            end;
        {error, _} = Error ->
            Error
    end,
    %% We ignore allow_put here so we do not call maybe_modify/5
    %% since we just deleted the object, we just respect the user option
    %% to resolve the Existing
    {reply, Reply, State};

handle_call({erase, PKey}, _From, State) ->
    DbRef = db_ref(State),
    Opts = write_opts(State),

    %% This will crash if error when reason =/= not_found
    {ok, Existing} = do_get(PKey, State, undefined),

    ok = maybe_hashtree_delete(PKey, Existing, State),

    Result = case prefix_type(PKey) of
        ram ->
            true = ets:delete(ram_tab(State), PKey),
            ok;
        ram_disk ->
            true = ets:delete(ram_disk_tab(State), PKey),
            Actions = [{delete, encode_key(PKey, State)}],
            result(rocksdb:write(DbRef, Actions, Opts));
        _ ->
            Actions = [{delete, encode_key(PKey, State)}],
            result(rocksdb:write(DbRef, Actions, Opts))
    end,

    %% Maybe callback
    case Result of
        {error, _} ->
            ok;
        _ ->
            ok = on_erase(PKey, Existing)
    end,

    {reply, Result, State};

handle_call({merge, PKey0, Obj0}, _From, State) ->

    %% We need to do a read followed by a write atomically
    %% This will crash if error when reason =/= not_found
    {ok, Existing} = do_get(PKey0, State, undefined),

    case plum_db_object:reconcile(Obj0, Existing) of
        false ->
            %% The remote object is an anscestor of or is equal to the local one
            {reply, false, State};

        {true, Obj1} ->
            %% Harmonize result
            Result =
                case callback(will_merge, PKey0, [Obj1, Existing]) of
                    true ->
                        {true, PKey0, Obj1};
                    {true, Obj2} ->
                        {true, PKey0, Obj2};
                    {true, _, _} = R ->
                        R;
                    false ->
                        false
                end,

            case Result of
                {true, PKey, Obj} ->
                    case do_put(PKey, Obj, State) of
                        ok when Obj =/= Obj1 ->
                            %% The case then the callback modified the object,
                            %% so we need to let the peers know
                            ok = maybe_broadcast(PKey, Obj, []),
                            ok = on_merge(PKey, Obj1, Existing),
                            {reply, true, State};

                        ok ->
                            ok = on_merge(PKey, Obj1, Existing),
                            {reply, true, State};

                        {error, Reason} ->
                            ?LOG_ERROR(#{
                                description =>
                                    "Error while writing merged object",
                                prefixed_key => PKey,
                                object => Obj,
                                reason => Reason
                            }),
                            {reply, false, State}
                    end;

                false ->
                    %% We cancel the merge
                    {reply, false, State}
            end
    end;

handle_call(byte_size, _From, State) ->
    _DbRef = db_ref(State),
    Ram = ets:info(ram_tab(State), memory),
    RamDisk = ets:info(ram_disk_tab(State), memory),
    Ets = (Ram + RamDisk) * erlang:system_info(wordsize),
    {reply, Ets, State};

handle_call(is_empty, _From, State) ->
    DbRef = db_ref(State),
    Ram = ets:info(ram_tab(State), size),
    RamDisk = ets:info(ram_disk_tab(State), size),
    Result = rocksdb:is_empty(DbRef) andalso (Ram + RamDisk) == 0,
    {reply, Result, State};

handle_call({iterator, Pid, FullPrefix, Opts}, _From, State) ->
    Mref = erlang:monitor(process, Pid),
    {Prefix, _} = FullPrefix,

    KeyPattern = key_value:get(match, Opts, undefined),

    MS = case KeyPattern == undefined of
        true ->
            undefined;
        false ->
            ets:match_spec_compile([{
                {FullPrefix, KeyPattern}, [], [true]
            }])
    end,

    PartIter0 = #partition_iterator{
        partition = State#state.partition,
        owner_mref = Mref,
        full_prefix = FullPrefix,
        keys_only = key_value:get(keys_only, Opts, false),
        match_pattern = KeyPattern,
        match_spec = MS,
        bin_prefix = encode_prefix({FullPrefix, '_'}, State),
        key_decoder = plum_db_key:decoder(),
        prefix_encoder = plum_db_key:prefix_encoder()
    },

    PartIter1 = case Prefix of
        ?WILDCARD ->
            %% We iterate over ram and disk only since everything in ram_disk
            %% is in disk (but not everything in disk is in ram_disk)
            set_ram_iterator(set_disk_iterator(PartIter0, State), State);
        _ ->
            case plum_db:prefix_type(Prefix) of
                ram ->
                    set_ram_iterator(PartIter0, State);
                ram_disk ->
                    set_ram_disk_iterator(PartIter0, State);
                Type when Type == disk orelse Type == undefined ->
                    %% If prefix is undefined then data is on disk by default
                    set_disk_iterator(PartIter0, State)
            end
    end,
    {reply, PartIter1, add_iterator(PartIter1, State)};

handle_call({iterator_close, Iter}, _From, State0) ->
    State1 = close_iterator(Iter, State0),
    {reply, ok, State1};

handle_call(_Message, _From, State) ->
    {reply, {error, unsupported_call}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({'EXIT', Pid, normal}, #state{helper = Pid} = State) ->
    {noreply, State#state{helper = undefined}};

handle_info({'EXIT', _, Reason}, #state{} = State) ->
    case Reason of
        restart ->
            %% Used for testing and debugging purposes
            exit(restart);
        _ ->
            {stop, Reason, State}
    end;

handle_info({'DOWN', Ref, process, _, _}, State0) ->
    State1 = close_iterator(Ref, State0),
    {noreply, State1};

handle_info({'ETS-TRANSFER', _, _, []}, State) ->
    {noreply, State};

handle_info(Event, State) ->
    ?LOG_INFO(#{
        description => "Unhandled event",
        event => Event
    }),
    {noreply, State}.


terminate(_Reason, State) ->
    %% Close all iterators
    _ = maps:fold(
        fun(Mref, _, Acc) -> close_iterator(Mref, Acc) end,
        State,
        State#state.iterators
    ),

    %% Close rocksdb
    catch rocksdb:close(db_ref(State)),
    ok.


code_change(_OldVsn, State, _Extra) ->
    {ok, State}.



%% =============================================================================
%% PRIVATE: ROCKSDB INIT
%% =============================================================================


%% @private
init_state(Name, Partition, DataRoot, Opts) ->
    %% Parse out the open/read/write options
    OpenOpts = key_value:get(open, Opts, []),
    ReadOpts = key_value:get(read, Opts, []),
    WriteOpts = key_value:get(write, Opts, []),

    %% Use read options for folding, but FORCE fill_cache to false
    FoldOpts = key_value:put(fill_cache, false, ReadOpts),

    %% We create two ets tables for ram and ram_disk storage levels
    EtsOpts = [
        named_table,
        public,
        ordered_set,
        {read_concurrency, true}, {write_concurrency, true}
    ],

    RamTab = table_name(Partition, ram),
    {ok, RamTab} = plum_db_table_owner:add_or_claim(RamTab, EtsOpts),

    %% TODO RamDisk Table should be restore on startup asynchronously and
    %% during its restore all gets should go to disk, so we should not set
    %% the table name here but later when the restore is finished
    RamDiskTab = table_name(Partition, ram_disk),
    {ok, RamDiskTab} = plum_db_table_owner:add_or_claim(RamDiskTab, EtsOpts),

    #state {
        name = Name,
        partition = Partition,
        actor_id = {Partition, partisan:node()},
        db_info = #db_info{
            ram_tab = RamTab,
            ram_disk_tab = RamDiskTab,
            read_opts = ReadOpts,
            write_opts = WriteOpts,
            %% eqwalizer:ignore FoldOpts
            fold_opts = FoldOpts,
            key_encoder = plum_db_key:encoder()
        },
		config = Opts,
        data_root = DataRoot,
		open_opts = OpenOpts,
        key_encoder = plum_db_key:encoder(),
        key_decoder = plum_db_key:decoder(),
        prefix_encoder = plum_db_key:prefix_encoder()
	}.


%% @private
open_db(State) ->
    RetriesLeft = plum_db_config:get(store_open_retry_Limit, 30),
    open_db(State, max(1, RetriesLeft), undefined).


%% @private
open_db(_State, 0, LastError) ->
    {error, LastError};

open_db(State, RetriesLeft, _) ->
    OpenOpts = State#state.open_opts,

    %% eqwalizer:ignore open opts
    case rocksdb:open(State#state.data_root, OpenOpts) of
        {ok, Ref} ->
            DBInfo0 = State#state.db_info,
            DBInfo = DBInfo0#db_info{db_ref = Ref},
            {ok, State#state{db_info = DBInfo}};

    	{error, {db_open, OpenErr} = Reason} when is_list(OpenErr) ->
            %% Check specifically for lock error, this can be caused if
            %% a crashed vnode takes some time to flush leveldb information
            %% out to disk.  The process is gone, but the NIF resource cleanup
            %% may not have completed.
            case lists:prefix("IO error: lock ", OpenErr) of
                true ->
                    SleepFor = plum_db_config:get(store_open_retries_delay),

                    ?LOG_DEBUG(#{
                        description => "Rocksdb backend retrying after error",
                        partition => State#state.partition,
                        node => partisan:node(),
                        data_root => State#state.data_root,
                        timeout => SleepFor,
                        reason => OpenErr
                    }),
                    %% eqwalizer:ignore SleepFor
                    timer:sleep(SleepFor),
                    open_db(State, RetriesLeft - 1, Reason);

                false ->
                    case lists:prefix("Corruption", OpenErr) of
                        true ->
                            ?LOG_WARNING(#{
                                description =>
                                    "Starting repair of corrupted RocksDB store",
                                partition => State#state.partition,
                                node => partisan:node(),
                                data_root => State#state.data_root,
                                reason => OpenErr
                            }),
                            _ = rocksdb:repair(
                                State#state.data_root, State#state.open_opts
                            ),
                            ?LOG_NOTICE(#{
                                description =>
                                    "Finished repair of corrupted RocksDB store",
                                partition => State#state.partition,
                                node => partisan:node(),
                                data_root => State#state.data_root,
                                reason => OpenErr
                            }),
                            open_db(State, 0, Reason);
                        false ->
                            {error, Reason}
                    end
            end;
        {error, Reason} ->
            {error, Reason}
    end.



%% @private
get_db_info(ServerRef) ->
    case persistent_term:get({?MODULE, ServerRef}) of
        undefined ->
            error({badarg, ServerRef});
        Value ->
            Value
    end.


%% @private
set_db_info(ServerRef, Data) ->
    persistent_term:put({?MODULE, ServerRef}, Data).



%% @private
spawn_helper(State) ->
    Helper = spawn_link(init_ram_disk_prefixes_fun(State)),
    State#state{helper = Helper}.



%% @private
init_ram_disk_prefixes_fun(State) ->
    fun() ->
        ?LOG_INFO(#{
            description => "Initialising partition",
            partition => State#state.partition,
            node => partisan:node()
        }),
        %% We create the in-memory db copy for ram and ram_disk prefixes
        Tab = ram_disk_tab(State),

        %% We load ram_disk prefixes from disk to ram
        PrefixList = maps:to_list(plum_db:prefixes()),
        {ok, DbIter} = rocksdb:iterator(db_ref(State), fold_opts(State)),

        try
            Fun = fun
                F({Prefix, #{type := Type}}, Acc) ->
                    F({Prefix, Type}, Acc);
                F({Prefix, ram_disk}, ok) ->
                    ?LOG_INFO(#{
                        description => "Loading data from disk to ram",
                        partition => State#state.partition,
                        prefix => Prefix,
                        node => partisan:node()
                    }),
                    First = encode_prefix(
                        {{Prefix, ?WILDCARD}, ?WILDCARD}, State
                    ),
                    Next = disk_iterator_move(DbIter, First),
                    init_prefix_iterate(
                        Next, DbIter, First, erlang:byte_size(First), Tab, State
                    );
                F(_, ok) ->
                    ok
            end,
            ok = lists:foldl(Fun, ok, PrefixList),
            ?LOG_INFO(#{
                description => "Finished initialisation of partition",
                partition => State#state.partition,
                node => partisan:node()
            }),
            _ = plum_db_events:notify(
                partition_init_finished, {ok, State#state.partition}
            ),
            ok

        catch
            Class:Reason:Stacktrace ->
                ?LOG_ERROR(#{
                    description => "Error while initialising partition",
                    class => Class,
                    reason => Reason,
                    stacktrace => Stacktrace,
                    partition => State#state.partition,
                    node => partisan:node()
                }),
                _ = plum_db_events:notify(
                    partition_init_finished,
                    {error, Reason, State#state.partition}
                ),
                erlang:raise(Class, Reason, Stacktrace)

        after

            catch rocksdb:iterator_close(DbIter)

        end
    end.


%% @private
init_prefix_iterate({error, _}, _, _, _, _, _) ->
    %% We have no more matches in this Prefix
    ok;

init_prefix_iterate({ok, K, V}, DbIter, BinPrefix, BPSize, Tab, State) ->
    case K of
        <<BinPrefix:BPSize/binary, _/binary>> ->
            %% Element is {{P, K}, MetadataObj}
            PKey = decode_key(K, State),
            true = ets:insert(Tab, {PKey, binary_to_term(V)}),
            Next = disk_iterator_move(DbIter, rocksdb_action(next, State)),
            init_prefix_iterate(Next, DbIter, BinPrefix, BPSize, Tab, State);
        _ ->
            %% We have no more matches in this Prefix
            ok
    end.



%% =============================================================================
%% PRIVATE: Call handling
%% =============================================================================







%% =============================================================================
%% PRIVATE
%% =============================================================================



%% @private
db_ref(#state{db_info = V}) ->
    db_ref(V);

db_ref(#db_info{db_ref = V}) ->
    V.


%% @private
ram_tab(#state{db_info = V}) ->
    ram_tab(V);

ram_tab(#db_info{ram_tab = V}) ->
    V.


%% @private
ram_disk_tab(#state{db_info = V}) ->
    ram_disk_tab(V);

ram_disk_tab(#db_info{ram_disk_tab = V}) ->
    V.


%% @private
read_opts(#state{db_info = V}) ->
    read_opts(V);

read_opts(#db_info{read_opts = V}) ->
    V.


%% @private
write_opts(#state{db_info = V}) ->
    write_opts(V);

write_opts(#db_info{write_opts = V}) ->
    V.

%% @private
fold_opts(#state{db_info = V}) ->
    fold_opts(V);

fold_opts(#db_info{fold_opts = V}) ->
    V.

%% @private
table_name(#partition_iterator{ram_tab = Tab}, ram) ->
    Tab;

table_name(#partition_iterator{ram_disk_tab = Tab}, ram_disk) ->
    Tab;

table_name(N, ram) when is_integer(N) ->
    list_to_atom(
        "plum_db_partition_" ++ integer_to_list(N) ++ "_server_ram");

table_name(N, ram_disk) when is_integer(N) ->
    list_to_atom(
        "plum_db_partition_" ++ integer_to_list(N) ++ "_server_ram_disk").


%% @private
prefix_type({{Prefix, _}, _}) ->
    plum_db:prefix_type(Prefix).


%% @private
modify(PKey, ValueOrFun, Opts, State) ->
    %% This will crash if error when reason =/= not_found
    {ok, Existing} = do_get(PKey, State, undefined),
    Ctxt = context(Existing),
    modify(PKey, ValueOrFun, Opts, State, Existing, Ctxt).


%% @private
modify(PKey, ValueOrFun, Opts, State, Existing, Ctxt) ->
    Actor = State#state.actor_id,

    %% If ValueOrFun is a function then it might raise an exception, so we catch
    try
        Modified = plum_db_object:modify(Existing, Ctxt, ValueOrFun, Actor),

        case do_put(PKey, Modified, State) of
            ok ->
                ok = maybe_broadcast(PKey, Modified, Opts),
                {ok, Existing, Modified};

            {error, _} = Error ->
                Error
        end

    catch
        _:Reason ->
            {error, Reason}
    end.


%% @private
maybe_resolve(undefined, _) ->
    {ok, undefined};

maybe_resolve(Object, Opts) ->
    case plum_db_object:value_count(Object) =< 1 of
        true ->
            {ok, Object};
        false ->
            Resolver = key_value:get(resolver, Opts, lww),
            try
                %% eqwalizer:ignore Resolver
                {ok, plum_db_object:resolve(Object, Resolver)}
            catch
                Class:Reason:Stacktrace ->
                    {error, {badresolver, Class, Reason, Stacktrace}}
            end
    end.


%% @private
maybe_modify(_, Existing, _, _, Existing) ->
    %% No change
    ok;

maybe_modify(PKey, Existing, Opts, State, NewObject) ->
    case key_value:get(allow_put, Opts, false) of
        false ->
            ok;
        true ->
            Ctxt = plum_db_object:context(NewObject),
            Value = plum_db_object:value(NewObject),
            case modify(PKey, Value, Opts, State, Existing, Ctxt) of
                {ok, _, Modified} ->
                    ok = on_update(PKey, Modified, Existing);

                {error, Reason} ->
                    ?LOG_ERROR(#{
                        description =>
                            "Error while during read-repair write",
                        reason => Reason,
                        prefixed_key => PKey,
                        object => Value
                    }),
                    ok
            end
    end.


%% @private
maybe_broadcast(PKey, Obj, Opts) ->
    case key_value:get(broadcast, Opts, true) of
        true ->
            broadcast(PKey, Obj);
        false ->
            ok
    end.


%% @private
broadcast(PKey, Obj) ->
    Broadcast = #plum_db_broadcast{pkey = PKey, obj = Obj},
    partisan:broadcast(Broadcast, plum_db).


%% @private
do_get(PKey, State) ->
    do_get_from(PKey, State, prefix_type(PKey)).


%% @private
do_get(PKey, State, Default) ->
    case do_get(PKey, State) of
        {error, not_found} ->
            {ok, Default};
        Other ->
            Other
    end.


%% @private
context(undefined) ->
    plum_db_object:empty_context();

context(Object) ->
    plum_db_object:context(Object).


%% @private
do_get_from(PKey, State, Type)
when (Type == disk) orelse (Type == undefined) ->
    DbRef = db_ref(State),
    ReadOpts = read_opts(State),
    result(rocksdb:get(DbRef, encode_key(PKey, State), ReadOpts));

do_get_from(PKey, State, ram) ->
    case ets:lookup(ram_tab(State), PKey) of
        [] ->
            {error, not_found};
        [{_, Obj}] ->
            {ok, Obj}
    end;

do_get_from(PKey, State, ram_disk) ->
    case ets:lookup(ram_disk_tab(State), PKey) of
        [] ->
            %% During init we would be restoring the ram_disk prefixes
            %% asynchronously.
            %% So we need to fallback to disk until the restore is
            %% done.
            do_get_from(PKey, State, disk);
        [{_, Obj}] ->
            {ok, Obj}
    end.


%% @private
maybe_hashtree_insert(PKey, Object, State) ->
    case plum_db_config:get(aae_enabled) of
        true ->
            Hash = plum_db_object:hash(Object),
            %% TODO avoid failing if hashtree server is down.
            ok = plum_db_partition_hashtree:insert(
                State#state.partition, PKey, Hash, false
            );
        false ->
            ok
    end.


%% @private
maybe_hashtree_delete(PKey, Existing, State) ->
    case plum_db_config:get(aae_enabled) of
        true ->
            Partition = State#state.partition,
            ActorId = State#state.actor_id,
            Hash = plum_db_object:hash(Existing),
            Ctxt = context(Existing),
            %% We create and insert the Erased object, this will be actually
            %% removed the next time we rebuild the tree, but until
            %% then we needed as a tombstone to avoid this becoming a
            %% 'missing key' when we compare with another hashtree.
            Erased = plum_db_object:modify(Existing, Ctxt, ?ERASED, ActorId),

            ok = plum_db_partition_hashtree:insert(
                Partition, PKey, Hash, false
            ),
            ok = broadcast(PKey, Erased);
        false ->
            ok
    end.


%% @private
do_put(PKey, Value, State) ->
    do_put(PKey, Value, State, prefix_type(PKey)).


%% @private
do_put(PKey, Value, State, undefined) ->
    do_put(PKey, Value, State, disk);

do_put(PKey, Value, State, ram) ->
    ok = maybe_hashtree_insert(PKey, Value, State),
    true = ets:insert(ram_tab(State), {PKey, Value}),
    ok;

do_put(PKey, Value, State, ram_disk) ->
    case do_put(PKey, Value, State, disk) of
        ok ->
            true = ets:insert(ram_disk_tab(State), {PKey, Value}),
            ok;
        Error ->
            Error
    end;

do_put(PKey, Value, State, disk) ->
    ok = maybe_hashtree_insert(PKey, Value, State),

    DbRef = db_ref(State),
    Opts = write_opts(State),
    Actions = [{put, encode_key(PKey, State), term_to_binary(Value, ?EXT_OPTS)}],
    result(rocksdb:write(DbRef, Actions, Opts)).


%% @private
next_iterator(disk, #partition_iterator{ram_disk_tab = undefined} = Iter) ->
    next_iterator(ram_disk, Iter);

next_iterator(disk, Iter) ->
    Iter#partition_iterator{
        disk_done = true,
        ram_disk_done = false
    };

next_iterator(ram_disk, #partition_iterator{ram_tab = undefined}) ->
    undefined;

next_iterator(ram_disk, Iter) ->
    Iter#partition_iterator{
        disk_done = true,
        ram_disk_done = true,
        ram_done = false
    };

next_iterator(ram, _) ->
    undefined.


%% @private
prev_iterator(ram, #partition_iterator{ram_disk_tab = undefined} = Iter) ->
    prev_iterator(ram_disk, Iter);

prev_iterator(ram, Iter) ->
    Iter#partition_iterator{
        ram_disk_done = false,
        ram_done = false
    };

prev_iterator(ram_disk, #partition_iterator{disk = undefined}) ->
    undefined;

prev_iterator(ram_disk, Iter) ->
    Iter#partition_iterator{
        disk_done = false,
        ram_disk_done = false
    };

prev_iterator(disk, _) ->
    undefined.

%% @private
-spec rocksdb_action(iterator_action_ext() | plum_db_prefix_pattern() | plum_db_pkey_pattern(), state() | iterator()) ->
    iterator_action() | binary().

%% @private
rocksdb_action({?WILDCARD, _}, _) ->
    first;

rocksdb_action({{?WILDCARD, _}, _}, _) ->
    first;

rocksdb_action({{_, _}, _} = PKey, StateOrIter) ->
    encode_prefix(PKey, StateOrIter);

rocksdb_action({_, _} = FullPrefix, Term) ->
    %% A PKey with wildcard key
    %% eqwalizer:ignore
    rocksdb_action({FullPrefix, ?WILDCARD}, Term);

rocksdb_action(first, _) ->
    first;

rocksdb_action(next, _) ->
    next;

rocksdb_action(prev, _) ->
    prev.


%% @private
%% ets key ois {{{Prefix, Suffix} = FullPrefix, Key} = PKey, Object}

ets_match_spec({{A, B}, KeyPattern}, KeysOnly) ->
    Pattern = {{{'$1', '$2'}, KeyPattern}, ?WILDCARD},

    Conds = case B of
        ?WILDCARD ->
            [{'==', '$1', {const, A}}];
        _ ->
            [{'andalso',
                {'==', '$1', {const, A}},
                {'==', '$2', {const, B}}
            }]
    end,

    Projection =  case KeysOnly of
        true ->
            [{element, 1, '$_'}];
        false ->
            ['$_']
    end,

    [
        {Pattern, Conds, Projection}
    ];

ets_match_spec({_, _} = FullPrefix, KeysOnly) ->
    ets_match_spec({{_, _} = FullPrefix, ?WILDCARD}, KeysOnly).


%% @private
-spec matches_key(binary() | plum_db_pkey(), iterator()) ->
    {true, plum_db_pkey()} | {false, plum_db_pkey()} | ?EOT.

matches_key(PKey, #partition_iterator{match_spec = undefined} = Iter) ->
    %% We try to match the prefix and if it doesn't we stop
    case matches_prefix(PKey, Iter) of
        true when is_binary(PKey) ->
            {true, decode_key(PKey, Iter)};
        true ->
            %% eqwalizer:ignore
            {true, PKey};
        false ->
            ?EOT
    end;

matches_key(PKey0, #partition_iterator{match_spec = MS} = Iter) ->
    PKey = decode_key(PKey0, Iter),

    case ets:match_spec_run([PKey], MS) of
        [true] ->
            {true, PKey};
        [] ->
            %% We try to match the prefix and if it doesn't we stop
            case matches_prefix(PKey, Iter) of
                true -> {false, PKey};
                false -> ?EOT
            end
    end.


%% @private
matches_prefix(
    {FullPrefix, _}, #partition_iterator{full_prefix = FullPrefix}) ->
    true;

matches_prefix(_, #partition_iterator{full_prefix = {'_', '_'}}) ->
    true;

matches_prefix({{P, _}, _}, #partition_iterator{full_prefix = {P, '_'}}) ->
    true;

matches_prefix(Bin, Iter) when is_binary(Bin) ->
    Prefix = Iter#partition_iterator.bin_prefix,
    Len = erlang:byte_size(Prefix),
    binary:longest_common_prefix([Bin, Prefix]) == Len;

matches_prefix(_, _) -> false.


%% @private
set_disk_iterator(#partition_iterator{} = PartIter0, State) ->
    DbRef = db_ref(State),
    Opts = fold_opts(State),

    {ok, DbIter} = rocksdb:iterator(DbRef, Opts),

    PartIter0#partition_iterator{
        disk_done = false,
        disk = DbIter
    }.


%% @private
set_ram_iterator(#partition_iterator{} = PartIter0, State) ->
    PartIter0#partition_iterator{
        ram_tab = ram_tab(State),
        ram_done = false,
        ram = undefined
    }.


%% @private
set_ram_disk_iterator(#partition_iterator{} = PartIter0, State) ->
    PartIter0#partition_iterator{
        ram_disk_tab = ram_disk_tab(State),
        ram_disk_done = false,
        ram_disk = undefined
    }.


%% @private
update_iterator(ram, Iter, Key, Cont) ->
    Iter#partition_iterator{prev_key = Key, ram = Cont};

update_iterator(ram_disk, Iter, Key, Cont) ->
    Iter#partition_iterator{prev_key = Key, ram_disk = Cont}.



%% @private
add_iterator(#partition_iterator{} = Iter, State) ->
    Mref = Iter#partition_iterator.owner_mref,
    Iterators1 = maps:put(Mref, Iter, State#state.iterators),
    State#state{iterators = Iterators1}.


%% @private
take_iterator(Mref, State) when is_reference(Mref) ->
    case maps:take(Mref, State#state.iterators) of
        {Iter, Iterators1} ->
            {Iter, State#state{iterators = Iterators1}};
        error ->
            error
    end.


%% @private
close_iterator(#partition_iterator{owner_mref = Mref}, State) ->
    close_iterator(Mref, State);

close_iterator(Mref, State0) when is_reference(Mref) ->
    case take_iterator(Mref, State0) of
        {#partition_iterator{disk = undefined}, State1} ->
            _ = erlang:demonitor(Mref, [flush]),
            State1;

        {#partition_iterator{disk = DbIter}, State1} ->
            _ = erlang:demonitor(Mref, [flush]),
            _ = catch rocksdb:iterator_close(DbIter),
            State1;

        error ->
            State0
    end.


%% @private
maybe_safe_fixtables(Iter, Flag) ->
    true = maybe_safe_fixtable(Iter#partition_iterator.ram_tab, Flag),
    maybe_safe_fixtable(Iter#partition_iterator.ram_disk_tab, Flag).


%% @private
maybe_safe_fixtable(undefined, _) ->
    true;
maybe_safe_fixtable(Tab, Flag) ->
    ets:safe_fixtable(Tab, Flag).


%% @private
result(ok) ->
    ok;

result({ok, Value}) ->
    {ok, binary_to_term(Value)};

result(not_found) ->
    {error, not_found};

result({error, _} = Error) ->
    Error.


%% @private
encode_key(Key, #state{key_encoder = Fun}) ->
    Fun(Key);

encode_key(Key, #db_info{key_encoder = Fun}) ->
    Fun(Key).


%% @private
encode_prefix(Key, #state{prefix_encoder = Fun}) ->
    Fun(Key);

encode_prefix(Key, #partition_iterator{prefix_encoder = Fun}) ->
    Fun(Key).


%% @private
decode_key(Bin, #state{key_decoder = Fun}) when is_binary(Bin) ->
    Fun(Bin);

decode_key(Bin, #partition_iterator{key_decoder = Fun}) when is_binary(Bin) ->
    Fun(Bin);

decode_key({{_, _}, _} = FPKey, _) ->
    FPKey.

%% @private
on_update(_, undefined, _) ->
    ok;

on_update(PKey, New, Existing) ->
    case plum_db_object:value(New) of
        ?TOMBSTONE ->
            on_delete(PKey, Existing);
        _ ->
            true = callback(on_update, PKey, [New, Existing])
    end,
    ok.


%% @private
on_merge(PKey, New, Existing) ->
    true = callback(on_merge, PKey, [New, Existing]),
    ok = plum_db_events:update({PKey, New, Existing}).


%% @private
on_delete(PKey, Obj) ->
    true = callback(on_delete, PKey, [Obj]),
    ok.


%% @private
on_erase(PKey, Obj) ->
    true = callback(on_erase, PKey, [Obj]),
    ok.


%% -----------------------------------------------------------------------------
%% @private
%% @doc Applies the user defined callback.
%% The will_merge callback needs to reply
%% true | {true, Obj} | {true, Pkey, Obj} | false
%% @end
%% -----------------------------------------------------------------------------
callback(Name, {{Prefix, _}, _} = PKey, Args) when is_list(Args) ->
    try
        Path = [prefixes, Prefix, callbacks, Name],

        case plum_db_config:get(Path, undefined) of
            undefined ->
                true;

            {Mod, FunName} when is_atom(Mod), is_atom(FunName) ->
                case erlang:apply(Mod, FunName, [PKey | Args]) of
                    ok when Name == on_update;
                            Name == on_merge;
                            Name == on_delete;
                            Name == on_erase ->
                        true;
                    true when Name == will_merge ->
                        true;
                    {true, {object, _}} = Result when Name == will_merge ->
                        Result;
                    {true, _, {object, _}} = Result when Name == will_merge ->
                        Result;
                    false when Name == will_merge ->
                        false;
                    Other ->
                        throw({badreturn, Other})
                end
        end
    catch
        throw:Reason ->
            ?LOG_ERROR(#{
                description => "Prefix callback return is invalid. Ignored",
                callback => Name,
                class => throw,
                reason => Reason
            }),
            true;

        Class:Reason:Stacktrace ->
            ?LOG_ERROR(#{
                description => "Error while invoking prefix callback. Ignored",
                callback => Name,
                class => Class,
                reason => Reason,
                stacktrace => Stacktrace
            }),
            true
    end.
