

# Module hashtree_tree #
* [Description](#description)
* [Data Types](#types)
* [Function Index](#index)
* [Function Details](#functions)

This module implements a specialized hash tree that is used
primarily by cluster metadata's anti-entropy exchanges and by
metadata clients for determining when groups of metadata keys have
changed locally.

<a name="description"></a>

## Description ##

The tree can be used, generally, for determining
the differences in groups of keys, or to find missing groups, between
two stores.

Each node of the tree is itself a hash tree, specifically a [`hashtree`](hashtree.md).  The tree has a fixed height but each node has a
variable amount of children. The height of the tree directly
corresponds to the number of prefixes supported by the tree. A list
of prefixes, or a "prefix list", represent a group of keys. Each
unique prefix list is a node in the tree. The leaves store hashes
for the individual keys in the segments of the node's [`hashtree`](hashtree.md). The buckets of the leaves' hashtree provide an efficient
way of determining when keys in the segments differ between two
trees.  The tails of the prefix list are used to roll up groups
into parent groups. For example, the prefixes `[a, b]`, `[a, c]`,
`[d, e]` will be rolled up into parent groups `a`, containing `c`
and `b`, and `d`, containing only 'e'. The parent group's node has
children corresponding to each child group. The top-hashes of the
child nodes are stored in the parent nodes' segments. The parent
nodes' buckets are used as an efficient method for determining when
child groups differ between two trees. The root node corresponds to
the empty list and it acts like any other node, storing hashes for
the first level of child groups. The top hash of the root node is
the top hash of the tree.

The tree in the example above might store something like:

node    parent   top-hash  segments
---------------------------------------------------
root     none       1      [{a, 2}, {d, 3}]
[a]      root       2      [{b, 4}, {c, 5}]
[d]      root       3      [{e, 6}]
[a,b]    [a]        4      [{k1, 0}, {k2, 6}, ...]
[a,c]    [a]        5      [{k1, 1}, {k2, 4}, ...]
[d,e]    [d]        6      [{k1, 2}, {k2, 3}, ...]

When a key is inserted into the tree it is inserted into the leaf
corresponding to the given prefix list. The leaf and its parents
are not updated at this time. Instead the leaf is added to a dirty
set. The nodes are later updated in bulk.

Updating the hashtree is a two step process. First, a snapshot of
the tree must be obtained. This prevents new writes from affecting
the update. Snapshotting the tree will snapshot each dirty
leaf. Since writes to nodes other than leaves only occur during
updates no snapshot is taken for them. Second, the tree is updated
using the snapshot. The update is performed by updating the [`hashtree`](hashtree.md) nodes at each level starting with the leaves. The top
hash of each node in a level is inserted into its parent node after
being updated. The list of dirty parents is then updated, moving up
the tree. Once the root is reached and has been updated the process
is complete. This process is designed to minimize the traversal of
the tree and ensure that each node is only updated once.

The typical use for updating a tree is to compare it with another
recently updated tree. Comparison is done with the `compare/4`
function.  Compare provides a sort of fold over the differences of
the tree allowing for callers to determine what to do with those
differences. In addition, the caller can accumulate a value, such
as the difference list or stats about differencces.

The tree implemented in this module assumes that it will be managed
by a single process and that all calls will be made to it synchronously, with
a couple exceptions:

1. Updating a tree with a snapshot can be done in another process. The snapshot
must be taken by the owning process, synchronously.
2. Comparing two trees may be done by a seperate process. Compares should should use
a snapshot and only be performed after an update.

The nodes in this tree are backend by LevelDB, however, this is
most likely temporary and Cluster Metadata's use of the tree is
ephemeral. Trees are only meant to live for the lifetime of a
running node and are rebuilt on start.  To ensure the tree is fresh
each time, when nodes are created the backing LevelDB store is
opened, closed, and then re-opened to ensure any lingering files
are removed.  Additionally, the nodes themselves (references to
[`hashtree`](hashtree.md), are stored in [`ets`](ets.md).
<a name="types"></a>

## Data Types ##




### <a name="type-diff">diff()</a> ###


<pre><code>
diff() = <a href="#type-prefix_diff">prefix_diff()</a> | <a href="#type-key_diffs">key_diffs()</a>
</code></pre>




### <a name="type-handler_fun">handler_fun()</a> ###


<pre><code>
handler_fun(X) = fun((<a href="#type-diff">diff()</a>, X) -&gt; X)
</code></pre>




### <a name="type-insert_opt">insert_opt()</a> ###


<pre><code>
insert_opt() = <a href="#type-insert_opt_if_missing">insert_opt_if_missing()</a>
</code></pre>




### <a name="type-insert_opt_if_missing">insert_opt_if_missing()</a> ###


<pre><code>
insert_opt_if_missing() = {if_missing, boolean()}
</code></pre>




### <a name="type-insert_opts">insert_opts()</a> ###


<pre><code>
insert_opts() = [<a href="#type-insert_opt">insert_opt()</a>]
</code></pre>




### <a name="type-key_diffs">key_diffs()</a> ###


<pre><code>
key_diffs() = {key_diffs, <a href="#type-prefixes">prefixes()</a>, [{missing | remote_missing | different, binary()}]}
</code></pre>




### <a name="type-new_opt">new_opt()</a> ###


<pre><code>
new_opt() = <a href="#type-new_opt_num_levels">new_opt_num_levels()</a> | <a href="#type-new_opt_data_dir">new_opt_data_dir()</a>
</code></pre>




### <a name="type-new_opt_data_dir">new_opt_data_dir()</a> ###


<pre><code>
new_opt_data_dir() = {data_dir, <a href="file.md#type-name_all">file:name_all()</a>}
</code></pre>




### <a name="type-new_opt_num_levels">new_opt_num_levels()</a> ###


<pre><code>
new_opt_num_levels() = {num_levels, non_neg_integer()}
</code></pre>




### <a name="type-new_opts">new_opts()</a> ###


<pre><code>
new_opts() = [<a href="#type-new_opt">new_opt()</a>]
</code></pre>




### <a name="type-prefix">prefix()</a> ###


<pre><code>
prefix() = atom() | binary()
</code></pre>




### <a name="type-prefix_diff">prefix_diff()</a> ###


<pre><code>
prefix_diff() = {missing_prefix, local | remote, <a href="#type-prefixes">prefixes()</a>}
</code></pre>




### <a name="type-prefixes">prefixes()</a> ###


<pre><code>
prefixes() = [<a href="#type-prefix">prefix()</a>]
</code></pre>




### <a name="type-remote_fun">remote_fun()</a> ###


<pre><code>
remote_fun() = fun((<a href="#type-prefixes">prefixes()</a>, {get_bucket, {integer(), integer()}} | {key_hashses, integer()}) -&gt; <a href="orddict.md#type-orddict">orddict:orddict()</a>)
</code></pre>




### <a name="type-tree">tree()</a> ###


__abstract datatype__: `tree()`




### <a name="type-tree_node">tree_node()</a> ###


__abstract datatype__: `tree_node()`

<a name="index"></a>

## Function Index ##


<table width="100%" border="1" cellspacing="0" cellpadding="2" summary="function index"><tr><td valign="top"><a href="#compare-4">compare/4</a></td><td>Compare a local and remote tree.</td></tr><tr><td valign="top"><a href="#destroy-1">destroy/1</a></td><td>Destroys the tree cleaning up any used resources.</td></tr><tr><td valign="top"><a href="#get_bucket-4">get_bucket/4</a></td><td>Returns the <a href="hashtree.md"><code>hashtree</code></a> buckets for a given node in the
tree.</td></tr><tr><td valign="top"><a href="#insert-4">insert/4</a></td><td>an alias for insert(Prefixes, Key, Hash, [], Tree).</td></tr><tr><td valign="top"><a href="#insert-5">insert/5</a></td><td>Insert a hash into the tree.</td></tr><tr><td valign="top"><a href="#key_hashes-3">key_hashes/3</a></td><td>Returns the <a href="hashtree.md"><code>hashtree</code></a> segment hashes for a given node
in the tree.</td></tr><tr><td valign="top"><a href="#local_compare-2">local_compare/2</a></td><td>Compare two local trees.</td></tr><tr><td valign="top"><a href="#new-2">new/2</a></td><td>Creates a new hashtree.</td></tr><tr><td valign="top"><a href="#prefix_hash-2">prefix_hash/2</a></td><td>Returns the top-hash of the node corresponding to the given
prefix list.</td></tr><tr><td valign="top"><a href="#top_hash-1">top_hash/1</a></td><td>Returns the top-hash of the tree.</td></tr><tr><td valign="top"><a href="#update_perform-1">update_perform/1</a></td><td>Update the tree with a snapshot obtained by <a href="#update_snapshot-1"><code>update_snapshot/1</code></a>.</td></tr><tr><td valign="top"><a href="#update_snapshot-1">update_snapshot/1</a></td><td>Snapshot the tree for updating.</td></tr></table>


<a name="functions"></a>

## Function Details ##

<a name="compare-4"></a>

### compare/4 ###

<pre><code>
compare(LocalTree::<a href="#type-tree">tree()</a>, RemoteFun::<a href="#type-remote_fun">remote_fun()</a>, HandlerFun::<a href="#type-handler_fun">handler_fun</a>(X), X) -&gt; X
</code></pre>
<br />

Compare a local and remote tree.`RemoteFun` is used to
access the buckets and segments of nodes in the remote
tree. `HandlerFun` will be called for each difference found in the
tree. A difference is either a missing local or remote prefix, or a
list of key differences, which themselves signify different or
missing keys. `HandlerAcc` is passed to the first call of
`HandlerFun` and each subsequent call is passed the value returned
by the previous call. The return value of this function is the
return value from the last call to `HandlerFun`.

<a name="destroy-1"></a>

### destroy/1 ###

<pre><code>
destroy(Tree::<a href="#type-tree">tree()</a>) -&gt; ok
</code></pre>
<br />

Destroys the tree cleaning up any used resources.
This deletes the LevelDB files for the nodes.

<a name="get_bucket-4"></a>

### get_bucket/4 ###

<pre><code>
get_bucket(Prefixes::<a href="#type-tree_node">tree_node()</a>, Level::integer(), Bucket::integer(), Tree::<a href="#type-tree">tree()</a>) -&gt; <a href="orddict.md#type-orddict">orddict:orddict()</a>
</code></pre>
<br />

Returns the [`hashtree`](hashtree.md) buckets for a given node in the
tree. This is used primarily for accessing buckets of a remote tree
during compare.

<a name="insert-4"></a>

### insert/4 ###

<pre><code>
insert(Prefixes::<a href="#type-prefixes">prefixes()</a>, Key::binary(), Hash::binary(), Tree::<a href="#type-tree">tree()</a>) -&gt; <a href="#type-tree">tree()</a> | {error, term()}
</code></pre>
<br />

an alias for insert(Prefixes, Key, Hash, [], Tree)

<a name="insert-5"></a>

### insert/5 ###

<pre><code>
insert(Prefixes::<a href="#type-prefixes">prefixes()</a>, Key::binary(), Hash::binary(), Opts::<a href="#type-insert_opts">insert_opts()</a>, Tree::<a href="#type-tree">tree()</a>) -&gt; <a href="#type-tree">tree()</a> | {error, term()}
</code></pre>
<br />

Insert a hash into the tree. The length of `Prefixes` must
correspond to the height of the tree -- the value used for
`num_levels` when creating the tree. The hash is inserted into
a leaf of the tree and that leaf is marked as dirty. The tree is not
updated at this time. Future operations on the tree should used the
tree returend by this fucntion.

Insert takes the following options:
* if_missing - if `true` then the hash is only inserted into the tree
if the key is not already present. This is useful for
ensuring writes concurrent with building the tree
take precedence over older values. `false` is the default
value.

<a name="key_hashes-3"></a>

### key_hashes/3 ###

<pre><code>
key_hashes(Prefixes::<a href="#type-tree_node">tree_node()</a>, Segment::integer(), Tree::<a href="#type-tree">tree()</a>) -&gt; [{integer(), <a href="orddict.md#type-orddict">orddict:orddict()</a>}]
</code></pre>
<br />

Returns the [`hashtree`](hashtree.md) segment hashes for a given node
in the tree.  This is used primarily for accessing key hashes of a
remote tree during compare.

<a name="local_compare-2"></a>

### local_compare/2 ###

<pre><code>
local_compare(T1::<a href="#type-tree">tree()</a>, T2::<a href="#type-tree">tree()</a>) -&gt; [<a href="#type-diff">diff()</a>]
</code></pre>
<br />

Compare two local trees. This function is primarily for
local debugging and testing.

<a name="new-2"></a>

### new/2 ###

<pre><code>
new(TreeId::term(), Opts::<a href="#type-new_opts">new_opts()</a>) -&gt; <a href="#type-tree">tree()</a>
</code></pre>
<br />

Creates a new hashtree.

Takes the following options:
* num_levels - the height of the tree excluding leaves. corresponds to the
length of the prefix list passed to [`insert/5`](#insert-5).
* data_dir   - the directory where the LevelDB instances for the nodes will
be stored.

<a name="prefix_hash-2"></a>

### prefix_hash/2 ###

<pre><code>
prefix_hash(Prefixes::<a href="#type-prefixes">prefixes()</a>, Tree::<a href="#type-tree">tree()</a>) -&gt; undefined | binary()
</code></pre>
<br />

Returns the top-hash of the node corresponding to the given
prefix list. The length of the prefix list can be less than or
equal to the height of the tree. If the tree has not been updated
or if the prefix list is not found or invalid, then `undefined` is
returned.  Otherwise the hash value from the most recent update is
returned.

<a name="top_hash-1"></a>

### top_hash/1 ###

<pre><code>
top_hash(Tree::<a href="#type-tree">tree()</a>) -&gt; undefined | binary()
</code></pre>
<br />

Returns the top-hash of the tree. This is the top-hash of the
root node.

<a name="update_perform-1"></a>

### update_perform/1 ###

<pre><code>
update_perform(Tree::<a href="#type-tree">tree()</a>) -&gt; ok
</code></pre>
<br />

Update the tree with a snapshot obtained by [`update_snapshot/1`](#update_snapshot-1). This function may be called by a process other
than the one managing the tree.

<a name="update_snapshot-1"></a>

### update_snapshot/1 ###

<pre><code>
update_snapshot(Tree::<a href="#type-tree">tree()</a>) -&gt; <a href="#type-tree">tree()</a>
</code></pre>
<br />

Snapshot the tree for updating. The return tree should be
updated using [`update_perform/1`](#update_perform-1) and to perform future operations
on the tree

