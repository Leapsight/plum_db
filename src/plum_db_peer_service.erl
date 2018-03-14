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
%% Based on: github.com/lasp-lang/lasp/...lasp_peer_service.erl
%% @end
%% -----------------------------------------------------------------------------
-module(plum_db_peer_service).

-define(DEFAULT_PEER_SERVICE, plum_db_partisan_peer_service).


-export([join/1]).
-export([join/2]).
-export([join/3]).
-export([leave/0]).
-export([manager/0]).
-export([myself/0]).
-export([members/0]).
-export([peer_service/0]).
-export([stop/0]).
-export([stop/1]).



%% =============================================================================
%% CALLBACKS
%% =============================================================================


%% Attempt to join node.
-callback join(node()) -> ok | {error, atom()}.

%% Attempt to join node with or without automatically claiming ring
%% ownership.
-callback join(node(), boolean()) -> ok | {error, atom()}.

%% Attempt to join node with or without automatically claiming ring
%% ownership.
-callback join(node(), node(), boolean()) -> ok | {error, atom()}.

%% Remove a node from the cluster.
-callback leave() -> ok.

%% Return members of the cluster.
-callback members() -> {ok, [node()]}.

%% Return manager.
-callback manager() -> module().

%% Stop the peer service on a given node.
-callback stop() -> ok.

%% Stop the peer service on a given node for a particular reason.
-callback stop(iolist()) -> ok.



%% =============================================================================
%% API
%% =============================================================================


%% -----------------------------------------------------------------------------
%% @doc Return the currently active peer service.
%% @end
%% -----------------------------------------------------------------------------
peer_service() ->
    application:get_env(plum_db, peer_service, ?DEFAULT_PEER_SERVICE).


%% -----------------------------------------------------------------------------
%% @doc Prepare node to join a cluster.
%% @end
%% ----------------------------------------------------------------------------
join(Node) ->
    do(join, [Node, true]).


%% -----------------------------------------------------------------------------
%% @doc Convert nodename to atom.
%% @end
%% -----------------------------------------------------------------------------
join(NodeStr, Auto) when is_list(NodeStr) ->
    do(join, [NodeStr, Auto]);

join(Node, Auto) when is_atom(Node) ->
    do(join, [Node, Auto]).


%% -----------------------------------------------------------------------------
%% @doc Initiate join. Nodes cannot join themselves.
%% @end
%% -----------------------------------------------------------------------------
join(Node, Node, Auto) ->
    do(join, [Node, Node, Auto]).


%% -----------------------------------------------------------------------------
%% @doc Return cluster members.
%% @end
%% -----------------------------------------------------------------------------
members() ->
    do(members, []).


%% -----------------------------------------------------------------------------
%% @doc Return myself.
%% @end
%% -----------------------------------------------------------------------------
myself() ->
    do(myself, []).


%% -----------------------------------------------------------------------------
%% @doc Return manager.
%% @end
%% -----------------------------------------------------------------------------
manager() ->
    do(manager, []).


%% -----------------------------------------------------------------------------
%% @doc Leave the cluster.
%% @end
%% -----------------------------------------------------------------------------
leave() ->
    do(leave, []).


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
    do(stop, [Reason]).



%% =============================================================================
%% PRIVATE
%% =============================================================================



%% -----------------------------------------------------------------------------
%% @doc Execute call to the proper backend.
%% @end
%% -----------------------------------------------------------------------------
do(Function, Args) ->
    Backend = peer_service(),
    erlang:apply(Backend, Function, Args).


