%% =============================================================================
%%  plum_db_partition_sup.erl -
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

-module(plum_db_partition_sup).
-behaviour(partisan_gen_supervisor).


-export([start_link/3]).
-export([init/1]).
-export([name/1]).



%% =============================================================================
%% API
%% =============================================================================



start_link(Id, ServerOpts, HashtreeOpts) ->
    Name = name(Id),
    supervisor:start_link(
        {local, Name}, ?MODULE, [Id, ServerOpts, HashtreeOpts]
    ).



%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
%% @private
name(Id) when is_integer(Id) ->
    list_to_atom("plum_db_partition_" ++ integer_to_list(Id) ++ "_sup").


%% =============================================================================
%% SUPERVISOR CALLBACKS
%% =============================================================================



init([Id, ServerOpts, HashtreeOpts]) ->
    RestartStrategy = {rest_for_one, 20, 60},
    Children = [
        #{
            id => plum_db_partition_server:name(Id),
            start => {
                plum_db_partition_server,
                start_link,
                [Id, ServerOpts]
            },
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [plum_db_partition_server]
        },
        #{
            id => plum_db_partition_hashtree:name(Id),
            start => {
                plum_db_partition_hashtree,
                start_link,
                [Id, HashtreeOpts]
            },
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [plum_db_partition_hashtree]
        }
    ],
    {ok, {RestartStrategy, Children}}.
