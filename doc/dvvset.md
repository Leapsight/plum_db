

# Module dvvset #
* [Description](#description)
* [Data Types](#types)
* [Function Index](#index)
* [Function Details](#functions)

An Erlang implementation of *compact* Dotted Version Vectors, which
provides a container for a set of concurrent values (siblings) with causal
order information.

Copyright (c) The MIT License (MIT)
Copyright (C) 2013

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and
associated documentation files (the "Software"), to deal in the Software without restriction,
including without limitation the rights to use, copy, modify, merge, publish, distribute,
sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or
substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING
BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

__Authors:__ Ricardo Tomé Gonçalves ([`tome.wave@gmail.com`](mailto:tome.wave@gmail.com)), Paulo Sérgio Almeida ([`pssalmeida@gmail.com`](mailto:pssalmeida@gmail.com)).

__References__* [
Dotted Version Vectors: Logical Clocks for Optimistic Replication
](http://arxiv.org/abs/1011.5808)

<a name="description"></a>

## Description ##
For further reading, visit the
[github page](https://github.com/ricardobcl/Dotted-Version-Vectors/tree/ompact).
<a name="types"></a>

## Data Types ##




### <a name="type-clock">clock()</a> ###


<pre><code>
clock() = {<a href="#type-entries">entries()</a>, <a href="#type-values">values()</a>}
</code></pre>




### <a name="type-counter">counter()</a> ###


<pre><code>
counter() = non_neg_integer()
</code></pre>




### <a name="type-entries">entries()</a> ###


<pre><code>
entries() = [{<a href="#type-id">id()</a>, <a href="#type-counter">counter()</a>, <a href="#type-values">values()</a>}]
</code></pre>




### <a name="type-id">id()</a> ###


<pre><code>
id() = any()
</code></pre>




### <a name="type-value">value()</a> ###


<pre><code>
value() = any()
</code></pre>




### <a name="type-values">values()</a> ###


<pre><code>
values() = [<a href="#type-value">value()</a>]
</code></pre>




### <a name="type-vector">vector()</a> ###


<pre><code>
vector() = [{<a href="#type-id">id()</a>, <a href="#type-counter">counter()</a>}]
</code></pre>

<a name="index"></a>

## Function Index ##


<table width="100%" border="1" cellspacing="0" cellpadding="2" summary="function index"><tr><td valign="top"><a href="#equal-2">equal/2</a></td><td>Compares the equality of both clocks, regarding
only the causal histories, thus ignoring the values.</td></tr><tr><td valign="top"><a href="#ids-1">ids/1</a></td><td>Returns all the ids used in this clock set.</td></tr><tr><td valign="top"><a href="#join-1">join/1</a></td><td>Return a version vector that represents the causal history.</td></tr><tr><td valign="top"><a href="#last-2">last/2</a></td><td>Returns the latest value in the clock set,
according to function F(A,B), which returns *true* if
A compares less than or equal to B, false otherwise.</td></tr><tr><td valign="top"><a href="#less-2">less/2</a></td><td>Returns True if the first clock is causally older than
the second clock, thus values on the first clock are outdated.</td></tr><tr><td valign="top"><a href="#lww-2">lww/2</a></td><td>Return a clock with the same causal history, but with only one
value in its original position.</td></tr><tr><td valign="top"><a href="#map-2">map/2</a></td><td>Maps (applies) a function on all values in this clock set,
returning the same clock set with the updated values.</td></tr><tr><td valign="top"><a href="#new-1">new/1</a></td><td>Constructs a new clock set without causal history,
and receives a list of values that gos to the anonymous list.</td></tr><tr><td valign="top"><a href="#new-2">new/2</a></td><td>Constructs a new clock set with the causal history
of the given version vector / vector clock,
and receives a list of values that gos to the anonymous list.</td></tr><tr><td valign="top"><a href="#reconcile-2">reconcile/2</a></td><td>Return a clock with the same causal history, but with only one
value in the anonymous placeholder.</td></tr><tr><td valign="top"><a href="#size-1">size/1</a></td><td>Returns the total number of values in this clock set.</td></tr><tr><td valign="top"><a href="#sync-1">sync/1</a></td><td>Synchronizes a list of clocks using sync/2.</td></tr><tr><td valign="top"><a href="#update-2">update/2</a></td><td>Advances the causal history with the given id.</td></tr><tr><td valign="top"><a href="#update-3">update/3</a></td><td>Advances the causal history of the
first clock with the given id, while synchronizing
with the second clock, thus the new clock is
causally newer than both clocks in the argument.</td></tr><tr><td valign="top"><a href="#values-1">values/1</a></td><td>Returns all the values used in this clock set,
including the anonymous values.</td></tr></table>


<a name="functions"></a>

## Function Details ##

<a name="equal-2"></a>

### equal/2 ###

<pre><code>
equal(C1::<a href="#type-clock">clock()</a> | <a href="#type-vector">vector()</a>, C2::<a href="#type-clock">clock()</a> | <a href="#type-vector">vector()</a>) -&gt; boolean()
</code></pre>
<br />

Compares the equality of both clocks, regarding
only the causal histories, thus ignoring the values.

<a name="ids-1"></a>

### ids/1 ###

<pre><code>
ids(X1::<a href="#type-clock">clock()</a>) -&gt; [<a href="#type-id">id()</a>]
</code></pre>
<br />

Returns all the ids used in this clock set.

<a name="join-1"></a>

### join/1 ###

<pre><code>
join(X1::<a href="#type-clock">clock()</a>) -&gt; <a href="#type-vector">vector()</a>
</code></pre>
<br />

Return a version vector that represents the causal history.

<a name="last-2"></a>

### last/2 ###

<pre><code>
last(LessOrEqual::fun((<a href="#type-value">value()</a>, <a href="#type-value">value()</a>) -&gt; boolean()), C::<a href="#type-clock">clock()</a>) -&gt; <a href="#type-value">value()</a>
</code></pre>
<br />

Returns the latest value in the clock set,
according to function F(A,B), which returns *true* if
A compares less than or equal to B, false otherwise.

<a name="less-2"></a>

### less/2 ###

<pre><code>
less(X1::<a href="#type-clock">clock()</a>, X2::<a href="#type-clock">clock()</a>) -&gt; boolean()
</code></pre>
<br />

Returns True if the first clock is causally older than
the second clock, thus values on the first clock are outdated.
Returns False otherwise.

<a name="lww-2"></a>

### lww/2 ###

<pre><code>
lww(LessOrEqual::fun((<a href="#type-value">value()</a>, <a href="#type-value">value()</a>) -&gt; boolean()), C::<a href="#type-clock">clock()</a>) -&gt; <a href="#type-clock">clock()</a>
</code></pre>
<br />

Return a clock with the same causal history, but with only one
value in its original position. This value is the newest value
in the given clock, according to function F(A,B), which returns *true*
if A compares less than or equal to B, false otherwise.

<a name="map-2"></a>

### map/2 ###

<pre><code>
map(F::fun((<a href="#type-value">value()</a>) -&gt; <a href="#type-value">value()</a>), X2::<a href="#type-clock">clock()</a>) -&gt; <a href="#type-clock">clock()</a>
</code></pre>
<br />

Maps (applies) a function on all values in this clock set,
returning the same clock set with the updated values.

<a name="new-1"></a>

### new/1 ###

<pre><code>
new(Vs::<a href="#type-value">value()</a> | [<a href="#type-value">value()</a>]) -&gt; <a href="#type-clock">clock()</a>
</code></pre>
<br />

Constructs a new clock set without causal history,
and receives a list of values that gos to the anonymous list.

<a name="new-2"></a>

### new/2 ###

<pre><code>
new(VV::<a href="#type-vector">vector()</a>, Vs::<a href="#type-value">value()</a> | [<a href="#type-value">value()</a>]) -&gt; <a href="#type-clock">clock()</a>
</code></pre>
<br />

Constructs a new clock set with the causal history
of the given version vector / vector clock,
and receives a list of values that gos to the anonymous list.
The version vector SHOULD BE a direct result of join/1.

<a name="reconcile-2"></a>

### reconcile/2 ###

<pre><code>
reconcile(Winner::fun(([<a href="#type-value">value()</a>]) -&gt; <a href="#type-value">value()</a>), C::<a href="#type-clock">clock()</a>) -&gt; <a href="#type-clock">clock()</a>
</code></pre>
<br />

Return a clock with the same causal history, but with only one
value in the anonymous placeholder. This value is the result of
the function F, which takes all values and returns a single new value.

<a name="size-1"></a>

### size/1 ###

<pre><code>
size(X1::<a href="#type-clock">clock()</a>) -&gt; non_neg_integer()
</code></pre>
<br />

Returns the total number of values in this clock set.

<a name="sync-1"></a>

### sync/1 ###

<pre><code>
sync(L::[<a href="#type-clock">clock()</a>]) -&gt; <a href="#type-clock">clock()</a>
</code></pre>
<br />

Synchronizes a list of clocks using sync/2.
It discards (causally) outdated values,
while merging all causal histories.

<a name="update-2"></a>

### update/2 ###

<pre><code>
update(X1::<a href="#type-clock">clock()</a>, I::<a href="#type-id">id()</a>) -&gt; <a href="#type-clock">clock()</a>
</code></pre>
<br />

Advances the causal history with the given id.
The new value is the *anonymous dot* of the clock.
The client clock SHOULD BE a direct result of new/2.

<a name="update-3"></a>

### update/3 ###

<pre><code>
update(X1::<a href="#type-clock">clock()</a>, Cr::<a href="#type-clock">clock()</a>, I::<a href="#type-id">id()</a>) -&gt; <a href="#type-clock">clock()</a>
</code></pre>
<br />

Advances the causal history of the
first clock with the given id, while synchronizing
with the second clock, thus the new clock is
causally newer than both clocks in the argument.
The new value is the *anonymous dot* of the clock.
The first clock SHOULD BE a direct result of new/2,
which is intended to be the client clock with
the new value in the *anonymous dot* while
the second clock is from the local server.

<a name="values-1"></a>

### values/1 ###

<pre><code>
values(X1::<a href="#type-clock">clock()</a>) -&gt; [<a href="#type-value">value()</a>]
</code></pre>
<br />

Returns all the values used in this clock set,
including the anonymous values.

