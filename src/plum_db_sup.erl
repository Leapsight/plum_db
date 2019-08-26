%% =============================================================================
%%  plum_db_sup.erl -
%%
%%  Copyright (c) 2016-2019 Ngineo Limited t/a Leapsight. All rights reserved.
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
    %% as we override some user configuration for both Partisan and Plumtree
    %% before they start (they are included applications and our supervisor
    %% starts them).
    ok = plum_db_config:init(),
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).



%% =============================================================================
%% SUPERVISOR CALLBACKS
%% =============================================================================



init([]) ->
    RestartStrategy = {one_for_one, 5, 60},
    Children = [
        %% We start the included applications
        ?CHILD(partisan_sup, supervisor, [], permanent),
        ?CHILD(plumtree_sup, supervisor, [], permanent),
        %% We start the plum_db processes
        ?CHILD(plum_db_events, worker, [], permanent),
        ?CHILD(plum_db_startup_coordinator, worker, [], transient),
        ?CHILD(plum_db_table_owner, worker, [], permanent),
        ?CHILD(plum_db, worker, [], permanent),

        ?CHILD(plum_db_partitions_sup, supervisor, [], permanent),
        ?CHILD(plum_db_exchanges_sup, supervisor, [], permanent)
    ],
    {ok, {RestartStrategy, Children}}.
