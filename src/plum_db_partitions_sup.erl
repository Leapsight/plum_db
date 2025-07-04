%% =============================================================================
%%  plum_db_partitions_sup.erl -
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

-module(plum_db_partitions_sup).
-behaviour(partisan_gen_supervisor).

-export([start_link/0]).
-export([add_partition/3]).


-export([init/1]).



%% =============================================================================
%% API
%% =============================================================================



start_link() ->
    partisan_gen_supervisor:start_link({local, ?MODULE}, ?MODULE, []).


add_partition(Id, ServerOpts, HashtreeOpts) ->
    ChildSpec = #{
        id => plum_db_partition_sup:name(Id),
        start => {
            plum_db_partition_sup,
            start_link,
            [Id, ServerOpts, HashtreeOpts]
        },
        restart => permanent,
        shutdown => infinity,
        type => supervisor,
        modules => [plum_db_partition_sup]
    },
    partisan_gen_supervisor:start_child(?MODULE, ChildSpec).


%% =============================================================================
%% SUPERVISOR CALLBACKS
%% =============================================================================



init([]) ->
    RestartStrategy = {one_for_one, 10, 60},
    Children = [
        #{
            id => plum_db_partition_manager,
            start => {
                plum_db_partition_manager,
                start_link,
                []
            },
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [plum_db_partition_manager]
        }
    ],

    {ok, {RestartStrategy, Children}}.
