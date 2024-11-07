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
-behaviour(gen_server).
-include_lib("kernel/include/logger.hrl").

-record(state, {
    block_cache             :: rocksdb:cache_handle() | undefined,
    server_stats            :: rocksdb:statistics_handle() | undefined,
    server_write_buffer     :: rocksdb:write_buffer_manager() | undefined,
    hashtree_stats          :: rocksdb:statistics_handle() | undefined,
    hashtree_write_buffer   :: rocksdb:write_buffer_manager() | undefined
}).

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
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
-spec stop() -> ok.

stop() ->
    gen_server:stop(?MODULE).


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
    ?LOG_INFO("Initialising RocksDB Config"),
    N = plum_db:partition_count(),
    Opts0 = plum_db_config:get(rocksdb),

    %% Create a shared cache
    CacheSize = key_value:get(
        [block_based_table_options, block_cache_size],
        Opts0,
        memory:gibibytes(1)
    ),
    ?LOG_INFO(
        "Configuring store shared block cache to ~s",
        [memory:format(CacheSize, binary)]
    ),

    {ok, BlockCache} = rocksdb:new_cache(lru, CacheSize),


    %% Create a shared buffer for partition server instances
    %% We multiply the value by the nuber of partitions
    WriteBufferSize = key_value:get(
        db_write_buffer_size,
        Opts0,
        memory:mebibytes(40)
    ) * N,
    ?LOG_INFO(
        "Configuring db store shared write buffer to ~s",
        [memory:format(WriteBufferSize, binary)]
    ),

    {ok, ServerWriteBuffer} = rocksdb:new_write_buffer_manager(
        WriteBufferSize,
        BlockCache
    ),

    HashtreeWriteBufferSize = memory:mebibytes(10 * N),
    ?LOG_INFO(
        "Configuring hashtree store shared write buffer to ~s",
        [memory:format(HashtreeWriteBufferSize, binary)]
    ),

    %% Create a shared buffer for partition hashtree instances
    %% This value is harcoded
    {ok, HashtreeWriteBuffer} = rocksdb:new_write_buffer_manager(
        HashtreeWriteBufferSize,
        BlockCache
    ),

    {ok, ServerStats} = rocksdb:new_statistics(),
    {ok, HashtreeStats} = rocksdb:new_statistics(),

    State = State0#state{
        block_cache = BlockCache,
        server_write_buffer = ServerWriteBuffer,
        hashtree_write_buffer = HashtreeWriteBuffer,
        server_stats = ServerStats,
        hashtree_stats = HashtreeStats
    },

    Opts1 = key_value:put(create_if_missing, true, Opts0),
    Opts = key_value:put(create_missing_column_families, true, Opts1),

    ServerOpts = [
        {open, lists:foldl(
            fun ({K, V}, Acc) -> key_value:put(K, V, Acc) end,
            Opts,
            [
                {[block_based_table_options, block_cache], BlockCache},
                {write_buffer_manager, ServerWriteBuffer},
                {statistics, State#state.server_stats}
            ]
        )}
    ],

    HashtreeOpts = [
        {open, lists:foldl(
            fun ({K, V}, Acc) -> key_value:put(K, V, Acc) end,
            Opts,
            [
                {[block_based_table_options, block_cache], BlockCache},
                {write_buffer_manager, HashtreeWriteBuffer},
                {max_write_buffer_number, 4},
                {statistics, State#state.hashtree_stats}
            ]
        )}
    ],

    plum_db_config:set(hashtree_rocksdb, HashtreeOpts),
    {noreply, State, {continue, {start_partitions, ServerOpts, HashtreeOpts}}};

handle_continue({start_partitions, ServerOpts, HashtreeOpts}, State) ->
    [
        plum_db_partitions_sup:add_partition(X, ServerOpts, HashtreeOpts)
        || X <- plum_db:partitions()
    ],
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

terminate(_Reason, State) ->
    rocksdb:release_cache(State#state.block_cache),

    rocksdb:release_write_buffer_manager(State#state.server_write_buffer),
    rocksdb:release_write_buffer_manager(State#state.hashtree_write_buffer),

    rocksdb:release_statistics(State#state.server_stats),
    rocksdb:release_statistics(State#state.hashtree_stats),

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