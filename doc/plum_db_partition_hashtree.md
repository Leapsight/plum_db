

# Module plum_db_partition_hashtree #
* [Data Types](#types)
* [Function Index](#index)
* [Function Details](#functions)

__Behaviours:__ [`gen_server`](gen_server.md).

<a name="types"></a>

## Data Types ##




### <a name="type-plum_db_key">plum_db_key()</a> ###


<pre><code>
plum_db_key() = any()
</code></pre>




### <a name="type-plum_db_pkey">plum_db_pkey()</a> ###


<pre><code>
plum_db_pkey() = {<a href="#type-plum_db_prefix">plum_db_prefix()</a>, <a href="#type-plum_db_key">plum_db_key()</a>}
</code></pre>




### <a name="type-plum_db_prefix">plum_db_prefix()</a> ###


<pre><code>
plum_db_prefix() = {binary() | atom(), binary() | atom()}
</code></pre>

<a name="index"></a>

## Function Index ##


<table width="100%" border="1" cellspacing="0" cellpadding="2" summary="function index"><tr><td valign="top"><a href="#code_change-3">code_change/3</a></td><td></td></tr><tr><td valign="top"><a href="#compare-4">compare/4</a></td><td>Compare the local tree managed by this process with the remote
tree also managed by a hashtree process.</td></tr><tr><td valign="top"><a href="#get_bucket-5">get_bucket/5</a></td><td>Return the bucket for a node in the tree managed by this
process running on <code>Node</code>.</td></tr><tr><td valign="top"><a href="#handle_call-3">handle_call/3</a></td><td></td></tr><tr><td valign="top"><a href="#handle_cast-2">handle_cast/2</a></td><td></td></tr><tr><td valign="top"><a href="#handle_info-2">handle_info/2</a></td><td></td></tr><tr><td valign="top"><a href="#init-1">init/1</a></td><td></td></tr><tr><td valign="top"><a href="#insert-2">insert/2</a></td><td>Same as insert(PKey, Hash, false).</td></tr><tr><td valign="top"><a href="#insert-3">insert/3</a></td><td>Insert a hash for a full-prefix and key into the tree
managed by the process.</td></tr><tr><td valign="top"><a href="#insert-4">insert/4</a></td><td></td></tr><tr><td valign="top"><a href="#key_hashes-4">key_hashes/4</a></td><td>Return the key hashes for a node in the tree managed by this
process running on <code>Node</code>.</td></tr><tr><td valign="top"><a href="#lock-1">lock/1</a></td><td>Locks the tree on this node for updating on behalf of the
calling process.</td></tr><tr><td valign="top"><a href="#lock-2">lock/2</a></td><td>Locks the tree on <code>Node</code> for updating on behalf of the calling
process.</td></tr><tr><td valign="top"><a href="#lock-3">lock/3</a></td><td>Lock the tree for updating.</td></tr><tr><td valign="top"><a href="#name-1">name/1</a></td><td></td></tr><tr><td valign="top"><a href="#prefix_hash-2">prefix_hash/2</a></td><td>Return the hash for the given prefix or full-prefix.</td></tr><tr><td valign="top"><a href="#release_lock-1">release_lock/1</a></td><td>Locks the tree on this node for updating on behalf of the
calling process.</td></tr><tr><td valign="top"><a href="#release_lock-2">release_lock/2</a></td><td>Locks the tree on <code>Node</code> for updating on behalf of the calling
process.</td></tr><tr><td valign="top"><a href="#release_lock-3">release_lock/3</a></td><td>Lock the tree for updating.</td></tr><tr><td valign="top"><a href="#reset-1">reset/1</a></td><td>Destroys the partition's hashtrees on the local node and rebuilds it.</td></tr><tr><td valign="top"><a href="#reset-2">reset/2</a></td><td>Destroys the partition's hashtrees on node <code>Node</code> and rebuilds it.</td></tr><tr><td valign="top"><a href="#start_link-1">start_link/1</a></td><td>Starts the process using <a href="#start_link-1"><code>start_link/1</code></a>, passing in the
directory where other cluster data is stored in <code>hashtrees_dir</code>
as the data root.</td></tr><tr><td valign="top"><a href="#terminate-2">terminate/2</a></td><td></td></tr><tr><td valign="top"><a href="#update-1">update/1</a></td><td>Updates the tree on this node.</td></tr><tr><td valign="top"><a href="#update-2">update/2</a></td><td>Updates the tree on <code>Node</code>.</td></tr></table>


<a name="functions"></a>

## Function Details ##

<a name="code_change-3"></a>

### code_change/3 ###

`code_change(OldVsn, State, Extra) -> any()`

<a name="compare-4"></a>

### compare/4 ###

<pre><code>
compare(Partition::<a href="plum_db.md#type-partition">plum_db:partition()</a>, RemoteFun::<a href="hashtree_tree.md#type-remote_fun">hashtree_tree:remote_fun()</a>, HandlerFun::<a href="hashtree_tree.md#type-handler_fun">hashtree_tree:handler_fun</a>(X), X) -&gt; X
</code></pre>
<br />

Compare the local tree managed by this process with the remote
tree also managed by a hashtree process. `RemoteFun` is
used to access the buckets and segments of nodes in the remote tree
and should usually call [`get_bucket/5`](#get_bucket-5) and [`key_hashes/4`](#key_hashes-4). `HandlerFun` is used to process the differences
found between the two trees. `HandlerAcc` is passed to the first
invocation of `HandlerFun`. Subsequent calls are passed the return
value from the previous call.  This function returns the return
value from the last call to `HandlerFun`. [`hashtree_tree`](hashtree_tree.md) for
more details on `RemoteFun`, `HandlerFun` and `HandlerAcc`.

<a name="get_bucket-5"></a>

### get_bucket/5 ###

<pre><code>
get_bucket(Node::node(), Partition::non_neg_integer(), Prefixes::<a href="hashtree_tree.md#type-tree_node">hashtree_tree:tree_node()</a>, Level::non_neg_integer(), Bucket::non_neg_integer()) -&gt; <a href="orddict.md#type-orddict">orddict:orddict()</a>
</code></pre>
<br />

Return the bucket for a node in the tree managed by this
process running on `Node`.

<a name="handle_call-3"></a>

### handle_call/3 ###

`handle_call(X1, From, State) -> any()`

<a name="handle_cast-2"></a>

### handle_cast/2 ###

`handle_cast(Msg, State) -> any()`

<a name="handle_info-2"></a>

### handle_info/2 ###

`handle_info(Event, State) -> any()`

<a name="init-1"></a>

### init/1 ###

`init(X1) -> any()`

<a name="insert-2"></a>

### insert/2 ###

<pre><code>
insert(PKey::<a href="#type-plum_db_pkey">plum_db_pkey()</a>, Hash::binary()) -&gt; ok
</code></pre>
<br />

Same as insert(PKey, Hash, false).

<a name="insert-3"></a>

### insert/3 ###

<pre><code>
insert(PKey::<a href="#type-plum_db_pkey">plum_db_pkey()</a>, Hash::binary(), IfMissing::boolean()) -&gt; ok
</code></pre>
<br />

Insert a hash for a full-prefix and key into the tree
managed by the process. If `IfMissing` is `true` the hash is only
inserted into the tree if the key is not already present.

<a name="insert-4"></a>

### insert/4 ###

<pre><code>
insert(Partition::<a href="pbd.md#type-partition">pbd:partition()</a>, PKey::<a href="#type-plum_db_pkey">plum_db_pkey()</a>, Hash::binary(), IfMissing::boolean()) -&gt; ok
</code></pre>
<br />

<a name="key_hashes-4"></a>

### key_hashes/4 ###

<pre><code>
key_hashes(Node::node(), Partition::non_neg_integer(), Prefixes::<a href="hashtree_tree.md#type-tree_node">hashtree_tree:tree_node()</a>, Segment::non_neg_integer()) -&gt; <a href="orddict.md#type-orddict">orddict:orddict()</a>
</code></pre>
<br />

Return the key hashes for a node in the tree managed by this
process running on `Node`.

<a name="lock-1"></a>

### lock/1 ###

<pre><code>
lock(Partition::<a href="plum_db.md#type-partition">plum_db:partition()</a>) -&gt; ok | not_built | locked
</code></pre>
<br />

Locks the tree on this node for updating on behalf of the
calling process.

__See also:__ [lock/3](#lock-3).

<a name="lock-2"></a>

### lock/2 ###

<pre><code>
lock(Node::node(), Partition::<a href="plum_db.md#type-partition">plum_db:partition()</a>) -&gt; ok | not_built | locked
</code></pre>
<br />

Locks the tree on `Node` for updating on behalf of the calling
process.

__See also:__ [lock/3](#lock-3).

<a name="lock-3"></a>

### lock/3 ###

<pre><code>
lock(Node::node(), Partition::<a href="plum_db.md#type-partition">plum_db:partition()</a>, Pid::pid()) -&gt; ok | not_built | locked
</code></pre>
<br />

Lock the tree for updating. This function must be called
before updating the tree with [`update/1`](#update-1) or [`update/2`](#update-2). If the tree is not built or already locked then the call
will fail and the appropriate atom is returned. Otherwise,
aqcuiring the lock succeeds and `ok` is returned.

<a name="name-1"></a>

### name/1 ###

`name(Partition) -> any()`

<a name="prefix_hash-2"></a>

### prefix_hash/2 ###

<pre><code>
prefix_hash(Partition::<a href="plum_db.md#type-partition">plum_db:partition()</a> | pid() | atom(), Prefix::<a href="#type-plum_db_prefix">plum_db_prefix()</a> | binary() | atom()) -&gt; undefined | binary()
</code></pre>
<br />

Return the hash for the given prefix or full-prefix

<a name="release_lock-1"></a>

### release_lock/1 ###

<pre><code>
release_lock(Partition::<a href="plum_db.md#type-partition">plum_db:partition()</a>) -&gt; ok
</code></pre>
<br />

Locks the tree on this node for updating on behalf of the
calling process.

__See also:__ [lock/3](#lock-3).

<a name="release_lock-2"></a>

### release_lock/2 ###

<pre><code>
release_lock(Node::node(), Partition::<a href="plum_db.md#type-partition">plum_db:partition()</a>) -&gt; ok
</code></pre>
<br />

Locks the tree on `Node` for updating on behalf of the calling
process.

__See also:__ [lock/3](#lock-3).

<a name="release_lock-3"></a>

### release_lock/3 ###

<pre><code>
release_lock(Node::node(), Partition::<a href="plum_db.md#type-partition">plum_db:partition()</a>, Pid::pid()) -&gt; ok | {error, not_locked | not_allowed}
</code></pre>
<br />

Lock the tree for updating. This function must be called
before updating the tree with [`update/1`](#update-1) or [`update/2`](#update-2). If the tree is not built or already locked then the call
will fail and the appropriate atom is returned. Otherwise,
aqcuiring the lock succeeds and `ok` is returned.

<a name="reset-1"></a>

### reset/1 ###

<pre><code>
reset(Partition::<a href="plum_db.md#type-partition">plum_db:partition()</a>) -&gt; ok
</code></pre>
<br />

Destroys the partition's hashtrees on the local node and rebuilds it.

<a name="reset-2"></a>

### reset/2 ###

<pre><code>
reset(Node::node(), Partition::<a href="plum_db.md#type-partition">plum_db:partition()</a>) -&gt; ok
</code></pre>
<br />

Destroys the partition's hashtrees on node `Node` and rebuilds it.

<a name="start_link-1"></a>

### start_link/1 ###

<pre><code>
start_link(Partition::non_neg_integer()) -&gt; {ok, pid()} | ignore | {error, term()}
</code></pre>
<br />

Starts the process using [`start_link/1`](#start_link-1), passing in the
directory where other cluster data is stored in `hashtrees_dir`
as the data root.

<a name="terminate-2"></a>

### terminate/2 ###

`terminate(Reason, State0) -> any()`

<a name="update-1"></a>

### update/1 ###

<pre><code>
update(Partition::<a href="plum_db.md#type-partition">plum_db:partition()</a>) -&gt; ok | not_locked | not_built | ongoing_update
</code></pre>
<br />

Updates the tree on this node.

__See also:__ [update/2](#update-2).

<a name="update-2"></a>

### update/2 ###

<pre><code>
update(Node::node(), Partition::<a href="plum_db.md#type-partition">plum_db:partition()</a>) -&gt; ok | not_locked | not_built | ongoing_update
</code></pre>
<br />

Updates the tree on `Node`. The tree must be locked using one
of the lock functions. If the tree is not locked or built the
update will not be started and the appropriate atom is
returned. Although this function should not be called without a
lock, if it is and the tree is being updated by the background tick
then `ongoing_update` is returned. If the tree is built and a lock
has been acquired then the update is started and `ok` is
returned. The update is performed asynchronously and does not block
the process that manages the tree (e.g. future inserts).

