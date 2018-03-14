%% -------------------------------------------------------------------
%%
%% Copyright (c) 2015 Christopher Meiklejohn.  All Rights Reserved.
%%
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.
%%
%% -------------------------------------------------------------------

%% -----------------------------------------------------------------------------
%% @doc
%% Based on: github.com/lasp-lang/lasp/...lasp_partisan_peer_service.erl
%% @end
%% -----------------------------------------------------------------------------
-module(plum_db_partisan_peer_service).
-behaviour(plum_db_peer_service).

-define(PEER_SERVICE, partisan_peer_service).

-export([join/1]).
-export([join/2]).
-export([join/3]).
-export([leave/0]).
-export([members/0]).
-export([manager/0]).
-export([myself/0]).
-export([stop/0]).
-export([stop/1]).



%% =============================================================================
%% API
%% =============================================================================



%% -----------------------------------------------------------------------------
%% @doc Prepare node to join a cluster.
%% @end
%% -----------------------------------------------------------------------------
join(Node) ->
    do(join, [Node, true]).


%% -----------------------------------------------------------------------------
%% @doc Convert nodename to atom.
%% @end
%% -----------------------------------------------------------------------------
join(NodeStr, Auto) when is_list(NodeStr) ->
    do(join, [NodeStr, Auto]);

join(Node, Auto) when is_atom(Node) ->
    do(join, [Node, Auto]);

join(#{name := _Name, listen_addrs := _ListenAddrs} = Node, Auto) ->
    do(join, [Node, Auto]).


%% -----------------------------------------------------------------------------
%% @doc Initiate join. Nodes cannot join themselves.
%% @end
%% -----------------------------------------------------------------------------
join(Node, Node, Auto) ->
    do(join, [Node, Node, Auto]).


%% -----------------------------------------------------------------------------
%% @doc Leave the cluster.
%% @end
%% -----------------------------------------------------------------------------
leave() ->
    do(leave, []).


%% -----------------------------------------------------------------------------
%% @doc Leave the cluster.
%% @end
%% -----------------------------------------------------------------------------
members() ->
    do(?PEER_SERVICE, members, []).


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
manager() ->
    do(?PEER_SERVICE, manager, []).


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
myself() ->
    Manager = do(?PEER_SERVICE, manager, []),
    Manager:myself().


%% -----------------------------------------------------------------------------
%% @doc Stop node.
%% @end
%% -----------------------------------------------------------------------------
stop() ->
    stop(stop_request_received).


%% -----------------------------------------------------------------------------
%% @doc Stop node for a given reason.
%% @end
%% -----------------------------------------------------------------------------
stop(Reason) ->
    lager:notice("Stopping; reason=~p", [Reason]),
    do(stop, [Reason]).



%% =============================================================================
%% PRIVATE
%% =============================================================================



%% -----------------------------------------------------------------------------
%% @private
%% @doc Execute call to the proper backend.
%% @end
%% -----------------------------------------------------------------------------
do(join, Args) ->
    erlang:apply(?PEER_SERVICE, join, Args);

do(Function, Args) ->
    erlang:apply(?PEER_SERVICE, Function, Args).


%% -----------------------------------------------------------------------------
%% @private
%% @doc Execute call to the proper backend.
%% @end
%% -----------------------------------------------------------------------------
do(Module, Function, Args) ->
    erlang:apply(Module, Function, Args).