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

-module(pdb_store_partition_sup).
-behaviour(supervisor).

-define(CHILD(Id, Mod, Type, Args, Timeout),
    {Id, {Mod, start_link, Args}, permanent, Timeout, Type, [Mod]}).



-export([start_link/1]).
-export([init/1]).
-export([name/1]).



%% =============================================================================
%% API
%% =============================================================================



start_link(PartitionId) ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, [PartitionId]).



%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
%% @private
name(Id) when is_integer(Id) ->
    list_to_atom("pdb_store_partition_sup_" ++ integer_to_list(Id)).


%% =============================================================================
%% SUPERVISOR CALLBACKS
%% =============================================================================



init([Id]) ->
    Opts = application:get_env(pdb, leveldb_opts, []),
    RestartStrategy = {one_for_all, 5, 1},
    Children = [
        #{
            id => pdb_store_server:name(Id),
            start => {
                pdb_store_server,
                start_link,
                [Id, Opts]
            },
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [pdb_store_server]
        },
        #{
            id => pdb_store_worker:name(Id),
            start => {
                pdb_store_worker,
                start_link,
                [Id]
            },
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [pdb_store_worker]
        },
        #{
            id => pdb_hashtree:name(Id),
            start => {
                pdb_hashtree,
                start_link,
                [Id]
            },
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [pdb_hashtree]
        }
    ],
    {ok, {RestartStrategy, Children}}.
