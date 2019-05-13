%% =============================================================================
%%  plum_db_config.erl -
%%
%%  Copyright (c) 2016-2018 Ngineo Limited t/a Leapsight. All rights reserved.
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


%% =============================================================================
%% @doc
%%
%% @end
%% =============================================================================
-module(plum_db_config).

-define(ERROR, '$error_badarg').
-define(APP, plum_db).
-define(DEFAULT_RESOURCE_SIZE, erlang:system_info(schedulers)).

-export([get/1]).
-export([get/2]).
-export([set/2]).
-export([init/0]).

-compile({no_auto_import, [get/1]}).




%% =============================================================================
%% API
%% =============================================================================


init() ->
    Config = application:get_all_env(plum_db),
    DefaultWriteBufferMin = 4 * 1024 * 1024,
    DefaultWriteBufferMax = 14 * 1024 * 1024,
    Defaults = #{
        shard_by => prefix,
        peer_service => plum_db_partisan_peer_service,
        store_open_retries_delay => 2000,
        store_open_retry_Limit => 30,
        data_exchange_timeout => 60000,
        hashtree_timer => 10000,
        data_dir => "data",
        partitions => erlang:system_info(schedulers),
        prefixes => [],
        aae_hashtree_ttl => 7 * 24 * 60 * 60, %% 1 week
        aae_enabled => true,
        aae_sha_chunk => 4096,
        aae_leveldb_opts => [
            {write_buffer_size_min, DefaultWriteBufferMin}, {write_buffer_size_max, DefaultWriteBufferMax}
        ]
    },
    Map = maps:merge(Defaults, maps:from_list(Config)),
    maps:fold(fun(K, V, ok) -> set(K, V) end, ok, Map).


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
-spec get(Key :: atom() | tuple()) -> term().
get([H|T]) ->
    case get(H) of
        Term when is_map(Term) ->
            case maps_utils:get_path(T, Term, ?ERROR) of
                ?ERROR -> error(badarg);
                Value -> Value
            end;
        Term when is_list(Term) ->
            get_path(Term, T, ?ERROR);
        _ ->
            undefined
    end;

get(Key) when is_tuple(Key) ->
    get(tuple_to_list(Key));

get(Key) ->
    plum_db_mochiglobal:get(Key).


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
-spec get(Key :: atom() | tuple(), Default :: term()) -> term().
get([H|T], Default) ->
    case get(H, Default) of
        Term when is_map(Term) ->
            maps_utils:get_path(T, Term, Default);
        Term when is_list(Term) ->
            get_path(Term, T, Default);
        _ ->
            Default
    end;

get(Key, Default) when is_tuple(Key) ->
    get(tuple_to_list(Key), Default);

get(Key, Default) ->
    plum_db_mochiglobal:get(Key, Default).





%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
-spec set(Key :: atom() | tuple(), Value :: term()) -> ok.

set(data_dir, Value) ->
    _ = do_set(db_dir, db_dir(Value)),
    _ = do_set(hashtrees_dir, hashtrees_dir(Value)),
    do_set(data_dir, Value);

set(partitions, Value) ->
    Partitions = validate_partitions(Value),
    do_set(partitions, Partitions);

set(prefixes, Values) ->
    Prefixes = validate_prefixes(Values),
    do_set(prefixes, Prefixes);

set(Key, Value) ->
    do_set(Key, Value).




%% =============================================================================
%% PRIVATE
%% =============================================================================


do_set(Key, Value) ->
    application:set_env(?APP, Key, Value),
    plum_db_mochiglobal:put(Key, Value).


%% @private
get_path([H|T], Term, Default) when is_list(Term) ->
    case lists:keyfind(H, 1, Term) of
        false when Default == ?ERROR ->
            error(badarg);
        false ->
            Default;
        {H, Child} ->
            get_path(T, Child, Default)
    end;

get_path([], Term, _) ->
    Term;

get_path(_, _, ?ERROR) ->
    error(badarg);

get_path(_, _, Default) ->
    Default.

%% @private
validate_prefixes(undefined) ->
    [];
validate_prefixes(L) ->
    Fun = fun
        ({P, ram} = E, Acc) when is_binary(P) orelse is_atom(P) ->
            [E | Acc];
        ({P, ram_disk} = E, Acc) when is_binary(P) orelse is_atom(P) ->
            [E | Acc];
        ({P, disk} = E, Acc) when is_binary(P) orelse is_atom(P) ->
            [E | Acc];
        (Term, _) ->
            throw({invalid_prefix_type, Term})
    end,
    maps:from_list(lists:foldl(Fun, [], L)).


%% @private
db_dir(Value) -> filename:join([Value, "db"]).


%% @private
hashtrees_dir(Value) -> filename:join([Value, "hashtrees"]).


%% @private
validate_partitions(undefined) ->
    erlang:system_info(schedulers);

validate_partitions(N) when is_integer(N) ->
    DataDir = get(data_dir),
    Pattern = filename:join([db_dir(DataDir), "*"]),
    Subdirs = filelib:wildcard(Pattern),
    case length(Subdirs) of
        0 ->
            %% We have no previous data, we take the user provided config
            N;
        N ->
            N;
        M ->
            %% We already have data in data_dir then
            %% we should coerce this value to the actual number of partitions
            _ = lager:warning(
                "The number of existing partitions on disk differ from the configuration, ignoring requested value and coercing configuration to the existing number instead; partitions=~p, existing=~p, data_dir=~p",
                [N, M, DataDir]
            ),
            M
    end.


