

# Module plum_db_object #
* [Data Types](#types)
* [Function Index](#index)
* [Function Details](#functions)

<a name="types"></a>

## Data Types ##




### <a name="type-plum_db_context">plum_db_context()</a> ###


<pre><code>
plum_db_context() = <a href="dvvset.md#type-vector">plum_db_dvvset:vector()</a>
</code></pre>




### <a name="type-plum_db_modifier">plum_db_modifier()</a> ###


<pre><code>
plum_db_modifier() = fun(([<a href="#type-plum_db_value">plum_db_value()</a> | <a href="#type-plum_db_tombstone">plum_db_tombstone()</a>] | undefined) -&gt; <a href="#type-plum_db_value">plum_db_value()</a>)
</code></pre>




### <a name="type-plum_db_object">plum_db_object()</a> ###


<pre><code>
plum_db_object() = {object, <a href="dvvset.md#type-clock">plum_db_dvvset:clock()</a>}
</code></pre>




### <a name="type-plum_db_tombstone">plum_db_tombstone()</a> ###


<pre><code>
plum_db_tombstone() = $deleted
</code></pre>




### <a name="type-plum_db_value">plum_db_value()</a> ###


<pre><code>
plum_db_value() = any()
</code></pre>

<a name="index"></a>

## Function Index ##


<table width="100%" border="1" cellspacing="0" cellpadding="2" summary="function index"><tr><td valign="top"><a href="#context-1">context/1</a></td><td>returns the context (opaque causal history) for the given object.</td></tr><tr><td valign="top"><a href="#empty_context-0">empty_context/0</a></td><td>returns the representation for an empty context (opaque causal history).</td></tr><tr><td valign="top"><a href="#equal_context-2">equal_context/2</a></td><td>Returns true if the given context and the context of the existing object are equal.</td></tr><tr><td valign="top"><a href="#hash-1">hash/1</a></td><td>returns a hash representing the objects contents.</td></tr><tr><td valign="top"><a href="#is_stale-2">is_stale/2</a></td><td>Determines if the given context (version vector) is causually newer than
an existing object.</td></tr><tr><td valign="top"><a href="#modify-4">modify/4</a></td><td>modifies a potentially existing object, setting its value and updating
the causual history.</td></tr><tr><td valign="top"><a href="#reconcile-2">reconcile/2</a></td><td>Reconciles a remote object received during replication or anti-entropy
with a local object.</td></tr><tr><td valign="top"><a href="#resolve-2">resolve/2</a></td><td>Resolves siblings using either last-write-wins or the provided function and returns
an object containing a single value.</td></tr><tr><td valign="top"><a href="#value-1">value/1</a></td><td>returns a single value.</td></tr><tr><td valign="top"><a href="#value_count-1">value_count/1</a></td><td>returns the number of siblings in the given object.</td></tr><tr><td valign="top"><a href="#values-1">values/1</a></td><td>returns a list of values held in the object.</td></tr></table>


<a name="functions"></a>

## Function Details ##

<a name="context-1"></a>

### context/1 ###

<pre><code>
context(X1::<a href="#type-plum_db_object">plum_db_object()</a>) -&gt; <a href="#type-plum_db_context">plum_db_context()</a>
</code></pre>
<br />

returns the context (opaque causal history) for the given object

<a name="empty_context-0"></a>

### empty_context/0 ###

<pre><code>
empty_context() -&gt; <a href="#type-plum_db_context">plum_db_context()</a>
</code></pre>
<br />

returns the representation for an empty context (opaque causal history)

<a name="equal_context-2"></a>

### equal_context/2 ###

<pre><code>
equal_context(Context::<a href="#type-plum_db_context">plum_db_context()</a>, X2::<a href="#type-plum_db_object">plum_db_object()</a>) -&gt; boolean()
</code></pre>
<br />

Returns true if the given context and the context of the existing object are equal

<a name="hash-1"></a>

### hash/1 ###

<pre><code>
hash(X1::<a href="#type-plum_db_object">plum_db_object()</a>) -&gt; binary()
</code></pre>
<br />

returns a hash representing the objects contents

<a name="is_stale-2"></a>

### is_stale/2 ###

<pre><code>
is_stale(RemoteContext::<a href="#type-plum_db_context">plum_db_context()</a>, X2::<a href="#type-plum_db_object">plum_db_object()</a>) -&gt; boolean()
</code></pre>
<br />

Determines if the given context (version vector) is causually newer than
an existing object. If the object missing or if the context does not represent
an anscestor of the current key, false is returned. Otherwise, when the context
does represent an ancestor of the existing object or the existing object itself,
true is returned

<a name="modify-4"></a>

### modify/4 ###

<pre><code>
modify(Obj::<a href="#type-plum_db_object">plum_db_object()</a> | undefined, Context::<a href="#type-plum_db_context">plum_db_context()</a>, Fun::<a href="#type-plum_db_value">plum_db_value()</a> | <a href="#type-plum_db_modifier">plum_db_modifier()</a>, ServerId::term()) -&gt; <a href="#type-plum_db_object">plum_db_object()</a>
</code></pre>
<br />

modifies a potentially existing object, setting its value and updating
the causual history. If a function is provided as the third argument
then this function also is used for conflict resolution. The difference
between this function and resolve/2 is that the logical clock is advanced in the
case of this function. Additionally, the resolution functions are slightly different.

<a name="reconcile-2"></a>

### reconcile/2 ###

<pre><code>
reconcile(RemoteObj::<a href="#type-plum_db_object">plum_db_object()</a>, LocalObj::<a href="#type-plum_db_object">plum_db_object()</a> | undefined) -&gt; false | {true, <a href="#type-plum_db_object">plum_db_object()</a>}
</code></pre>
<br />

Reconciles a remote object received during replication or anti-entropy
with a local object. If the remote object is an anscestor of or is equal to the local one
`false` is returned, otherwise the reconciled object is returned as the second
element of the two-tuple

<a name="resolve-2"></a>

### resolve/2 ###

<pre><code>
resolve(X1::<a href="#type-plum_db_object">plum_db_object()</a>, Reconcile::lww | fun(([<a href="#type-plum_db_value">plum_db_value()</a>]) -&gt; <a href="#type-plum_db_value">plum_db_value()</a>)) -&gt; <a href="#type-plum_db_object">plum_db_object()</a>
</code></pre>
<br />

Resolves siblings using either last-write-wins or the provided function and returns
an object containing a single value. The causal history is not updated

<a name="value-1"></a>

### value/1 ###

<pre><code>
value(Obj::<a href="#type-plum_db_object">plum_db_object()</a>) -&gt; <a href="#type-plum_db_value">plum_db_value()</a>
</code></pre>
<br />

returns a single value. if the object holds more than one value an error is generated

__See also:__ [values/2](#values-2).

<a name="value_count-1"></a>

### value_count/1 ###

<pre><code>
value_count(X1::<a href="#type-plum_db_object">plum_db_object()</a>) -&gt; non_neg_integer()
</code></pre>
<br />

returns the number of siblings in the given object

<a name="values-1"></a>

### values/1 ###

<pre><code>
values(X1::<a href="#type-plum_db_object">plum_db_object()</a>) -&gt; [<a href="#type-plum_db_value">plum_db_value()</a>]
</code></pre>
<br />

returns a list of values held in the object

