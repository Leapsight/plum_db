

# Module hashtree #
* [Description](#description)
* [Data Types](#types)
* [Function Index](#index)
* [Function Details](#functions)

This module implements a persistent, on-disk hash tree that is used
predominately for active anti-entropy exchange in Riak.

<a name="description"></a>

## Description ##

The tree consists
of two parts, a set of unbounded on-disk segments and a fixed size hash
tree (that may be on-disk or in-memory) constructed over these segments.

A graphical description of this design can be found in: docs/hashtree.md

Each segment logically represents an on-disk list of (key, hash) pairs.
Whereas the hash tree is represented as a set of levels and buckets, with a
fixed width (or fan-out) between levels that determines how many buckets of
a child level are grouped together and hashed to represent a bucket at the
parent level. Each leaf in the tree corresponds to a hash of one of the
on-disk segments. For example, a tree with a width of 4 and 16 segments
would look like the following:

level   buckets
1:      [0]
2:      [0 1 2 3]
3:      [0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15]

With each bucket entry of the form `{bucket-id, hash}`, eg. `{0,
binary()}`.  The hash for each of the entries at level 3 would come from
one of the 16 segments, while the hashes for entries at level 1 and 2 are
derived from the lower levels.

Specifically, the bucket entries in level 2 would come from level 3:
0: hash([ 0  1  2  3])
1: hash([ 4  5  6  7])
2: hash([ 8  9 10 11])
3: hash([12 13 14 15])

And the bucket entries in level 1 would come from level 2:
1: hash([hash([ 0  1  2  3])
hash([ 4  5  6  7])
hash([ 8  9 10 11])
hash([12 13 14 15])])

When a (key, hash) pair is added to the tree, the key is hashed to
determine which segment it belongs to and inserted/upserted into the
segment. Rather than update the hash tree on every insert, a dirty bit is
set to note that a given segment has changed. The hashes are then updated
in bulk before performing a tree exchange

To update the hash tree, the code iterates over each dirty segment,
building a list of (key, hash) pairs. A hash is computed over this list,
and the leaf node in the hash tree corresponding to the given segment is
updated.  After iterating over all dirty segments, and thus updating all
leaf nodes, the update then continues to update the tree bottom-up,
updating only paths that have changed. As designed, the update requires a
single sparse scan over the on-disk segments and a minimal traversal up the
hash tree.

The heavy-lifting of this module is provided by LevelDB. What is logically
viewed as sorted on-disk segments is in reality a range of on-disk
(segment, key, hash) values written to LevelDB. Each insert of a (key,
hash) pair therefore corresponds to a single LevelDB write (no read
necessary). Likewise, the update operation is performed using LevelDB
iterators.

When used for active anti-entropy in Riak, the hash tree is built once and
then updated in real-time as writes occur. A key design goal is to ensure
that adding (key, hash) pairs to the tree is non-blocking, even during a
tree update or a tree exchange. This is accomplished using LevelDB
snapshots. Inserts into the tree always write directly to the active
LevelDB instance, however updates and exchanges operate over a snapshot of
the tree.

In order to improve performance, writes are buffered in memory and sent
to LevelDB using a single batch write. Writes are flushed whenever the
buffer becomes full, as well as before updating the hashtree.

Tree exchange is provided by the `compare/4` function.
The behavior of this function is determined through a provided function
that implements logic to get buckets and segments for a given remote tree,
as well as a callback invoked as key differences are determined. This
generic interface allows for tree exchange to be implemented in a variety
of ways, including directly against to local hash tree instances, over
distributed Erlang, or over a custom protocol over a TCP socket. See
`local_compare/2` and `do_remote/1` for examples (-ifdef(TEST) only).
<a name="types"></a>

## Data Types ##




### <a name="type-acc_fun">acc_fun()</a> ###


<pre><code>
acc_fun(Acc) = fun(([<a href="#type-keydiff">keydiff()</a>], Acc) -&gt; Acc)
</code></pre>




### <a name="type-hashtree">hashtree()</a> ###


__abstract datatype__: `hashtree()`




### <a name="type-index">index()</a> ###


<pre><code>
index() = non_neg_integer()
</code></pre>




### <a name="type-keydiff">keydiff()</a> ###


<pre><code>
keydiff() = {missing | remote_missing | different, binary()}
</code></pre>




### <a name="type-orddict">orddict()</a> ###


<pre><code>
orddict() = <a href="orddict.md#type-orddict">orddict:orddict()</a>
</code></pre>




### <a name="type-proplist">proplist()</a> ###


<pre><code>
proplist() = <a href="proplists.md#type-proplist">proplists:proplist()</a>
</code></pre>




### <a name="type-remote_fun">remote_fun()</a> ###


<pre><code>
remote_fun() = fun((get_bucket | key_hashes | init | final, {integer(), integer()} | integer() | term()) -&gt; any())
</code></pre>




### <a name="type-tree_id_bin">tree_id_bin()</a> ###


<pre><code>
tree_id_bin() = &lt;&lt;_:176&gt;&gt;
</code></pre>

<a name="index"></a>

## Function Index ##


<table width="100%" border="1" cellspacing="0" cellpadding="2" summary="function index"><tr><td valign="top"><a href="#close-1">close/1</a></td><td></td></tr><tr><td valign="top"><a href="#compare-4">compare/4</a></td><td></td></tr><tr><td valign="top"><a href="#delete-2">delete/2</a></td><td></td></tr><tr><td valign="top"><a href="#destroy-1">destroy/1</a></td><td></td></tr><tr><td valign="top"><a href="#flush_buffer-1">flush_buffer/1</a></td><td></td></tr><tr><td valign="top"><a href="#get_bucket-3">get_bucket/3</a></td><td></td></tr><tr><td valign="top"><a href="#insert-3">insert/3</a></td><td></td></tr><tr><td valign="top"><a href="#insert-4">insert/4</a></td><td></td></tr><tr><td valign="top"><a href="#key_hashes-2">key_hashes/2</a></td><td></td></tr><tr><td valign="top"><a href="#levels-1">levels/1</a></td><td></td></tr><tr><td valign="top"><a href="#mem_levels-1">mem_levels/1</a></td><td></td></tr><tr><td valign="top"><a href="#new-0">new/0</a></td><td></td></tr><tr><td valign="top"><a href="#new-2">new/2</a></td><td></td></tr><tr><td valign="top"><a href="#new-3">new/3</a></td><td></td></tr><tr><td valign="top"><a href="#read_meta-2">read_meta/2</a></td><td></td></tr><tr><td valign="top"><a href="#rehash_tree-1">rehash_tree/1</a></td><td></td></tr><tr><td valign="top"><a href="#segments-1">segments/1</a></td><td></td></tr><tr><td valign="top"><a href="#top_hash-1">top_hash/1</a></td><td></td></tr><tr><td valign="top"><a href="#update_perform-1">update_perform/1</a></td><td></td></tr><tr><td valign="top"><a href="#update_snapshot-1">update_snapshot/1</a></td><td></td></tr><tr><td valign="top"><a href="#update_tree-1">update_tree/1</a></td><td></td></tr><tr><td valign="top"><a href="#width-1">width/1</a></td><td></td></tr><tr><td valign="top"><a href="#write_meta-3">write_meta/3</a></td><td></td></tr></table>


<a name="functions"></a>

## Function Details ##

<a name="close-1"></a>

### close/1 ###

<pre><code>
close(State::<a href="#type-hashtree">hashtree()</a>) -&gt; <a href="#type-hashtree">hashtree()</a>
</code></pre>
<br />

<a name="compare-4"></a>

### compare/4 ###

`compare(Tree, Remote, AccFun, Acc) -> any()`

<a name="delete-2"></a>

### delete/2 ###

<pre><code>
delete(Key::binary(), State::<a href="#type-hashtree">hashtree()</a>) -&gt; <a href="#type-hashtree">hashtree()</a>
</code></pre>
<br />

<a name="destroy-1"></a>

### destroy/1 ###

<pre><code>
destroy(Path::string() | <a href="#type-hashtree">hashtree()</a>) -&gt; ok | <a href="#type-hashtree">hashtree()</a>
</code></pre>
<br />

<a name="flush_buffer-1"></a>

### flush_buffer/1 ###

`flush_buffer(State) -> any()`

<a name="get_bucket-3"></a>

### get_bucket/3 ###

<pre><code>
get_bucket(Level::integer(), Bucket::integer(), State::<a href="#type-hashtree">hashtree()</a>) -&gt; <a href="#type-orddict">orddict()</a>
</code></pre>
<br />

<a name="insert-3"></a>

### insert/3 ###

<pre><code>
insert(Key::binary(), ObjHash::binary(), State::<a href="#type-hashtree">hashtree()</a>) -&gt; <a href="#type-hashtree">hashtree()</a>
</code></pre>
<br />

<a name="insert-4"></a>

### insert/4 ###

<pre><code>
insert(Key::binary(), ObjHash::binary(), State::<a href="#type-hashtree">hashtree()</a>, Opts::<a href="#type-proplist">proplist()</a>) -&gt; <a href="#type-hashtree">hashtree()</a>
</code></pre>
<br />

<a name="key_hashes-2"></a>

### key_hashes/2 ###

<pre><code>
key_hashes(State::<a href="#type-hashtree">hashtree()</a>, Segment::integer()) -&gt; [{integer(), <a href="#type-orddict">orddict()</a>}]
</code></pre>
<br />

<a name="levels-1"></a>

### levels/1 ###

<pre><code>
levels(State::<a href="#type-hashtree">hashtree()</a>) -&gt; pos_integer()
</code></pre>
<br />

<a name="mem_levels-1"></a>

### mem_levels/1 ###

<pre><code>
mem_levels(State::<a href="#type-hashtree">hashtree()</a>) -&gt; integer()
</code></pre>
<br />

<a name="new-0"></a>

### new/0 ###

<pre><code>
new() -&gt; <a href="#type-hashtree">hashtree()</a> | no_return()
</code></pre>
<br />

<a name="new-2"></a>

### new/2 ###

<pre><code>
new(TreeId::{<a href="#type-index">index()</a>, <a href="#type-tree_id_bin">tree_id_bin()</a> | non_neg_integer()}, Options::<a href="#type-proplist">proplist()</a>) -&gt; <a href="#type-hashtree">hashtree()</a> | no_return()
</code></pre>
<br />

<a name="new-3"></a>

### new/3 ###

<pre><code>
new(X1::{<a href="#type-index">index()</a>, <a href="#type-tree_id_bin">tree_id_bin()</a> | non_neg_integer()}, LinkedStore::<a href="#type-hashtree">hashtree()</a>, Options::<a href="#type-proplist">proplist()</a>) -&gt; <a href="#type-hashtree">hashtree()</a> | no_return()
</code></pre>
<br />

<a name="read_meta-2"></a>

### read_meta/2 ###

<pre><code>
read_meta(Key::binary(), State::<a href="#type-hashtree">hashtree()</a>) -&gt; {ok, binary()} | undefined
</code></pre>
<br />

<a name="rehash_tree-1"></a>

### rehash_tree/1 ###

<pre><code>
rehash_tree(State::<a href="#type-hashtree">hashtree()</a>) -&gt; <a href="#type-hashtree">hashtree()</a>
</code></pre>
<br />

<a name="segments-1"></a>

### segments/1 ###

<pre><code>
segments(State::<a href="#type-hashtree">hashtree()</a>) -&gt; pos_integer()
</code></pre>
<br />

<a name="top_hash-1"></a>

### top_hash/1 ###

<pre><code>
top_hash(State::<a href="#type-hashtree">hashtree()</a>) -&gt; [] | [{0, binary()}]
</code></pre>
<br />

<a name="update_perform-1"></a>

### update_perform/1 ###

<pre><code>
update_perform(State2::<a href="#type-hashtree">hashtree()</a>) -&gt; <a href="#type-hashtree">hashtree()</a>
</code></pre>
<br />

<a name="update_snapshot-1"></a>

### update_snapshot/1 ###

<pre><code>
update_snapshot(State::<a href="#type-hashtree">hashtree()</a>) -&gt; {<a href="#type-hashtree">hashtree()</a>, <a href="#type-hashtree">hashtree()</a>}
</code></pre>
<br />

<a name="update_tree-1"></a>

### update_tree/1 ###

<pre><code>
update_tree(State::<a href="#type-hashtree">hashtree()</a>) -&gt; <a href="#type-hashtree">hashtree()</a>
</code></pre>
<br />

<a name="width-1"></a>

### width/1 ###

<pre><code>
width(State::<a href="#type-hashtree">hashtree()</a>) -&gt; pos_integer()
</code></pre>
<br />

<a name="write_meta-3"></a>

### write_meta/3 ###

<pre><code>
write_meta(Key::binary(), Value::binary(), State::<a href="#type-hashtree">hashtree()</a>) -&gt; <a href="#type-hashtree">hashtree()</a>
</code></pre>
<br />

