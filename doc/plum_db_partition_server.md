

# Module plum_db_partition_server #
* [Description](#description)
* [Data Types](#types)
* [Function Index](#index)
* [Function Details](#functions)

A wrapper for an elevelb instance.

__Behaviours:__ [`gen_server`](gen_server.md).

<a name="types"></a>

## Data Types ##




### <a name="type-iterator">iterator()</a> ###


<pre><code>
iterator() = #partition_iterator{owner_ref = reference(), partition = non_neg_integer(), full_prefix = <a href="#type-plum_db_prefix_pattern">plum_db_prefix_pattern()</a>, match_pattern = term(), bin_prefix = binary(), match_spec = <a href="ets.md#type-comp_match_spec">ets:comp_match_spec()</a> | undefined, keys_only = boolean(), prev_key = <a href="#type-plum_db_pkey">plum_db_pkey()</a> | undefined, disk_done = boolean(), ram_disk_done = boolean(), ram_done = boolean(), disk = <a href="eleveldb.md#type-itr_ref">eleveldb:itr_ref()</a> | undefined, ram = key | {cont, any()} | undefined, ram_disk = key | {cont, any()} | undefined, ram_tab = atom(), ram_disk_tab = atom()}
</code></pre>




### <a name="type-iterator_action">iterator_action()</a> ###


<pre><code>
iterator_action() = first | last | next | prev | prefetch | prefetch_stop | <a href="#type-plum_db_prefix">plum_db_prefix()</a> | <a href="#type-plum_db_pkey">plum_db_pkey()</a> | binary()
</code></pre>




### <a name="type-iterator_move_result">iterator_move_result()</a> ###


<pre><code>
iterator_move_result() = {ok, Key::binary() | <a href="#type-plum_db_pkey">plum_db_pkey()</a>, Value::binary(), <a href="#type-iterator">iterator()</a>} | {ok, Key::binary() | <a href="#type-plum_db_pkey">plum_db_pkey()</a>, <a href="#type-iterator">iterator()</a>} | {error, invalid_iterator, <a href="#type-iterator">iterator()</a>} | {error, iterator_closed, <a href="#type-iterator">iterator()</a>} | {error, no_match, <a href="#type-iterator">iterator()</a>}
</code></pre>




### <a name="type-opts">opts()</a> ###


<pre><code>
opts() = [{atom(), term()}]
</code></pre>




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




### <a name="type-plum_db_prefix_pattern">plum_db_prefix_pattern()</a> ###


<pre><code>
plum_db_prefix_pattern() = {binary() | atom() | <a href="#type-plum_db_wildcard">plum_db_wildcard()</a>, binary() | atom() | <a href="#type-plum_db_wildcard">plum_db_wildcard()</a>}
</code></pre>




### <a name="type-plum_db_wildcard">plum_db_wildcard()</a> ###


<pre><code>
plum_db_wildcard() = _
</code></pre>

<a name="index"></a>

## Function Index ##


<table width="100%" border="1" cellspacing="0" cellpadding="2" summary="function index"><tr><td valign="top"><a href="#byte_size-1">byte_size/1</a></td><td></td></tr><tr><td valign="top"><a href="#code_change-3">code_change/3</a></td><td></td></tr><tr><td valign="top"><a href="#delete-1">delete/1</a></td><td></td></tr><tr><td valign="top"><a href="#delete-2">delete/2</a></td><td></td></tr><tr><td valign="top"><a href="#get-1">get/1</a></td><td></td></tr><tr><td valign="top"><a href="#get-2">get/2</a></td><td></td></tr><tr><td valign="top"><a href="#handle_call-3">handle_call/3</a></td><td></td></tr><tr><td valign="top"><a href="#handle_cast-2">handle_cast/2</a></td><td></td></tr><tr><td valign="top"><a href="#handle_info-2">handle_info/2</a></td><td></td></tr><tr><td valign="top"><a href="#init-1">init/1</a></td><td></td></tr><tr><td valign="top"><a href="#is_empty-1">is_empty/1</a></td><td></td></tr><tr><td valign="top"><a href="#iterator-2">iterator/2</a></td><td></td></tr><tr><td valign="top"><a href="#iterator-3">iterator/3</a></td><td>If the prefix is ground, it restricts the iteration on keys belonging
to that prefix and the storage type of the prefix if known.</td></tr><tr><td valign="top"><a href="#iterator_close-2">iterator_close/2</a></td><td></td></tr><tr><td valign="top"><a href="#iterator_move-2">iterator_move/2</a></td><td>Iterates over the storage stack in order (disk -> ram_disk -> ram).</td></tr><tr><td valign="top"><a href="#key_iterator-2">key_iterator/2</a></td><td></td></tr><tr><td valign="top"><a href="#key_iterator-3">key_iterator/3</a></td><td></td></tr><tr><td valign="top"><a href="#put-2">put/2</a></td><td></td></tr><tr><td valign="top"><a href="#put-3">put/3</a></td><td></td></tr><tr><td valign="top"><a href="#start_link-2">start_link/2</a></td><td></td></tr><tr><td valign="top"><a href="#terminate-2">terminate/2</a></td><td></td></tr></table>


<a name="functions"></a>

## Function Details ##

<a name="byte_size-1"></a>

### byte_size/1 ###

`byte_size(Id) -> any()`

<a name="code_change-3"></a>

### code_change/3 ###

`code_change(OldVsn, State, Extra) -> any()`

<a name="delete-1"></a>

### delete/1 ###

`delete(Key) -> any()`

<a name="delete-2"></a>

### delete/2 ###

`delete(Partition, Key) -> any()`

<a name="get-1"></a>

### get/1 ###

`get(PKey) -> any()`

<a name="get-2"></a>

### get/2 ###

`get(Partition, PKey) -> any()`

<a name="handle_call-3"></a>

### handle_call/3 ###

`handle_call(X1, From, State) -> any()`

<a name="handle_cast-2"></a>

### handle_cast/2 ###

`handle_cast(Msg, State) -> any()`

<a name="handle_info-2"></a>

### handle_info/2 ###

`handle_info(Info, State) -> any()`

<a name="init-1"></a>

### init/1 ###

`init(X1) -> any()`

<a name="is_empty-1"></a>

### is_empty/1 ###

`is_empty(Id) -> any()`

<a name="iterator-2"></a>

### iterator/2 ###

`iterator(Id, FullPrefix) -> any()`

<a name="iterator-3"></a>

### iterator/3 ###

`iterator(Id, FullPrefix, Opts) -> any()`

If the prefix is ground, it restricts the iteration on keys belonging
to that prefix and the storage type of the prefix if known. If prefix is
undefined or storage type of is undefined, then it starts with disk and
follows with ram. It does not cover ram_disk as all data in ram_disk is in
disk but not viceversa.

<a name="iterator_close-2"></a>

### iterator_close/2 ###

`iterator_close(Id, Iter) -> any()`

<a name="iterator_move-2"></a>

### iterator_move/2 ###

<pre><code>
iterator_move(Partition_iterator::<a href="#type-iterator">iterator()</a>, Action::<a href="#type-iterator_action">iterator_action()</a>) -&gt; <a href="#type-iterator_move_result">iterator_move_result()</a>
</code></pre>
<br />

Iterates over the storage stack in order (disk -> ram_disk -> ram).

<a name="key_iterator-2"></a>

### key_iterator/2 ###

`key_iterator(Id, FullPrefix) -> any()`

<a name="key_iterator-3"></a>

### key_iterator/3 ###

`key_iterator(Id, FullPrefix, Opts) -> any()`

<a name="put-2"></a>

### put/2 ###

`put(PKey, Value) -> any()`

<a name="put-3"></a>

### put/3 ###

`put(Partition, PKey, Value) -> any()`

<a name="start_link-2"></a>

### start_link/2 ###

<pre><code>
start_link(Partition::non_neg_integer(), Opts::<a href="#type-opts">opts()</a>) -&gt; any()
</code></pre>
<br />

<a name="terminate-2"></a>

### terminate/2 ###

`terminate(Reason, State) -> any()`

