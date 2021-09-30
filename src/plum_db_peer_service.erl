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
-include_lib("kernel/include/logger.hrl").
-include("plum_db.hrl").

-define(DEFAULT_PEER_SERVICE, partisan_peer_service).

-type partisan_peer()   ::  #{name := _Name, listen_addrs := _ListenAddrs}.
-export_type([partisan_peer/0]).



-export([add_sup_callback/1]).
-export([cast_message/3]).
-export([connections/0]).
-export([decode/1]).
-export([forward_message/3]).
-export([join/1]).
-export([join/2]).
-export([join/3]).
-export([leave/0]).
-export([leave/1]).
-export([manager/0]).
-export([members/0]).
-export([mynode/0]).
-export([myself/0]).
-export([peer_service/0]).
-export([stop/0]).
-export([stop/1]).
-export([sync_join/1]).
-export([sync_join/2]).
-export([sync_join/3]).
-export([update_members/1]).



%% =============================================================================
%% CALLBACKS
%% =============================================================================


%% Attempt to join node.
-callback join(node() | list() | partisan_peer()) -> ok | {error, atom()}.
-callback sync_join(node() | list() | partisan_peer()) -> ok | {error, atom()}.

%% Attempt to join node with or without automatically claiming ring
%% ownership.
-callback join(node() | list() | partisan_peer(), boolean()) ->
    ok | {error, atom()}.
-callback sync_join(node() | list() | partisan_peer(), boolean()) ->
    ok | {error, atom()}.

%% Attempt to join node with or without automatically claiming ring
%% ownership.
-callback join(
    node() | list() | partisan_peer(),
    node() | list() | partisan_peer(), boolean()) -> ok | {error, atom()}.
-callback sync_join(
    node() | list() | partisan_peer(),
    node() | list() | partisan_peer(), boolean()) -> ok | {error, atom()}.


%% Remove myself from the cluster.
-callback leave() -> ok.

%% Remove a node from the cluster.
-callback leave(node() | list() | partisan_peer()) -> ok.

%% Return members of the cluster.
-callback members() -> {ok, [node()]}.

%% Return members of the cluster.
-callback connections() -> {ok, [partisan_peer_service_connections:t()]}.

-callback decode() -> list().


%% Return manager.
-callback myself() -> map().

%% Return manager.
-callback mynode() -> atom().

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
    plum_db_config:get(peer_service, ?DEFAULT_PEER_SERVICE).


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
    do(join, [Node, Auto]);

join(#{name := _Name, listen_addrs := _ListenAddrs} = Node, Auto) ->
    do(join, [Node, Auto]).


%% -----------------------------------------------------------------------------
%% @doc Initiate join. Nodes cannot join themselves.
%% @end
%% -----------------------------------------------------------------------------
join(Node1, Node2, Auto) ->
    do(join, [Node1, Node2, Auto]).


%% -----------------------------------------------------------------------------
%% @doc Prepare node to join a cluster.
%% @end
%% ----------------------------------------------------------------------------
sync_join(Node) ->
    do(sync_join, [Node, true]).


%% -----------------------------------------------------------------------------
%% @doc Prepare node to join a cluster.
%% @end
%% ----------------------------------------------------------------------------
sync_join(Node, Auto) ->
    do(sync_join, [Node, Auto]).


%% -----------------------------------------------------------------------------
%% @doc Prepare node to join a cluster.
%% @end
%% ----------------------------------------------------------------------------
sync_join(Node1, Node2, Auto) ->
    do(sync_join, [Node1, Node2, Auto]).


%% -----------------------------------------------------------------------------
%% @doc Return cluster members.
%% @end
%% -----------------------------------------------------------------------------
members() ->
    do(members, []).

%% -----------------------------------------------------------------------------
%% @doc Update cluster members.
%% @end
%% -----------------------------------------------------------------------------
update_members(Nodes) ->
    do(update_members, [Nodes]).


%% -----------------------------------------------------------------------------
%% @doc Return node connections.
%% @end
%% -----------------------------------------------------------------------------
connections() ->
    do(connections, []).


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
decode(State) ->
    do(decode, [State]).


%% -----------------------------------------------------------------------------
%% @doc Return myself.
%% @end
%% -----------------------------------------------------------------------------
myself() ->
    partisan_peer_service_manager:myself().


%% -----------------------------------------------------------------------------
%% @doc Return myself.
%% @end
%% -----------------------------------------------------------------------------
mynode() ->
    partisan_peer_service_manager:mynode().


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
    leave(mynode()).


%% -----------------------------------------------------------------------------
%% @doc Leave the cluster.
%% @end
%% -----------------------------------------------------------------------------
leave(Peer) ->
    do(leave, [Peer]).


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
    ?LOG_NOTICE(#{
        description => "Stopping",
        reason => Reason
    }),
    do(stop, [Reason]).


%% -----------------------------------------------------------------------------
%% @doc Add callback
%% @end
%% -----------------------------------------------------------------------------
add_sup_callback(Function) ->
    do(add_sup_callback, [Function]).


%% -----------------------------------------------------------------------------
%% @doc Add callback
%% @end
%% -----------------------------------------------------------------------------
cast_message(Name, ServerRef, Message) ->
    do(cast_message, [Name, ?AAE_CHANNEL, ServerRef, Message]).


%% -----------------------------------------------------------------------------
%% @doc Add callback
%% @end
%% -----------------------------------------------------------------------------
forward_message(Name, ServerRef, Message) ->
    do(forward_message, [Name, ?AAE_CHANNEL, ServerRef, Message]).



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


