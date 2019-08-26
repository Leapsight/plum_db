%% =============================================================================
%%  plum_db_app.erl -
%%
%%  Copyright (c) 2018-2019 Ngineo Limited t/a Leapsight. All rights reserved.
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
%% @doc
%%
%% ```
%%                         +------------------+
%%                         |                  |
%%                         |   plum_db_sup    |
%%                         |                  |
%%                         +------------------+
%%                                   |
%%           +-----------------------+-----------------------+
%%           |                       |                       |
%%           v                       v                       v
%% +------------------+    +------------------+    +------------------+
%% |                  |    |     plum_db_     |    |                  |
%% |     plum_db      |    |  partitions_sup  |    |  plum_db_events  |
%% |                  |    |                  |    |                  |
%% +------------------+    +------------------+    +------------------+
%%                                   |
%%                       +-----------+-----------+
%%                       |                       |
%%                       v                       v
%%             +------------------+    +------------------+
%%             |plum_db_partition_|    |plum_db_partition_|
%%             |      1_sup       |    |      n_sup       |
%%             |                  |    |                  |
%%             +------------------+    +------------------+
%%                       |
%%           +-----------+-----------+----------------------+
%%           |                       |                      |
%%           v                       v                      v
%% +------------------+    +------------------+   +------------------+
%% |plum_db_partition_|    |plum_db_partition_|   |plum_db_partition_|
%% |     1_worker     |    |     1_server     |   |    1_hashtree    |
%% |                  |    |                  |   |                  |
%% +------------------+    +------------------+   +------------------+
%%                                   |                      |
%%                                   v                      v
%%                         + - - - - - - - - -    + - - - - - - - - -
%%                                            |                      |
%%                         |     eleveldb         |     eleveldb
%%                                            |                      |
%%                         + - - - - - - - - -    + - - - - - - - - -
%% '''
%%
%% @end
%% -----------------------------------------------------------------------------
-module(plum_db_app).
-behaviour(application).

-export([start/2]).
-export([start_phase/3]).
-export([prep_stop/1]).
-export([stop/1]).



%% =============================================================================
%% API
%% =============================================================================



%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
start(_StartType, _StartArgs) ->
      case plum_db_sup:start_link() of
        {ok, Pid} ->
            {ok, Pid};
        Other ->
            Other
    end.


%% -----------------------------------------------------------------------------
%% @doc Application behaviour callback
%% @end
%% -----------------------------------------------------------------------------
start_phase(init_db_partitions, normal, []) ->
    case wait_for_partitions() of
        true ->
            %% We block until all partitions are initialised
            _ = lager:info("Application master is waiting for plum_db partitions to be initialised; start_phase=init_db_partitions"),
            plum_db_startup_coordinator:wait_for_partitions();
        false ->
            ok
    end;

start_phase(init_db_hashtrees, normal, []) ->
    case wait_for_hashtrees() of
        true ->
            %% We block until all hashtrees are built
            _ = lager:info("Application master is waiting for plum_db hashtrees to be built; start_phase=init_db_hashtrees"),
            plum_db_startup_coordinator:wait_for_hashtrees();
        false ->
            ok
    end,
    %% We stop the coordinator as it is a transcient worker
    plum_db_startup_coordinator:stop();

start_phase(aae_exchange, normal, []) ->
    %% When plum_db is included in a principal application, the latter can
    %% join the cluster before this phase and perform a first aae exchange
    case wait_for_aae_exchange() of
        true ->
            MyNode = plum_db_peer_service:mynode(),
            Members = plumtree_broadcast:broadcast_members(),

            case lists:delete(MyNode, Members) of
                [] ->
                    %% We have not yet joined a cluster, so we finish
                    ok;
                Peers ->
                    _ = lager:info("Application master is waiting for plum_db aae to perform AAE exchange; start_phase=aae_exchange"),
                    %% We are in a cluster, we randomnly pick a peer and
                    %% perform an AAE exchange
                    [Peer|_] = lists_utils:shuffle(Peers),
                    %% We block until the exchange finishes successfully
                    %% or with error, we finish anyway
                    _ = plum_db:sync_exchange(Peer),
                    ok
            end;
        false ->
            ok
    end.


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
prep_stop(_State) ->
    ok.


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
stop(_State) ->
    ok.



%% =============================================================================
%% PRIVATE
%% =============================================================================



%% @private
wait_for_partitions() ->
    %% Waiting for hashtrees implies waiting for partitions
    plum_db_config:get(wait_for_partitions) orelse wait_for_hashtrees().


%% @private
wait_for_hashtrees() ->
    %% If aae is disabled the hastrees will never get build
    %% and we would block forever
    (plum_db_config:get(aae_enabled)
        andalso plum_db_config:get(wait_for_hashtrees))
    orelse wait_for_aae_exchange().


%% @private
wait_for_aae_exchange() ->
    plum_db_config:get(aae_enabled) andalso
    plum_db_config:get(wait_for_aae_exchange).
