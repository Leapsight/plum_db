%% =============================================================================
%%  plum_db_partition_worker.erl -
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
-behaviour(supervisor).


-export([get_db_info/1]).
-export([set_db_info/2]).
-export([start_link/0]).


-export([init/1]).



%% =============================================================================
%% API
%% =============================================================================



start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).


get_db_info(ServerRef) ->
    ets:lookup_element(?MODULE, ServerRef, 2).


set_db_info(ServerRef, Data) ->
    true = ets:insert(?MODULE, {ServerRef, Data}),
    ok.



%% =============================================================================
%% SUPERVISOR CALLBACKS
%% =============================================================================



init([]) ->
    RestartStrategy = {one_for_one, 5, 60},
    Children = [
        #{
            id => plum_db_partition_sup:name(Id),
            start => {
                plum_db_partition_sup,
                start_link,
                [Id]
            },
            restart => permanent,
            shutdown => infinity,
            type => supervisor,
            modules => [plum_db_partition_sup]
        }
        || Id <- plum_db:partitions()
    ],

    ok = setup_db_info_tab(),

    {ok, {RestartStrategy, Children}}.



setup_db_info_tab() ->
    EtsOpts = [
        named_table,
        public,
        set,
        {read_concurrency, true}
    ],

    {ok, ?MODULE} = plum_db_table_owner:add_or_claim(?MODULE, EtsOpts),
    ok.