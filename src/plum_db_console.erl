%% =============================================================================
%%  plum_db_console.erl -
%%
%%  Copyright (c) 2018-2019 Leapsight t/a Leapsight. All rights reserved.
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

-module(plum_db_console).
-include("plum_db.hrl").

-export([members/1]).





%% =============================================================================
%% API
%% =============================================================================



members([]) ->
    {ok, Members} = plum_db_peer_service:members(),
    print_members(Members).




%% =============================================================================
%% PRIVATE
%% =============================================================================



print_members(Members) ->
    _ = io:format("~29..=s Cluster Membership ~30..=s~n", ["",""]),
    _ = io:format("Connected Nodes:~n~n", []),
    _ = [io:format("~p~n", [Node]) || Node <- Members],
    _ = io:format("~79..=s~n", [""]),
    ok.
