

# Module plum_db_peer_service #
* [Description](#description)
* [Data Types](#types)
* [Function Index](#index)
* [Function Details](#functions)

Based on: github.com/lasp-lang/lasp/...lasp_peer_service.erl.

__This module defines the `plum_db_peer_service` behaviour.__<br /> Required callback functions: `join/1`, `sync_join/1`, `join/2`, `sync_join/2`, `join/3`, `sync_join/3`, `leave/0`, `leave/1`, `members/0`, `connections/0`, `decode/0`, `myself/0`, `mynode/0`, `manager/0`, `stop/0`, `stop/1`.

<a name="types"></a>

## Data Types ##




### <a name="type-partisan_peer">partisan_peer()</a> ###


<pre><code>
partisan_peer() = #{name =&gt; _Name, listen_addrs =&gt; _ListenAddrs}
</code></pre>

<a name="index"></a>

## Function Index ##


<table width="100%" border="1" cellspacing="0" cellpadding="2" summary="function index"><tr><td valign="top"><a href="#add_sup_callback-1">add_sup_callback/1</a></td><td>Add callback.</td></tr><tr><td valign="top"><a href="#cast_message-3">cast_message/3</a></td><td>Add callback.</td></tr><tr><td valign="top"><a href="#connections-0">connections/0</a></td><td>Return node connections.</td></tr><tr><td valign="top"><a href="#decode-1">decode/1</a></td><td></td></tr><tr><td valign="top"><a href="#forward_message-3">forward_message/3</a></td><td>Add callback.</td></tr><tr><td valign="top"><a href="#join-1">join/1</a></td><td>Prepare node to join a cluster.</td></tr><tr><td valign="top"><a href="#join-2">join/2</a></td><td>Convert nodename to atom.</td></tr><tr><td valign="top"><a href="#join-3">join/3</a></td><td>Initiate join.</td></tr><tr><td valign="top"><a href="#leave-0">leave/0</a></td><td>Leave the cluster.</td></tr><tr><td valign="top"><a href="#leave-1">leave/1</a></td><td>Leave the cluster.</td></tr><tr><td valign="top"><a href="#manager-0">manager/0</a></td><td>Return manager.</td></tr><tr><td valign="top"><a href="#members-0">members/0</a></td><td>Return cluster members.</td></tr><tr><td valign="top"><a href="#mynode-0">mynode/0</a></td><td>Return myself.</td></tr><tr><td valign="top"><a href="#myself-0">myself/0</a></td><td>Return myself.</td></tr><tr><td valign="top"><a href="#peer_service-0">peer_service/0</a></td><td>Return the currently active peer service.</td></tr><tr><td valign="top"><a href="#stop-0">stop/0</a></td><td>Stop node.</td></tr><tr><td valign="top"><a href="#stop-1">stop/1</a></td><td>Stop node for a given reason.</td></tr><tr><td valign="top"><a href="#sync_join-1">sync_join/1</a></td><td>Prepare node to join a cluster.</td></tr><tr><td valign="top"><a href="#sync_join-2">sync_join/2</a></td><td>Prepare node to join a cluster.</td></tr><tr><td valign="top"><a href="#sync_join-3">sync_join/3</a></td><td>Prepare node to join a cluster.</td></tr><tr><td valign="top"><a href="#update_members-1">update_members/1</a></td><td>Update cluster members.</td></tr></table>


<a name="functions"></a>

## Function Details ##

<a name="add_sup_callback-1"></a>

### add_sup_callback/1 ###

`add_sup_callback(Function) -> any()`

Add callback

<a name="cast_message-3"></a>

### cast_message/3 ###

`cast_message(Name, ServerRef, Message) -> any()`

Add callback

<a name="connections-0"></a>

### connections/0 ###

`connections() -> any()`

Return node connections.

<a name="decode-1"></a>

### decode/1 ###

`decode(State) -> any()`

<a name="forward_message-3"></a>

### forward_message/3 ###

`forward_message(Name, ServerRef, Message) -> any()`

Add callback

<a name="join-1"></a>

### join/1 ###

`join(Node) -> any()`

Prepare node to join a cluster.

<a name="join-2"></a>

### join/2 ###

`join(NodeStr, Auto) -> any()`

Convert nodename to atom.

<a name="join-3"></a>

### join/3 ###

`join(Node1, Node2, Auto) -> any()`

Initiate join. Nodes cannot join themselves.

<a name="leave-0"></a>

### leave/0 ###

`leave() -> any()`

Leave the cluster.

<a name="leave-1"></a>

### leave/1 ###

`leave(Peer) -> any()`

Leave the cluster.

<a name="manager-0"></a>

### manager/0 ###

`manager() -> any()`

Return manager.

<a name="members-0"></a>

### members/0 ###

`members() -> any()`

Return cluster members.

<a name="mynode-0"></a>

### mynode/0 ###

`mynode() -> any()`

Return myself.

<a name="myself-0"></a>

### myself/0 ###

`myself() -> any()`

Return myself.

<a name="peer_service-0"></a>

### peer_service/0 ###

`peer_service() -> any()`

Return the currently active peer service.

<a name="stop-0"></a>

### stop/0 ###

`stop() -> any()`

Stop node.

<a name="stop-1"></a>

### stop/1 ###

`stop(Reason) -> any()`

Stop node for a given reason.

<a name="sync_join-1"></a>

### sync_join/1 ###

`sync_join(Node) -> any()`

Prepare node to join a cluster.

<a name="sync_join-2"></a>

### sync_join/2 ###

`sync_join(Node, Auto) -> any()`

Prepare node to join a cluster.

<a name="sync_join-3"></a>

### sync_join/3 ###

`sync_join(Node1, Node2, Auto) -> any()`

Prepare node to join a cluster.

<a name="update_members-1"></a>

### update_members/1 ###

`update_members(Nodes) -> any()`

Update cluster members.

