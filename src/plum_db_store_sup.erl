%% -----------------------------------------------------------------------------
%%    Copyright 2018 Ngineo Limited t/a Leapsight
%%
%%    Licensed under the Apache License, Version 2.0 (the "License");
%%    you may not use this file except in compliance with the License.
%%    You may obtain a copy of the License at
%%
%%        http://www.apache.org/licenses/LICENSE-2.0
%%
%%    Unless required by applicable law or agreed to in writing, software
%%    distributed under the License is distributed on an "AS IS" BASIS,
%%    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%%    See the License for the specific language governing permissions and
%%    limitations under the License.
%% -----------------------------------------------------------------------------

-module(plum_db_store_sup).
-behaviour(supervisor).

-define(CHILD(Id, Mod, Type, Args, Timeout),
    {Id, {Mod, start_link, Args}, permanent, Timeout, Type, [Mod]}).



-export([start_link/0]).
-export([init/1]).



%% =============================================================================
%% API
%% =============================================================================



start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).



%% =============================================================================
%% SUPERVISOR CALLBACKS
%% =============================================================================



init([]) ->
    RestartStrategy = {one_for_one, 5, 1},
    Children = [
        #{
            id => plum_db_store_partition_sup:name(Id),
            start => {
                plum_db_store_partition_sup,
                start_link,
                [Id]
            },
            restart => permanent,
            shutdown => infinity,
            type => supervisor,
            modules => [plum_db_store_partition_sup]
        }
        || Id <- plum_db:partitions()
    ],
    {ok, {RestartStrategy, Children}}.
