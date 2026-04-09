%% =============================================================================
%%  plum_db_partition_manager.erl -
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

%% -----------------------------------------------------------------------------
%% @doc A transient worker that is used to listen to certain plum_db events and
%% allow watchers to wait (blocking the caller) for certain conditions.
%% This is used by plum_db_app during the startup process to wait for the
%% following conditions:
%%
%% * Partition initisalisation – the worker subscribes to plum_db notifications
%% and keeps track of each partition initialisation until they are all
%% initialised (or failed to initilised) and replies to all watchers with a
%% `ok' or `{error, FailedPartitions}', where FailedPartitions is a map() which
%% keys are the partition number and the value is the reason for the failure.
%% * Partition hashtree build – the worker subscribes to plum_db notifications
%% and keeps track of each partition hashtree until they are all
%% built (or failed to build) and replies to all watchers with a
%% `ok' or `{error, FailedHashtrees}', where FailedHashtrees is a map() which
%% keys are the partition number and the value is the reason for the failure.
%%
%% A watcher is any process which calls the functions wait_for_partitions/0,1
%% and/or wait_for_hashtrees/0,1. Both functions will block the caller until
%% the above conditions are met.
%%
%% @end
%% -----------------------------------------------------------------------------
-module(plum_db_partition_manager).
-behaviour(partisan_gen_server).
-include_lib("kernel/include/logger.hrl").

-record(state, {}).

-type state()               ::  #state{}.


-export([start_link/0]).
-export([stop/0]).
-export([stats/1]).

%% gen_server callbacks
-export([init/1]).
-export([handle_continue/2]).
-export([handle_call/3]).
-export([handle_cast/2]).
-export([handle_info/2]).
-export([terminate/2]).
-export([code_change/3]).



%% =============================================================================
%% API
%% =============================================================================



%% -----------------------------------------------------------------------------
%% @doc Start plumtree_partitions_coordinator and link to calling process.
%% @end
%% -----------------------------------------------------------------------------
-spec start_link() -> {ok, pid()} | ignore | {error, term()}.

start_link() ->
    partisan_gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
-spec stop() -> ok.

stop() ->
    partisan_gen_server:stop(?MODULE).


stats(Arg) ->
    Res = plum_db_partition_server:stats(Arg),
    resulto:map(Res, fun(Bin) -> parse(Bin) end).



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
    State = #state{},
    {ok, State, {continue, init_config}}.


handle_continue(init_config, #state{} = State0) ->
    N = plum_db:partition_count(),
    Opts0 = plum_db_config:get([rocksdb, open]),

    ?LOG_INFO("Initialising RocksDB Config ~p", [Opts0]),

    MaxWriteBuffNumber = key_value:get(max_write_buffer_number, Opts0),

    %% Per-partition block cache size (total budget divided by N)
    TotalCacheSize =
        key_value:get(
            [block_based_table_options, block_cache_size],
            Opts0,
            memory:gibibytes(2)
        ),
    PerPartitionCacheSize = TotalCacheSize div N,
    ?LOG_INFO(
        "Configuring per-partition block cache to ~s (total ~s across ~p partitions)",
        [memory:format(PerPartitionCacheSize, binary),
         memory:format(TotalCacheSize, binary), N]
    ),

    %% Per-partition write buffer size
    WriteBuffSize = key_value:get(write_buffer_size, Opts0),
    ?LOG_INFO(
        "Configuring per-partition db store write buffer to ~s",
        [memory:format(WriteBuffSize, binary)]
    ),

    %% Per-partition hashtree write buffer size
    HTWriteBuffSize = memory:mebibytes(10),
    ?LOG_INFO(
        "Configuring per-partition hashtree store write buffer to ~s",
        [memory:format(HTWriteBuffSize, binary)]
    ),

    EnableStats = key_value:get([rocksdb, enable_statistics], Opts0, true),

    State = State0,

    Opts1 = key_value:put(create_if_missing, true, Opts0),
    Opts = key_value:put(create_missing_column_families, true, Opts1),

    BaseOpts = key_value:put(max_write_buffer_number, MaxWriteBuffNumber, Opts),

    PerPartitionOpts = #{
        base_opts => BaseOpts,
        per_partition_cache_size => PerPartitionCacheSize,
        write_buff_size => WriteBuffSize,
        ht_write_buff_size => HTWriteBuffSize,
        enable_stats => EnableStats
    },

    {noreply, State, {continue, {start_partitions, PerPartitionOpts}}};

