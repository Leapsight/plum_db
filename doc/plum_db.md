

# Module plum_db #
* [Data Types](#types)
* [Function Index](#index)
* [Function Details](#functions)

__Behaviours:__ [`gen_server`](gen_server.md), [`plumtree_broadcast_handler`](plumtree_broadcast_handler.md).

<a name="types"></a>

## Data Types ##




### <a name="type-continuation">continuation()</a> ###


__abstract datatype__: `continuation()`




### <a name="type-delete_opts">delete_opts()</a> ###


<pre><code>
delete_opts() = []
</code></pre>




### <a name="type-fold_elements_fun">fold_elements_fun()</a> ###


<pre><code>
fold_elements_fun() = fun(({<a href="#type-plum_db_key">plum_db_key()</a>, <a href="#type-plum_db_object">plum_db_object()</a>}, any()) -&gt; any())
</code></pre>




### <a name="type-fold_fun">fold_fun()</a> ###


<pre><code>
fold_fun() = fun(({<a href="#type-plum_db_key">plum_db_key()</a>, <a href="#type-value_or_values">value_or_values()</a>}, any()) -&gt; any())
</code></pre>




### <a name="type-fold_opts">fold_opts()</a> ###


<pre><code>
fold_opts() = <a href="#type-it_opts">it_opts()</a>
</code></pre>




### <a name="type-foreach_fun">foreach_fun()</a> ###


<pre><code>
foreach_fun() = fun(({<a href="#type-plum_db_key">plum_db_key()</a>, <a href="#type-value_or_values">value_or_values()</a>}) -&gt; any())
</code></pre>




### <a name="type-get_opt">get_opt()</a> ###


<pre><code>
get_opt() = <a href="#type-get_opt_default_val">get_opt_default_val()</a> | <a href="#type-get_opt_resolver">get_opt_resolver()</a> | <a href="#type-get_opt_allow_put">get_opt_allow_put()</a>
</code></pre>




### <a name="type-get_opt_allow_put">get_opt_allow_put()</a> ###


<pre><code>
get_opt_allow_put() = {allow_put, boolean()}
</code></pre>




### <a name="type-get_opt_default_val">get_opt_default_val()</a> ###


<pre><code>
get_opt_default_val() = {default, <a href="#type-plum_db_value">plum_db_value()</a>}
</code></pre>




### <a name="type-get_opt_resolver">get_opt_resolver()</a> ###


<pre><code>
get_opt_resolver() = {resolver, <a href="#type-plum_db_resolver">plum_db_resolver()</a>}
</code></pre>




### <a name="type-get_opts">get_opts()</a> ###


<pre><code>
get_opts() = [<a href="#type-get_opt">get_opt()</a>]
</code></pre>




### <a name="type-it_opt">it_opt()</a> ###


<pre><code>
it_opt() = <a href="#type-it_opt_resolver">it_opt_resolver()</a> | <a href="#type-it_opt_first">it_opt_first()</a> | <a href="#type-it_opt_default">it_opt_default()</a> | <a href="#type-it_opt_keymatch">it_opt_keymatch()</a> | <a href="#type-it_opt_keys_only">it_opt_keys_only()</a> | <a href="#type-it_opt_partitions">it_opt_partitions()</a>
</code></pre>




### <a name="type-it_opt_default">it_opt_default()</a> ###


<pre><code>
it_opt_default() = {default, <a href="#type-plum_db_value">plum_db_value()</a> | <a href="#type-it_opt_default_fun">it_opt_default_fun()</a>}
</code></pre>




### <a name="type-it_opt_default_fun">it_opt_default_fun()</a> ###


<pre><code>
it_opt_default_fun() = fun((<a href="#type-plum_db_key">plum_db_key()</a>) -&gt; <a href="#type-plum_db_value">plum_db_value()</a>)
</code></pre>




### <a name="type-it_opt_first">it_opt_first()</a> ###


<pre><code>
it_opt_first() = {first, term()}
</code></pre>




### <a name="type-it_opt_keymatch">it_opt_keymatch()</a> ###


<pre><code>
it_opt_keymatch() = {match, term()}
</code></pre>




### <a name="type-it_opt_keys_only">it_opt_keys_only()</a> ###


<pre><code>
it_opt_keys_only() = {keys_only, boolean()}
</code></pre>




### <a name="type-it_opt_partitions">it_opt_partitions()</a> ###


<pre><code>
it_opt_partitions() = {partitions, [<a href="#type-partition">partition()</a>]}
</code></pre>




### <a name="type-it_opt_resolver">it_opt_resolver()</a> ###


<pre><code>
it_opt_resolver() = {resolver, <a href="#type-plum_db_resolver">plum_db_resolver()</a> | lww}
</code></pre>




### <a name="type-it_opts">it_opts()</a> ###


<pre><code>
it_opts() = [<a href="#type-it_opt">it_opt()</a>]
</code></pre>




### <a name="type-iterator">iterator()</a> ###


__abstract datatype__: `iterator()`




### <a name="type-iterator_element">iterator_element()</a> ###


<pre><code>
iterator_element() = {<a href="#type-plum_db_pkey">plum_db_pkey()</a>, <a href="#type-plum_db_object">plum_db_object()</a>}
</code></pre>




### <a name="type-match_opt_limit">match_opt_limit()</a> ###


<pre><code>
match_opt_limit() = pos_integer() | infinity
</code></pre>




### <a name="type-match_opt_remove_tombstones">match_opt_remove_tombstones()</a> ###


<pre><code>
match_opt_remove_tombstones() = boolean()
</code></pre>




### <a name="type-match_opts">match_opts()</a> ###


<pre><code>
match_opts() = [<a href="#type-it_opt">it_opt()</a> | <a href="#type-match_opt_limit">match_opt_limit()</a> | <a href="#type-match_opt_remove_tombstones">match_opt_remove_tombstones()</a>]
</code></pre>




### <a name="type-partition">partition()</a> ###


<pre><code>
partition() = non_neg_integer()
</code></pre>




### <a name="type-plum_db_broadcast">plum_db_broadcast()</a> ###


<pre><code>
plum_db_broadcast() = #plum_db_broadcast{pkey = <a href="#type-plum_db_pkey">plum_db_pkey()</a>, obj = <a href="#type-plum_db_object">plum_db_object()</a>}
</code></pre>




### <a name="type-plum_db_context">plum_db_context()</a> ###


<pre><code>
plum_db_context() = <a href="dvvset.md#type-vector">dvvset:vector()</a>
</code></pre>




### <a name="type-plum_db_key">plum_db_key()</a> ###


<pre><code>
plum_db_key() = any()
</code></pre>




### <a name="type-plum_db_modifier">plum_db_modifier()</a> ###


<pre><code>
plum_db_modifier() = fun(([<a href="#type-plum_db_value">plum_db_value()</a> | <a href="#type-plum_db_tombstone">plum_db_tombstone()</a>] | undefined) -&gt; <a href="#type-plum_db_value">plum_db_value()</a>)
</code></pre>




### <a name="type-plum_db_object">plum_db_object()</a> ###


<pre><code>
plum_db_object() = {object, <a href="dvvset.md#type-clock">dvvset:clock()</a>}
</code></pre>




### <a name="type-plum_db_pkey">plum_db_pkey()</a> ###


<pre><code>
plum_db_pkey() = {<a href="#type-plum_db_prefix">plum_db_prefix()</a>, <a href="#type-plum_db_key">plum_db_key()</a>}
</code></pre>




### <a name="type-plum_db_pkey_pattern">plum_db_pkey_pattern()</a> ###


<pre><code>
plum_db_pkey_pattern() = {<a href="#type-plum_db_prefix_pattern">plum_db_prefix_pattern()</a>, <a href="#type-plum_db_key">plum_db_key()</a> | <a href="#type-plum_db_wildcard">plum_db_wildcard()</a>}
</code></pre>




### <a name="type-plum_db_prefix">plum_db_prefix()</a> ###


<pre><code>
plum_db_prefix() = {binary() | atom(), binary() | atom()}
</code></pre>




### <a name="type-plum_db_prefix_pattern">plum_db_prefix_pattern()</a> ###


<pre><code>
plum_db_prefix_pattern() = {binary() | atom() | <a href="#type-plum_db_wildcard">plum_db_wildcard()</a>, binary() | atom() | <a href="#type-plum_db_wildcard">plum_db_wildcard()</a>}
</code></pre>




### <a name="type-plum_db_resolver">plum_db_resolver()</a> ###


<pre><code>
plum_db_resolver() = fun((<a href="#type-plum_db_key">plum_db_key()</a> | <a href="#type-plum_db_pkey">plum_db_pkey()</a>, <a href="#type-plum_db_value">plum_db_value()</a> | <a href="#type-plum_db_tombstone">plum_db_tombstone()</a>) -&gt; <a href="#type-plum_db_value">plum_db_value()</a>)
</code></pre>




### <a name="type-plum_db_tombstone">plum_db_tombstone()</a> ###


<pre><code>
plum_db_tombstone() = $deleted
</code></pre>




### <a name="type-plum_db_value">plum_db_value()</a> ###


<pre><code>
plum_db_value() = any()
</code></pre>




### <a name="type-plum_db_wildcard">plum_db_wildcard()</a> ###


<pre><code>
plum_db_wildcard() = _
</code></pre>




### <a name="type-prefix_type">prefix_type()</a> ###


<pre><code>
prefix_type() = ram | ram_disk | disk
</code></pre>




### <a name="type-prefixes">prefixes()</a> ###


<pre><code>
prefixes() = #{binary() | atom() =&gt; <a href="#type-prefix_type">prefix_type()</a>}
</code></pre>




### <a name="type-put_opts">put_opts()</a> ###


<pre><code>
put_opts() = []
</code></pre>




### <a name="type-remote_iterator">remote_iterator()</a> ###


<pre><code>
remote_iterator() = #remote_iterator{node = node(), ref = reference(), match_prefix = <a href="#type-plum_db_prefix">plum_db_prefix()</a> | atom() | binary()}
</code></pre>




### <a name="type-value_or_values">value_or_values()</a> ###


<pre><code>
value_or_values() = [<a href="#type-plum_db_value">plum_db_value()</a> | <a href="#type-plum_db_tombstone">plum_db_tombstone()</a>] | <a href="#type-plum_db_value">plum_db_value()</a> | <a href="#type-plum_db_tombstone">plum_db_tombstone()</a>
</code></pre>

<a name="index"></a>

## Function Index ##


<table width="100%" border="1" cellspacing="0" cellpadding="2" summary="function index"><tr><td valign="top"><a href="#broadcast_data-1">broadcast_data/1</a></td><td>Deconstructs a broadcast that is sent using
<code>broadcast/2</code> as the handling module returning the message id
and payload.</td></tr><tr><td valign="top"><a href="#delete-2">delete/2</a></td><td>Same as delete(FullPrefix, Key, []).</td></tr><tr><td valign="top"><a href="#delete-3">delete/3</a></td><td>Logically deletes the value associated with the given prefix
and key locally and then triggers a broradcast to notify other nodes in the
cluster.</td></tr><tr><td valign="top"><a href="#exchange-1">exchange/1</a></td><td>Triggers an asynchronous exchange.</td></tr><tr><td valign="top"><a href="#exchange-2">exchange/2</a></td><td>Triggers an asynchronous exchange.</td></tr><tr><td valign="top"><a href="#fold-3">fold/3</a></td><td>Same as fold(Fun, Acc0, FullPrefix, []).</td></tr><tr><td valign="top"><a href="#fold-4">fold/4</a></td><td>Fold over all keys and values stored under a given prefix/subprefix.</td></tr><tr><td valign="top"><a href="#fold_elements-3">fold_elements/3</a></td><td>Same as fold_elements(Fun, Acc0, FullPrefix, []).</td></tr><tr><td valign="top"><a href="#fold_elements-4">fold_elements/4</a></td><td>Fold over all elements stored under a given prefix/subprefix.</td></tr><tr><td valign="top"><a href="#foreach-2">foreach/2</a></td><td>Same as fold(Fun, Acc0, FullPrefix, []).</td></tr><tr><td valign="top"><a href="#foreach-3">foreach/3</a></td><td>Fold over all keys and values stored under a given prefix/subprefix.</td></tr><tr><td valign="top"><a href="#get-2">get/2</a></td><td>Same as get(FullPrefix, Key, []).</td></tr><tr><td valign="top"><a href="#get-3">get/3</a></td><td>Retrieves the local value stored at the given fullprefix <code>FullPrefix</code>
and key <code>Key</code> using options <code>Opts</code>.</td></tr><tr><td valign="top"><a href="#get_object-1">get_object/1</a></td><td>Returns a Dotted Version Vector Set or undefined.</td></tr><tr><td valign="top"><a href="#get_object-2">get_object/2</a></td><td>Same as get/1 but reads the value from <code>Node</code>
This is function is used by plum_db_exchange_statem.</td></tr><tr><td valign="top"><a href="#graft-1">graft/1</a></td><td>Returns the object associated with the given prefixed key <code>Pkey</code> and
context <code>Context</code> (message id) if the currently stored version has an equal
context.</td></tr><tr><td valign="top"><a href="#is_partition-1">is_partition/1</a></td><td>Returns true if an identifier is a valid partition.</td></tr><tr><td valign="top"><a href="#is_stale-1">is_stale/1</a></td><td>Returns false if the update (or a causally newer update) has already
been received (stored locally).</td></tr><tr><td valign="top"><a href="#iterate-1">iterate/1</a></td><td>Advances the iterator by one key, full-prefix or sub-prefix.</td></tr><tr><td valign="top"><a href="#iterator-0">iterator/0</a></td><td>Returns a full-prefix iterator: an iterator for all full-prefixes that
have keys stored under them.</td></tr><tr><td valign="top"><a href="#iterator-1">iterator/1</a></td><td>Same as calling <code>iterator(FullPrefix, [])</code>.</td></tr><tr><td valign="top"><a href="#iterator-2">iterator/2</a></td><td>Return an iterator pointing to the first key stored under a prefix.</td></tr><tr><td valign="top"><a href="#iterator_close-1">iterator_close/1</a></td><td>Closes the iterator.</td></tr><tr><td valign="top"><a href="#iterator_default-1">iterator_default/1</a></td><td>Returns the value returned when an iterator points to a tombstone.</td></tr><tr><td valign="top"><a href="#iterator_done-1">iterator_done/1</a></td><td>Returns true if there is nothing more to iterate over.</td></tr><tr><td valign="top"><a href="#iterator_element-1">iterator_element/1</a></td><td></td></tr><tr><td valign="top"><a href="#iterator_key-1">iterator_key/1</a></td><td>Return the key pointed at by the iterator.</td></tr><tr><td valign="top"><a href="#iterator_key_value-1">iterator_key_value/1</a></td><td>Returns a single value pointed at by the iterator.</td></tr><tr><td valign="top"><a href="#iterator_key_values-1">iterator_key_values/1</a></td><td>Return the key and all sibling values pointed at by the iterator.</td></tr><tr><td valign="top"><a href="#iterator_prefix-1">iterator_prefix/1</a></td><td>Returns the full-prefix being iterated by this iterator.</td></tr><tr><td valign="top"><a href="#match-1">match/1</a></td><td></td></tr><tr><td valign="top"><a href="#match-2">match/2</a></td><td></td></tr><tr><td valign="top"><a href="#match-3">match/3</a></td><td></td></tr><tr><td valign="top"><a href="#merge-2">merge/2</a></td><td>Merges a remote copy of an object record sent via broadcast w/ the
local view for the key contained in the message id.</td></tr><tr><td valign="top"><a href="#merge-3">merge/3</a></td><td>Same as merge/2 but merges the object on <code>Node</code></td></tr><tr><td valign="top"><a href="#partition_count-0">partition_count/0</a></td><td>Returns the number of partitions.</td></tr><tr><td valign="top"><a href="#partitions-0">partitions/0</a></td><td>Returns the list of the partition identifiers starting at 0.</td></tr><tr><td valign="top"><a href="#prefix_hash-2">prefix_hash/2</a></td><td>Return the local hash associated with a full-prefix or prefix.</td></tr><tr><td valign="top"><a href="#prefix_type-1">prefix_type/1</a></td><td></td></tr><tr><td valign="top"><a href="#prefixes-0">prefixes/0</a></td><td>Returns a mapping of prefixes (the first element of a plum_db_prefix()
tuple) to prefix_type() only for those prefixes for which a type was
declared using the application optiont <code>prefixes</code>.</td></tr><tr><td valign="top"><a href="#put-3">put/3</a></td><td>Same as put(FullPrefix, Key, Value, []).</td></tr><tr><td valign="top"><a href="#put-4">put/4</a></td><td>Stores or updates the value at the given prefix and key locally and then
triggers a broadcast to notify other nodes in the cluster.</td></tr><tr><td valign="top"><a href="#remote_iterator-1">remote_iterator/1</a></td><td>Create an iterator on <code>Node</code>.</td></tr><tr><td valign="top"><a href="#remote_iterator-2">remote_iterator/2</a></td><td></td></tr><tr><td valign="top"><a href="#start_link-0">start_link/0</a></td><td>Start the plum_db server and link to calling process.</td></tr><tr><td valign="top"><a href="#sync_exchange-1">sync_exchange/1</a></td><td>Triggers a synchronous exchange.</td></tr><tr><td valign="top"><a href="#sync_exchange-2">sync_exchange/2</a></td><td>Triggers a synchronous exchange.</td></tr><tr><td valign="top"><a href="#take-2">take/2</a></td><td></td></tr><tr><td valign="top"><a href="#take-3">take/3</a></td><td></td></tr><tr><td valign="top"><a href="#to_list-1">to_list/1</a></td><td>Same as to_list(FullPrefix, []).</td></tr><tr><td valign="top"><a href="#to_list-2">to_list/2</a></td><td>Return a list of all keys and values stored under a given
prefix/subprefix.</td></tr></table>


<a name="functions"></a>

## Function Details ##

<a name="broadcast_data-1"></a>

### broadcast_data/1 ###

<pre><code>
broadcast_data(Plum_db_broadcast::<a href="#type-plum_db_broadcast">plum_db_broadcast()</a>) -&gt; {{<a href="#type-plum_db_pkey">plum_db_pkey()</a>, <a href="#type-plum_db_context">plum_db_context()</a>}, <a href="#type-plum_db_object">plum_db_object()</a>}
</code></pre>
<br />

Deconstructs a broadcast that is sent using
`broadcast/2` as the handling module returning the message id
and payload.

> This function is part of the implementation of the
plumtree_broadcast_handler behaviour.
> You should never call it directly.

<a name="delete-2"></a>

### delete/2 ###

<pre><code>
delete(FullPrefix::<a href="#type-plum_db_prefix">plum_db_prefix()</a>, Key::<a href="#type-plum_db_key">plum_db_key()</a>) -&gt; ok
</code></pre>
<br />

Same as delete(FullPrefix, Key, [])

<a name="delete-3"></a>

### delete/3 ###

<pre><code>
delete(FullPrefix::<a href="#type-plum_db_prefix">plum_db_prefix()</a>, Key::<a href="#type-plum_db_key">plum_db_key()</a>, Opts::<a href="#type-delete_opts">delete_opts()</a>) -&gt; ok
</code></pre>
<br />

Logically deletes the value associated with the given prefix
and key locally and then triggers a broradcast to notify other nodes in the
cluster. Currently there are no delete options.

NOTE: currently deletion is logical and no GC is performed.

<a name="exchange-1"></a>

### exchange/1 ###

<pre><code>
exchange(Peer::node()) -&gt; {ok, pid()} | {error, term()}
</code></pre>
<br />

Triggers an asynchronous exchange.
Calls [`exchange/2`](#exchange-2) with an empty map as the second argument.
> The exchange is only triggered if the application option `aae_enabled` is
set to `true`.

<a name="exchange-2"></a>

### exchange/2 ###

<pre><code>
exchange(Peer::node(), Opts::map()) -&gt; {ok, pid()} | {error, term()}
</code></pre>
<br />

Triggers an asynchronous exchange.
The exchange is performed asynchronously by spawning a supervised process. Read the [`plum_db_exchanges_sup`](plum_db_exchanges_sup.md) documentation.

`Opts` is a map accepting the following options:

* `timeout` (milliseconds) –– timeout for the AAE exchange to conclude.

> The exchange is only triggered if the application option `aae_enabled` is
set to `true`.

<a name="fold-3"></a>

### fold/3 ###

<pre><code>
fold(Fun::<a href="#type-fold_fun">fold_fun()</a>, Acc0::any(), FullPrefixPattern::<a href="#type-plum_db_prefix_pattern">plum_db_prefix_pattern()</a>) -&gt; any()
</code></pre>
<br />

Same as fold(Fun, Acc0, FullPrefix, []).

<a name="fold-4"></a>

### fold/4 ###

<pre><code>
fold(Fun::<a href="#type-fold_fun">fold_fun()</a>, Acc0::any(), FullPrefixPattern::<a href="#type-plum_db_prefix_pattern">plum_db_prefix_pattern()</a>, Opts::<a href="#type-fold_opts">fold_opts()</a>) -&gt; any()
</code></pre>
<br />

Fold over all keys and values stored under a given prefix/subprefix.
Available options are the same as those provided to iterator/2. To return
early, throw {break, Result} in your fold function.

<a name="fold_elements-3"></a>

### fold_elements/3 ###

<pre><code>
fold_elements(Fun::<a href="#type-fold_elements_fun">fold_elements_fun()</a>, Acc0::any(), FullPrefix::<a href="#type-plum_db_prefix">plum_db_prefix()</a>) -&gt; any()
</code></pre>
<br />

Same as fold_elements(Fun, Acc0, FullPrefix, []).

<a name="fold_elements-4"></a>

### fold_elements/4 ###

<pre><code>
fold_elements(Fun::<a href="#type-fold_elements_fun">fold_elements_fun()</a>, Acc0::any(), FullPrefix::<a href="#type-plum_db_prefix">plum_db_prefix()</a>, Opts::<a href="#type-fold_opts">fold_opts()</a>) -&gt; any()
</code></pre>
<br />

Fold over all elements stored under a given prefix/subprefix.
Available options are the same as those provided to iterator/2. To return
early, throw {break, Result} in your fold function.

<a name="foreach-2"></a>

### foreach/2 ###

<pre><code>
foreach(Fun::<a href="#type-foreach_fun">foreach_fun()</a>, FullPrefixPattern::<a href="#type-plum_db_prefix_pattern">plum_db_prefix_pattern()</a>) -&gt; any()
</code></pre>
<br />

Same as fold(Fun, Acc0, FullPrefix, []).

<a name="foreach-3"></a>

### foreach/3 ###

<pre><code>
foreach(Fun::<a href="#type-foreach_fun">foreach_fun()</a>, FullPrefixPattern::<a href="#type-plum_db_prefix_pattern">plum_db_prefix_pattern()</a>, Opts::<a href="#type-fold_opts">fold_opts()</a>) -&gt; any()
</code></pre>
<br />

Fold over all keys and values stored under a given prefix/subprefix.
Available options are the same as those provided to iterator/2. To return
early, throw {break, Result} in your fold function.

<a name="get-2"></a>

### get/2 ###

<pre><code>
get(FullPrefix::<a href="#type-plum_db_prefix">plum_db_prefix()</a>, Key::<a href="#type-plum_db_key">plum_db_key()</a>) -&gt; <a href="#type-plum_db_value">plum_db_value()</a> | undefined
</code></pre>
<br />

Same as get(FullPrefix, Key, [])

<a name="get-3"></a>

### get/3 ###

<pre><code>
get(FullPrefix::<a href="#type-plum_db_prefix">plum_db_prefix()</a>, Key::<a href="#type-plum_db_key">plum_db_key()</a>, Opts::<a href="#type-get_opts">get_opts()</a>) -&gt; <a href="#type-plum_db_value">plum_db_value()</a> | undefined
</code></pre>
<br />

Retrieves the local value stored at the given fullprefix `FullPrefix`
and key `Key` using options `Opts`.

Returns the stored value if found. If no value is found and `Opts` contains
a value for the key `default`, this value is returned.
Otherwise returns the atom `undefined`.

`Opts` is a property list that can take the following options:

* `default` – value to return if no value is found, Defaults to `undefined`.
* `resolver` – The atom `lww` or a `plum_db_resolver()` that resolves
conflicts if they are encountered. Defaults to `lww` (last-write-wins).
* `allow_put` – whether or not to write and broadcast a resolved value.
Defaults to `true`.

Example: Simple get

```
  > plum_db:get({foo, a}, x).
  undefined.
  > plum_db:get({foo, a}, x, [{default, 1}]).
  1.
  > plum_db:put({foo, a}, x, 100).
  ok
  > plum_db:get({foo, a}, x).
  100.
```

Example: Resolving with a custom function

```
  Fun = fun(A, B) when A > B -> A; _ -> B end,
  > plum_db:get({foo, a}, x, [{resolver, Fun}]).
```

> NOTE: an update will be broadcasted if conflicts are resolved and
`allow_put` is `true`. However, any further conflicts generated by
concurrent writes during resolution are not resolved.

<a name="get_object-1"></a>

### get_object/1 ###

`get_object(PKey) -> any()`

Returns a Dotted Version Vector Set or undefined.
When reading the value for a subsequent call to put/3 the
context can be obtained using plum_db_object:context/1. Values can
obtained w/ plum_db_object:values/1.

<a name="get_object-2"></a>

### get_object/2 ###

<pre><code>
get_object(Node::node(), PKey::<a href="#type-plum_db_pkey">plum_db_pkey()</a>) -&gt; <a href="#type-plum_db_object">plum_db_object()</a> | undefined
</code></pre>
<br />

Same as get/1 but reads the value from `Node`
This is function is used by plum_db_exchange_statem.

<a name="graft-1"></a>

### graft/1 ###

<pre><code>
graft(X1::{<a href="#type-plum_db_pkey">plum_db_pkey()</a>, <a href="#type-plum_db_context">plum_db_context()</a>}) -&gt; stale | {ok, <a href="#type-plum_db_object">plum_db_object()</a>} | {error, term()}
</code></pre>
<br />

Returns the object associated with the given prefixed key `Pkey` and
context `Context` (message id) if the currently stored version has an equal
context. Otherwise returns the atom `stale`.

Because it assumes that a grafted context can only be causally older than
the local view, a `stale` response means there is another message that
subsumes the grafted one.

> This function is part of the implementation of the
plumtree_broadcast_handler behaviour.
> You should never call it directly.

<a name="is_partition-1"></a>

### is_partition/1 ###

<pre><code>
is_partition(Id::<a href="#type-partition">partition()</a>) -&gt; boolean()
</code></pre>
<br />

Returns true if an identifier is a valid partition.

<a name="is_stale-1"></a>

### is_stale/1 ###

<pre><code>
is_stale(X1::{<a href="#type-plum_db_pkey">plum_db_pkey()</a>, <a href="#type-plum_db_context">plum_db_context()</a>}) -&gt; boolean()
</code></pre>
<br />

Returns false if the update (or a causally newer update) has already
been received (stored locally).

> This function is part of the implementation of the
plumtree_broadcast_handler behaviour.
> You should never call it directly.

<a name="iterate-1"></a>

### iterate/1 ###

<pre><code>
iterate(Remote_iterator::<a href="#type-iterator">iterator()</a> | <a href="#type-remote_iterator">remote_iterator()</a>) -&gt; <a href="#type-iterator">iterator()</a> | <a href="#type-remote_iterator">remote_iterator()</a>
</code></pre>
<br />

Advances the iterator by one key, full-prefix or sub-prefix

<a name="iterator-0"></a>

### iterator/0 ###

<pre><code>
iterator() -&gt; <a href="#type-iterator">iterator()</a>
</code></pre>
<br />

Returns a full-prefix iterator: an iterator for all full-prefixes that
have keys stored under them.
When done with the iterator, iterator_close/1 must be called.
This iterator works across all existing store partitions, treating the set
of partitions as a single logical database. As a result, ordering is partial
per partition and not global across them.

Same as calling `iterator({undefined, undefined})`.

<a name="iterator-1"></a>

### iterator/1 ###

<pre><code>
iterator(FullPrefix::<a href="#type-plum_db_prefix">plum_db_prefix()</a>) -&gt; <a href="#type-iterator">iterator()</a>
</code></pre>
<br />

Same as calling `iterator(FullPrefix, [])`.

<a name="iterator-2"></a>

### iterator/2 ###

<pre><code>
iterator(FullPrefix::<a href="#type-plum_db_prefix_pattern">plum_db_prefix_pattern()</a>, Opts::<a href="#type-it_opts">it_opts()</a>) -&gt; <a href="#type-iterator">iterator()</a>
</code></pre>
<br />

Return an iterator pointing to the first key stored under a prefix

This function can take the following options:

* `resolver`: either the atom `lww` or a function that resolves conflicts if
they are encounted (see get/3 for more details). Conflict resolution is
performed when values are retrieved (see iterator_key_value/1 and iterator_key_values/1).
If no resolver is provided no resolution is performed. The default is to not
provide a resolver.
* `allow_put`: whether or not to write and broadcast a resolved value.
defaults to `true`.
* `default`: Used when the value an iterator points to is a tombstone. default
is either an arity-1 function or a value. If a function, the key the
iterator points to is passed as the argument and the result is returned in
place of the tombstone. If default is a value, the value is returned in
place of the tombstone. This applies when using functions such as
iterator_key_values/1 and iterator_key_values/1.
* `first` - the key this iterator should start at, equivalent to calling
iterator_move/2 passing the key as the second argument.
* `match`: If match is undefined then all keys will may be visted by the
iterator, match can be:
* an erlang term - which will be matched exactly against a key
* '_' - the wilcard term which matches anything
* an erlang tuple containing terms and '_' - if tuples are used as keys
this can be used to iterate over some subset of keys
* `partitions`: The list of partitions this iterator should cover. If
undefined it will cover all partitions (`pdb:partitions/0`)
* `keys_only`: wether to iterate only on keys (default: false)

<a name="iterator_close-1"></a>

### iterator_close/1 ###

<pre><code>
iterator_close(Remote_iterator::<a href="#type-iterator">iterator()</a> | <a href="#type-iterator">iterator()</a> | <a href="#type-remote_iterator">remote_iterator()</a>) -&gt; ok
</code></pre>
<br />

Closes the iterator. This function must be called on all open iterators

<a name="iterator_default-1"></a>

### iterator_default/1 ###

<pre><code>
iterator_default(Iterator::<a href="#type-iterator">iterator()</a> | <a href="#type-iterator">iterator()</a>) -&gt; <a href="#type-plum_db_tombstone">plum_db_tombstone()</a> | <a href="#type-plum_db_value">plum_db_value()</a> | <a href="#type-it_opt_default_fun">it_opt_default_fun()</a>
</code></pre>
<br />

Returns the value returned when an iterator points to a tombstone. If
the default used when creating the given iterator is a function it will be
applied to the current key the iterator points at. If no default was
provided the tombstone value was returned.
This function should only be called after checking iterator_done/1.

<a name="iterator_done-1"></a>

### iterator_done/1 ###

<pre><code>
iterator_done(Remote_iterator::<a href="#type-iterator">iterator()</a> | <a href="#type-iterator">iterator()</a> | <a href="#type-remote_iterator">remote_iterator()</a>) -&gt; boolean()
</code></pre>
<br />

Returns true if there is nothing more to iterate over

<a name="iterator_element-1"></a>

### iterator_element/1 ###

<pre><code>
iterator_element(Remote_iterator::<a href="#type-iterator">iterator()</a> | <a href="#type-iterator">iterator()</a> | <a href="#type-remote_iterator">remote_iterator()</a>) -&gt; <a href="#type-iterator_element">iterator_element()</a>
</code></pre>
<br />

<a name="iterator_key-1"></a>

### iterator_key/1 ###

<pre><code>
iterator_key(Iterator::<a href="#type-iterator">iterator()</a>) -&gt; <a href="#type-plum_db_key">plum_db_key()</a> | undefined
</code></pre>
<br />

Return the key pointed at by the iterator. Before calling this function,
check the iterator is not complete w/ iterator_done/1. No conflict resolution
will be performed as a result of calling this function.

<a name="iterator_key_value-1"></a>

### iterator_key_value/1 ###

<pre><code>
iterator_key_value(Iterator::<a href="#type-iterator">iterator()</a> | <a href="#type-remote_iterator">remote_iterator()</a> | <a href="#type-iterator">iterator()</a>) -&gt; {<a href="#type-plum_db_key">plum_db_key()</a>, <a href="#type-plum_db_value">plum_db_value()</a>} | {error, conflict}
</code></pre>
<br />

Returns a single value pointed at by the iterator.
If there are conflicts and a resolver was
specified in the options when creating this iterator, they will be resolved.
Otherwise, and error is returned.
If conflicts are resolved, the resolved value is written locally and a
broadcast is performed to update other nodes
in the cluster if `allow_put` is `true` (the default value). If `allow_put`
is `false`, values are resolved but not written or broadcast.

NOTE: if resolution may be performed this function must be called at most
once before calling iterate/1 on the iterator (at which point the function
can be called once more).

<a name="iterator_key_values-1"></a>

### iterator_key_values/1 ###

<pre><code>
iterator_key_values(Iterator::<a href="#type-iterator">iterator()</a>) -&gt; {<a href="#type-plum_db_key">plum_db_key()</a>, <a href="#type-value_or_values">value_or_values()</a>}
</code></pre>
<br />

Return the key and all sibling values pointed at by the iterator.
Before calling this function, check the iterator is not complete w/
iterator_done/1.
If a resolver was passed to iterator/0 when creating the given iterator,
siblings will be resolved using the given function or last-write-wins (if
`lww` is passed as the resolver). If no resolver was used then no conflict
resolution will take place.
If conflicts are resolved, the resolved value is written to
local store and a broadcast is submitted to update other nodes in the
cluster if `allow_put` is `true`. If `allow_put` is `false` the values are
resolved but are not written or broadcast. A single value is returned as the
second element of the tuple in the case values are resolved. If no
resolution takes place then a list of values will be returned as the second
element (even if there is only a single sibling).

NOTE: if resolution may be performed this function must be called at most
once before calling iterate/1 on the iterator (at which point the function
can be called once more).

<a name="iterator_prefix-1"></a>

### iterator_prefix/1 ###

<pre><code>
iterator_prefix(Remote_iterator::<a href="#type-iterator">iterator()</a> | <a href="#type-remote_iterator">remote_iterator()</a>) -&gt; <a href="#type-plum_db_prefix">plum_db_prefix()</a>
</code></pre>
<br />

Returns the full-prefix being iterated by this iterator.

<a name="match-1"></a>

### match/1 ###

<pre><code>
match(Continuation::<a href="#type-continuation">continuation()</a>) -&gt; {[{<a href="#type-plum_db_key">plum_db_key()</a>, <a href="#type-value_or_values">value_or_values()</a>}], <a href="#type-continuation">continuation()</a>} | $end_of_table
</code></pre>
<br />

<a name="match-2"></a>

### match/2 ###

<pre><code>
match(FullPrefix::<a href="#type-plum_db_prefix_pattern">plum_db_prefix_pattern()</a>, KeyPattern::<a href="#type-plum_db_pkey_pattern">plum_db_pkey_pattern()</a>) -&gt; [{<a href="#type-plum_db_key">plum_db_key()</a>, <a href="#type-value_or_values">value_or_values()</a>}]
</code></pre>
<br />

<a name="match-3"></a>

### match/3 ###

<pre><code>
match(FullPrefix0::<a href="#type-plum_db_prefix_pattern">plum_db_prefix_pattern()</a>, KeyPattern::<a href="#type-plum_db_pkey_pattern">plum_db_pkey_pattern()</a>, Opts0::<a href="#type-match_opts">match_opts()</a>) -&gt; [{<a href="#type-plum_db_key">plum_db_key()</a>, <a href="#type-value_or_values">value_or_values()</a>}] | {[{<a href="#type-plum_db_key">plum_db_key()</a>, <a href="#type-value_or_values">value_or_values()</a>}], <a href="#type-continuation">continuation()</a>} | $end_of_table
</code></pre>
<br />

<a name="merge-2"></a>

### merge/2 ###

<pre><code>
merge(X1::{<a href="#type-plum_db_pkey">plum_db_pkey()</a>, undefined | <a href="#type-plum_db_context">plum_db_context()</a>}, Obj::undefined | <a href="#type-plum_db_object">plum_db_object()</a>) -&gt; boolean()
</code></pre>
<br />

Merges a remote copy of an object record sent via broadcast w/ the
local view for the key contained in the message id. If the remote copy is
causally older than the current data stored then `false` is returned and no
updates are merged. Otherwise, the remote copy is merged (possibly
generating siblings) and `true` is returned.

> This function is part of the implementation of the
plumtree_broadcast_handler behaviour.
> You should never call it directly.

<a name="merge-3"></a>

### merge/3 ###

<pre><code>
merge(Node::node(), X2::{<a href="#type-plum_db_pkey">plum_db_pkey()</a>, undefined | <a href="#type-plum_db_context">plum_db_context()</a>}, Obj::<a href="#type-plum_db_object">plum_db_object()</a>) -&gt; boolean()
</code></pre>
<br />

Same as merge/2 but merges the object on `Node`

> This function is part of the implementation of the
plumtree_broadcast_handler behaviour.
> You should never call it directly.

<a name="partition_count-0"></a>

### partition_count/0 ###

<pre><code>
partition_count() -&gt; non_neg_integer()
</code></pre>
<br />

Returns the number of partitions.

<a name="partitions-0"></a>

### partitions/0 ###

<pre><code>
partitions() -&gt; [<a href="#type-partition">partition()</a>]
</code></pre>
<br />

Returns the list of the partition identifiers starting at 0.

<a name="prefix_hash-2"></a>

### prefix_hash/2 ###

<pre><code>
prefix_hash(Partition::<a href="#type-partition">partition()</a>, Prefix::<a href="#type-plum_db_prefix">plum_db_prefix()</a>) -&gt; binary() | undefined
</code></pre>
<br />

Return the local hash associated with a full-prefix or prefix. The hash
value is updated periodically and does not always reflect the most recent
value. This function can be used to determine when keys stored under a
full-prefix or prefix have changed.
If the tree has not yet been updated or there are no keys stored the given
(full-)prefix. `undefined` is returned.

<a name="prefix_type-1"></a>

### prefix_type/1 ###

<pre><code>
prefix_type(Prefix::term()) -&gt; <a href="#type-prefix_type">prefix_type()</a> | undefined
</code></pre>
<br />

<a name="prefixes-0"></a>

### prefixes/0 ###

<pre><code>
prefixes() -&gt; <a href="#type-prefixes">prefixes()</a>
</code></pre>
<br />

Returns a mapping of prefixes (the first element of a plum_db_prefix()
tuple) to prefix_type() only for those prefixes for which a type was
declared using the application optiont `prefixes`.

<a name="put-3"></a>

### put/3 ###

<pre><code>
put(FullPrefix::<a href="#type-plum_db_prefix">plum_db_prefix()</a>, Key::<a href="#type-plum_db_key">plum_db_key()</a>, ValueOrFun::<a href="#type-plum_db_value">plum_db_value()</a> | <a href="#type-plum_db_modifier">plum_db_modifier()</a>) -&gt; ok
</code></pre>
<br />

Same as put(FullPrefix, Key, Value, [])

<a name="put-4"></a>

### put/4 ###

<pre><code>
put(FullPrefix::<a href="#type-plum_db_prefix">plum_db_prefix()</a>, Key::<a href="#type-plum_db_key">plum_db_key()</a>, ValueOrFun::<a href="#type-plum_db_value">plum_db_value()</a> | <a href="#type-plum_db_modifier">plum_db_modifier()</a>, Opts::<a href="#type-put_opts">put_opts()</a>) -&gt; ok
</code></pre>
<br />

Stores or updates the value at the given prefix and key locally and then
triggers a broadcast to notify other nodes in the cluster. Currently, there
are no put options.

NOTE: because the third argument to this function can be a plum_db_modifier(),
used to resolve conflicts on write, values cannot be functions.
To store functions wrap them in another type like a tuple.

<a name="remote_iterator-1"></a>

### remote_iterator/1 ###

<pre><code>
remote_iterator(Node::node()) -&gt; <a href="#type-remote_iterator">remote_iterator()</a>
</code></pre>
<br />

Create an iterator on `Node`. This allows for remote iteration by having
the worker keep track of the actual iterator (since ets
continuations cannot cross node boundaries). The iterator created iterates
all full-prefixes.
Once created the rest of the iterator API may be used as usual. When done
with the iterator, iterator_close/1 must be called

<a name="remote_iterator-2"></a>

### remote_iterator/2 ###

<pre><code>
remote_iterator(Node::node(), FullPrefix::<a href="#type-plum_db_prefix">plum_db_prefix()</a>) -&gt; <a href="#type-remote_iterator">remote_iterator()</a>
</code></pre>
<br />

<a name="start_link-0"></a>

### start_link/0 ###

<pre><code>
start_link() -&gt; {ok, pid()} | ignore | {error, term()}
</code></pre>
<br />

Start the plum_db server and link to calling process.
The plum_db server is responsible for managing local and remote iterators.
No API function uses the server itself.

<a name="sync_exchange-1"></a>

### sync_exchange/1 ###

<pre><code>
sync_exchange(Peer::node()) -&gt; ok | {error, term()}
</code></pre>
<br />

Triggers a synchronous exchange.
Calls [`sync_exchange/2`](#sync_exchange-2) with an empty map as the second argument.
> The exchange is only triggered if the application option `aae_enabled` is
set to `true`.

<a name="sync_exchange-2"></a>

### sync_exchange/2 ###

<pre><code>
sync_exchange(Peer::node(), Opts0::map()) -&gt; ok | {error, term()}
</code></pre>
<br />

Triggers a synchronous exchange.
The exchange is performed synchronously by spawning a supervised process and
waiting (blocking) till it finishes.
Read the [`plum_db_exchanges_sup`](plum_db_exchanges_sup.md) documentation.

`Opts` is a map accepting the following options:

* `timeout` (milliseconds) –– timeout for the AAE exchange to conclude.

> The exchange is only triggered if the application option `aae_enabled` is
set to `true`.

<a name="take-2"></a>

### take/2 ###

<pre><code>
take(FullPrefix::<a href="#type-plum_db_prefix">plum_db_prefix()</a>, Key::<a href="#type-plum_db_key">plum_db_key()</a>) -&gt; <a href="#type-plum_db_value">plum_db_value()</a> | undefined
</code></pre>
<br />

<a name="take-3"></a>

### take/3 ###

<pre><code>
take(FullPrefix::<a href="#type-plum_db_prefix">plum_db_prefix()</a>, Key::<a href="#type-plum_db_key">plum_db_key()</a>, Opts::<a href="#type-get_opts">get_opts()</a>) -&gt; <a href="#type-plum_db_value">plum_db_value()</a> | undefined
</code></pre>
<br />

<a name="to_list-1"></a>

### to_list/1 ###

<pre><code>
to_list(FullPrefix::<a href="#type-plum_db_prefix">plum_db_prefix()</a>) -&gt; [{<a href="#type-plum_db_key">plum_db_key()</a>, <a href="#type-value_or_values">value_or_values()</a>}]
</code></pre>
<br />

Same as to_list(FullPrefix, [])

<a name="to_list-2"></a>

### to_list/2 ###

<pre><code>
to_list(FullPrefix::<a href="#type-plum_db_prefix">plum_db_prefix()</a>, Opts::<a href="#type-fold_opts">fold_opts()</a>) -&gt; [{<a href="#type-plum_db_key">plum_db_key()</a>, <a href="#type-value_or_values">value_or_values()</a>}]
</code></pre>
<br />

Return a list of all keys and values stored under a given
prefix/subprefix. Available options are the same as those provided to
iterator/2.

