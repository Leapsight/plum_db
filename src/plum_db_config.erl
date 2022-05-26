%% =============================================================================
%%  plum_db_config.erl -
%%
%%  Copyright (c) 2016-2021 Leapsight. All rights reserved.
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
-behaviour(app_config).

-include_lib("kernel/include/logger.hrl").
-include("plum_db.hrl").


-define(APP, plum_db).
-define(ERROR, '$error_badarg').
-define(DEFAULT_RESOURCE_SIZE, erlang:system_info(schedulers)).

-export([get/1]).
-export([get/2]).
-export([set/2]).
-export([init/0]).
-export([setup_dependencies/0]).
-export([on_set/2]).
-export([will_set/2]).

-compile({no_auto_import, [get/1]}).



%% =============================================================================
%% API
%% =============================================================================



%% -----------------------------------------------------------------------------
%% @doc Initialises plum_db configuration
%% @end
%% -----------------------------------------------------------------------------
init() ->
    ok = setup_dependencies(),
    ok = setup_env(),
    ok = app_config:init(?APP, #{callback_mod => ?MODULE}),
    ok = coerce_partitions(),
    ?LOG_NOTICE(#{description => "PlumDB configuration initialised}"}),
    ok.


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
-spec get(Key :: list() | atom() | tuple()) -> term().

get(Key) ->
    app_config:get(?APP, Key).


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
-spec get(Key :: list() | atom() | tuple(), Default :: term()) -> term().

get(Key, Default) ->
    app_config:get(?APP, Key, Default).


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
-spec set(Key :: key_value:key() | tuple(), Value :: term()) -> ok.

set(Key, Value) ->
    app_config:set(?APP, Key, Value).


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
-spec will_set(Key :: key_value:key(), Value :: any()) ->
    ok | {ok, NewValue :: any()} | {error, Reason :: any()}.

will_set(partitions, Value) ->
    try
        {ok, validate_partitions(Value)}
    catch
        _:Reason ->
            {error, Reason}
    end;

will_set(prefixes, Values) ->
    try
        DefaultShardBy = get(shardy, prefix),
        {ok, validate_prefixes(Values, DefaultShardBy)}
    catch
        _:Reason ->
            {error, Reason}
    end;

will_set(_, _) ->
    ok.


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
-spec on_set(Key :: key_value:key(), Value :: any()) -> ok.

on_set(data_dir, Value) ->
    _ = app_config:set(?APP, db_dir, db_dir(Value)),
    Hashtrees = filename:join([Value, "hashtrees"]),
    app_config:set(?APP, hashtrees_dir, Hashtrees);

on_set(_, _) ->
    ok.


%% =============================================================================
%% PRIVATE
%% =============================================================================



setup_env() ->
    Config0 = maps:from_list(application:get_all_env(?APP)),
    Defaults = #{
        wait_for_partitions => true,
        wait_for_hashtrees => true,
        wait_for_aae_exchange => true,
        store_open_retries_delay => 2000,
        store_open_retry_Limit => 30,
        shard_by => prefix,
        data_dir => "data",
        data_exchange_timeout => 60000,
        hashtree_timer => 10000,
        partitions => max(erlang:system_info(schedulers), 8),
        prefixes => [],
        aae_enabled => true,
        aae_concurrency => 1,
        aae_hashtree_ttl => 7 * 24 * 60 * 60, %% 1 week
        aae_sha_chunk => 4096
    },
    Config1 = maps:merge(Defaults, Config0),
    % Prefixes0 = maps:get(prefixes, Config1),
    _ShardBy = validate_shard_by(maps:get(shard_by, Config1)),
    % Prefixes1 = validate_prefixes(Prefixes0, ShardBy),
    % Config2 = maps:put(prefixes, Prefixes1, Config1),
    application:set_env([{?APP, maps:to_list(Config1)}]).



%% @private
validate_prefixes(undefined, _) ->
    #{};

validate_prefixes([], _) ->
    #{};

validate_prefixes(L, ShardBy) ->
    Fun = fun
        ({P, Config}, Acc)
        when is_binary(P) orelse is_atom(P) andalso is_map(Config) ->
            [{P, validate_prefix_config(Config, ShardBy)} | Acc];

        ({P, Type}, Acc) when is_binary(P) orelse is_atom(P) ->
            %% Support for previous form, we transform it into the new form
            Type = validate_prefix_type(Type),
            Config = #{type => Type, shard_by => ShardBy},
            [{P, Config} | Acc];

        (Term, _) ->
            throw({invalid_prefix_config, Term})
    end,

    maps:from_list(lists:foldl(Fun, [], L)).


%% @private
validate_prefix_type(ram) -> ram;
validate_prefix_type(ram_disk) -> ram_disk;
validate_prefix_type(disk) -> disk;
validate_prefix_type(Term) -> throw({invalid_prefix_type, Term}).

validate_shard_by(prefix) -> prefix;
validate_shard_by(key) -> key;
validate_shard_by(Term) -> throw({invalid_prefix_shard_by, Term}).


validate_prefix_config(#{type := Type, shard_by := ShardBy} = Config, _) ->
    Type = validate_prefix_type(Type),
    ShardBy = validate_shard_by(ShardBy),
    Config;

validate_prefix_config(#{type := Type} = Config, DefaultShardBy) ->
    Type = validate_prefix_type(Type),
    Config#{shard_by => DefaultShardBy}.


%% @private
db_dir(Value) -> filename:join([Value, "db"]).



%% @private
validate_partitions(undefined) ->
    validate_partitions(erlang:system_info(schedulers));

validate_partitions(0) ->
    validate_partitions(1);

validate_partitions(N) when is_integer(N) ->
    N.

coerce_partitions() ->
    N = get(partitions),
    DataDir = get(data_dir),
    Pattern = filename:join([db_dir(DataDir), "*"]),
    Subdirs = filelib:wildcard(Pattern),
    case length(Subdirs) of
        0 ->
            %% We have no previous data, we take the user provided config
            ok;
        N ->
            ok;
        M ->
            %% We already have data in data_dir then
            %% we should coerce this value to the actual number of partitions
            ?LOG_WARNING(#{
                description => "The number of existing partitions on disk differ from the configuration, ignoring requested value and coercing configuration to the existing number instead",
                partitions => N,
                existing => M,
                data_dir => DataDir
            }),
            set(partitions, M)
    end.



%% @private
setup_dependencies() ->
    PartisanDefaults = #{
        partisan_peer_service_manager => partisan_pluggable_peer_service_manager,
        connect_disterl => false,
        exchange_selection => optimized,
        lazy_tick_period => 1000,
        exchange_tick_period => 60000
    },

    PartisanEnv0 = maps:from_list(application:get_all_env(partisan)),
    Channels = maps:get(channels, PartisanEnv0, []),
    BroadcastMods = maps:get(broadcast_mods, PartisanEnv0, []),

    PartisanOverrides = #{
        pid_encoding => false,
        channels => [?DATA_CHANNEL | Channels],
        broadcast_mods => ordsets:to_list(
            ordsets:union(
                ordsets:from_list([plum_db, partisan_plumtree_backend]),
                ordsets:from_list(BroadcastMods)
            )
        )
    },

    PartisanEnv1 = maps:merge(
        maps:merge(PartisanDefaults, PartisanEnv0),
        PartisanOverrides
    ),

    ok = application:set_env([{partisan, maps:to_list(PartisanEnv1)}]),
    ok.
