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
-define(CONFIG_SPEC, #{
    type => #{
        required => true,
        datatype => {in, [ram, ram_disk, disk]},
        default => disk
    },
    shard_by => #{
        required => true,
        datatype => {in, [prefix, key]},
        default => prefix
    },
    callbacks => #{
        required => true,
        datatype => map,
        default => #{},
        validator => ?CALLBACKS_SPEC
    }
}).

-define(CALLBACKS_SPEC, #{
    will_merge => #{
        required => false,
        datatype => tuple,
        validator => ?FUN_WITH_ARITY(3)
    },
    on_merge => #{
        required => false,
        datatype => tuple,
        validator => ?FUN_WITH_ARITY(3)
    },
    on_update => #{
        required => false,
        datatype => tuple,
        validator => ?FUN_WITH_ARITY(3)
    },
    on_delete => #{
        required => false,
        datatype => tuple,
        validator => ?FUN_WITH_ARITY(2)
    },
    on_erase => #{
        required => false,
        datatype => tuple,
        validator => ?FUN_WITH_ARITY(2)
    }
}).

-define(FUN_WITH_ARITY(N),
    fun
        ({Mod, Fun}) when is_atom(Mod); is_atom(Fun) ->
            erlang:function_exported(Mod, Fun, N);
        (_) ->
            false
    end
).

-export([get/1]).
-export([get/2]).
-export([set/2]).
-export([init/0]).
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
    ok = setup_env(),
    ok = app_config:init(?APP, #{callback_mod => ?MODULE}),

    ok = setup_partisan(),
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
        {ok, validate_prefixes(Values)}
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
        data_channel => ?DATA_CHANNEL,
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
    _ShardBy = validate_shard_by(maps:get(shard_by, Config1)),
    application:set_env([{?APP, maps:to_list(Config1)}]).


validate_shard_by(prefix) -> prefix;
validate_shard_by(key) -> key;
validate_shard_by(Term) -> throw({invalid_prefix_shard_by, Term}).



%% @private
validate_prefixes(undefined) ->
    #{};

validate_prefixes([]) ->
    #{};


validate_prefixes(L) when is_list(L) ->
    maps:from_list(
        lists:map(
            fun
                ({Prefix, Config0}) when is_map(Config0) ->
                    Config = maps_utils:validate(Config0, ?CONFIG_SPEC),
                    {Prefix, Config};

                ({Prefix, Type})
                when Type == ram; Type == ram_disk; Type == disk ->
                    Config0 = #{type => Type},
                    Config = maps_utils:validate(Config0, ?CONFIG_SPEC),
                    {Prefix, Config};

                (Term) ->
                    throw({invalid_prefix_config, Term})
            end,
            L
        )
    ).


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
setup_partisan() ->
    PartisanDefaults = #{
        partisan_peer_service_manager =>
            partisan_pluggable_peer_service_manager,
        connect_disterl => false,
        exchange_selection => optimized,
        lazy_tick_period => 1000,
        exchange_tick_period => 60000
    },

    PartisanEnv0 = maps:from_list(application:get_all_env(partisan)),
    Channels0 = maps:get(channels, PartisanEnv0, []),
    BroadcastMods = maps:get(broadcast_mods, PartisanEnv0, []),
    Channels =
        case ?MODULE:get(data_channel) of
            Name when is_map(Channels0), is_atom(Name) ->
                maps:put(Name, #{}, Channels0);

            {monotonic, Name} when is_map(Channels0) ->
                maps:put(Name, #{monotonic => true}, Channels0);

            {Name, ChannelOpts}
            when is_map(Channels0), is_atom(Name), is_map(ChannelOpts) ->
                maps:put(Name, ChannelOpts, Channels0);

            #{name := Name} = Spec when is_map(Channels0) ->
                ChannelOpts = maps:without([name], Spec),
                maps:put(Name, ChannelOpts, Channels0);

            Arg when is_list(Channels0) ->
                [Arg | Channels0]
    end,


    PartisanOverrides = #{
        pid_encoding => false,
        channels => Channels,
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