handle_continue({start_partitions, PerPartitionOpts}, State) ->
    #{
        base_opts := BaseOpts,
        per_partition_cache_size := PerPartitionCacheSize,
        write_buff_size := WriteBuffSize,
        ht_write_buff_size := HTWriteBuffSize,
        enable_stats := EnableStats
    } = PerPartitionOpts,

    lists:foreach(
        fun(Partition) ->
            %% Each partition gets its own block cache
            {ok, BlockCache} = rocksdb:new_cache(lru, PerPartitionCacheSize),

            %% Each partition gets its own write buffer manager
            {ok, ServerWriteBuff} = rocksdb:new_write_buffer_manager(
                WriteBuffSize
            ),
            {ok, HTWriteBuff} = rocksdb:new_write_buffer_manager(
                HTWriteBuffSize
            ),

            CommonOpenOpts0 = key_value:put(
                [block_based_table_options, block_cache],
                BlockCache,
                BaseOpts
            ),

            %% Each partition gets its own statistics handles
            CommonOpenOpts =
                case EnableStats of
                    true ->
                        {ok, ServerStats} = rocksdb:new_statistics(),
                        key_value:put(statistics, ServerStats, CommonOpenOpts0);
                    false ->
                        CommonOpenOpts0
                end,

            ServerOpenOpts = key_value:put(
                write_buffer_manager, ServerWriteBuff, CommonOpenOpts
            ),

            HTOpenOpts0 =
                case EnableStats of
                    true ->
                        {ok, HTStats} = rocksdb:new_statistics(),
                        key_value:put(statistics, HTStats, CommonOpenOpts0);
                    false ->
                        CommonOpenOpts0
                end,

            HTOpenOpts = key_value:put(
                write_buffer_manager, HTWriteBuff, HTOpenOpts0
            ),

            ServerOpts = [{open, ServerOpenOpts}],
            HashtreeOpts = [{open, HTOpenOpts}],

            plum_db_config:set(hashtree_rocksdb, HashtreeOpts),
            plum_db_partitions_sup:add_partition(
                Partition, ServerOpts, HashtreeOpts
            )
        end,
        plum_db:partitions()
    ),
    {noreply, State};

handle_continue(_, State) ->
    {noreply, State}.


%% @private
-spec handle_call(term(), {pid(), term()}, state()) ->
    {reply, term(), state()}
    | {reply, term(), state(), non_neg_integer()}
    | {reply, term(), state(), {continue, term()}}
    | {noreply, state()}
    | {noreply, state(), non_neg_integer()}
    | {noreply, state(), {continue, term()}}
    | {stop, term(), term(), state()}
    | {stop, term(), state()}.

handle_call(_Message, _From, State) ->
    {reply, {error, unsupported_call}, State}.


%% @private
-spec handle_cast(term(), state()) ->
    {noreply, state()}
    | {noreply, state(), non_neg_integer()}
    | {noreply, state(), {continue, term()}}
    | {stop, term(), state()}.

handle_cast(_Msg, State) ->
    {noreply, State}.


%% @private
-spec handle_info(term(), state()) ->
    {noreply, state()}
    | {noreply, state(), non_neg_integer()}
    | {noreply, state(), {continue, term()}}
    | {stop, term(), state()}.

handle_info(Event, State) ->
    ?LOG_INFO(#{
        reason => unsupported_event,
        event => Event
    }),
    {noreply, State}.


%% @private
-spec terminate(term(), state()) -> term().

terminate(_Reason, _State) ->
    %% All RocksDB resources (block caches, write buffer managers, statistics)
    %% are per-partition and released when each partition's RocksDB instance
    %% is closed.
    ok.


%% @private
-spec code_change(term() | {down, term()}, state(), term()) -> {ok, state()}.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.



%% =============================================================================
%% PRIVATE
%% =============================================================================

%% TODO
parse(Bin) ->
  Bin.