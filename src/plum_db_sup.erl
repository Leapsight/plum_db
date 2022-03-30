%% =============================================================================
%%  plum_db_sup.erl -
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
%% @doc
%% @end
%% -----------------------------------------------------------------------------
-module(plum_db_sup).
-behaviour(supervisor).

-include_lib("kernel/include/logger.hrl").

-define(CHILD(I, Type, Args, Restart, Timeout), #{
    id => I,
    start => {I, start_link, Args},
    restart => Restart,
    shutdown => Timeout,
    type => Type,
    modules => [I]
}).

-define(CHILD(I, Type, Args, Restart), ?CHILD(I, Type, Args, Restart, 5000)).


-export([start_link/0]).
-export([init/1]).



%% =============================================================================
%% API
%% =============================================================================



%% -----------------------------------------------------------------------------
%% @doc Initialises plum_db configuration and starts the supervisor
%% @end
%% -----------------------------------------------------------------------------
start_link() ->
    %% It is important we init the config before starting the supervisor
    %% as we override some user configuration for Partisan.
    ok = plum_db_config:init(),

    case supervisor:start_link({local, ?MODULE}, ?MODULE, []) of
        {ok, _} = OK ->
            % ok = init_db_partitions(),
            % ok = init_db_hashtrees(),
            % ok = aae_exchange(),
            OK;
        Other ->
            Other
    end.



%% =============================================================================
%% SUPERVISOR CALLBACKS
%% =============================================================================



init([]) ->
    RestartStrategy = {one_for_one, 5, 60},
    Children = [
        %% We start the plum_db processes
        ?CHILD(plum_db_events, worker, [], permanent),
        ?CHILD(plum_db_startup_coordinator, worker, [], transient),
        ?CHILD(plum_db_table_owner, worker, [], permanent),
        ?CHILD(plum_db, worker, [], permanent),
        ?CHILD(plum_db_partitions_sup, supervisor, [], permanent),
        ?CHILD(plum_db_exchanges_sup, supervisor, [], permanent)
    ],
    {ok, {RestartStrategy, Children}}.



%% =============================================================================
%% PRIVATE
%% =============================================================================


% init_db_partitions() ->
%     case wait_for_partitions() of
%         true ->
%             %% We block until all partitions are initialised
%             ?LOG_NOTICE(#{
%                 description => "Application master is waiting for plum_db partitions to be initialised"
%             }),
%             plum_db_startup_coordinator:wait_for_partitions();
%         false ->
%             ok
%     end.


% init_db_hashtrees() ->
%     case wait_for_hashtrees() of
%         true ->
%             %% We block until all hashtrees are built
%             ?LOG_NOTICE(#{
%                 description => "Application master is waiting for plum_db hashtrees to be built"
%             }),
%             plum_db_startup_coordinator:wait_for_hashtrees();
%         false ->
%             ok
%     end,
%     %% We stop the coordinator as it is a transcient worker
%     plum_db_startup_coordinator:stop().


% aae_exchange() ->
%     %% When plum_db is included in a principal application, the latter can
%     %% join the cluster before this phase and perform a first aae exchange
%     case wait_for_aae_exchange() of
%         true ->
%             MyNode = partisan:node(),
%             Members = partisan:broadcast_members(),

%             case lists:delete(MyNode, Members) of
%                 [] ->
%                     %% We have not yet joined a cluster, so we finish
%                     ok;
%                 Peers ->
%                     ?LOG_NOTICE(#{
%                         description => "Application master is waiting for plum_db AAE to perform exchange"
%                     }),
%                     %% We are in a cluster, we randomnly pick a peer and
%                     %% perform an AAE exchange
%                     [Peer|_] = lists_utils:shuffle(Peers),
%                     %% We block until the exchange finishes successfully
%                     %% or with error, we finish anyway
%                     _ = plum_db:sync_exchange(Peer),
%                     ok
%             end;
%         false ->
%             ok
%     end.


% %% @private
% wait_for_partitions() ->
%     %% Waiting for hashtrees implies waiting for partitions
%     plum_db_config:get(wait_for_partitions) orelse wait_for_hashtrees().


% %% @private
% wait_for_hashtrees() ->
%     %% If aae is disabled the hastrees will never get build
%     %% and we would block forever
%     (plum_db_config:get(aae_enabled)
%         andalso plum_db_config:get(wait_for_hashtrees))
%     orelse wait_for_aae_exchange().


% %% @private
% wait_for_aae_exchange() ->
%     plum_db_config:get(aae_enabled) andalso
%     plum_db_config:get(wait_for_aae_exchange).
