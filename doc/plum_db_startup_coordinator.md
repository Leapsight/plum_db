

# Module plum_db_startup_coordinator #
* [Description](#description)
* [Function Index](#index)
* [Function Details](#functions)

A transient worker that is used to listen to certain plum_db events and
allow watchers to wait (blocking the caller) for certain conditions.

__Behaviours:__ [`gen_server`](gen_server.md).

<a name="description"></a>

## Description ##

This is used by plum_db_app during the startup process to wait for the
following conditions:

* Partition initisalisation – the worker subscribes to plum_db notifications
and keeps track of each partition initialisation until they are all
initialised (or failed to initilised) and replies to all watchers with a
`ok` or `{error, FailedPartitions}`, where FailedPartitions is a map() which
keys are the partition number and the value is the reason for the failure.
* Partition hashtree build – the worker subscribes to plum_db notifications
and keeps track of each partition hashtree until they are all
built (or failed to build) and replies to all watchers with a
`ok` or `{error, FailedHashtrees}`, where FailedHashtrees is a map() which
keys are the partition number and the value is the reason for the failure.

A watcher is any process which calls the functions wait_for_partitions/0,1
and/or wait_for_hashtrees/0,1. Both functions will block the caller until
the above conditions are met.
<a name="index"></a>

## Function Index ##


<table width="100%" border="1" cellspacing="0" cellpadding="2" summary="function index"><tr><td valign="top"><a href="#start_link-0">start_link/0</a></td><td>Start plumtree_partitions_coordinator and link to calling process.</td></tr><tr><td valign="top"><a href="#stop-0">stop/0</a></td><td></td></tr><tr><td valign="top"><a href="#wait_for_hashtrees-0">wait_for_hashtrees/0</a></td><td>Blocks the caller until all hastrees are built.</td></tr><tr><td valign="top"><a href="#wait_for_hashtrees-1">wait_for_hashtrees/1</a></td><td>Blocks the caller until all hastrees are built or the timeout TImeout
is reached.</td></tr><tr><td valign="top"><a href="#wait_for_partitions-0">wait_for_partitions/0</a></td><td>Blocks the caller until all partitions are initialised.</td></tr><tr><td valign="top"><a href="#wait_for_partitions-1">wait_for_partitions/1</a></td><td>Blocks the caller until all partitions are initialised
or the timeout TImeout is reached.</td></tr></table>


<a name="functions"></a>

## Function Details ##

<a name="start_link-0"></a>

### start_link/0 ###

<pre><code>
start_link() -&gt; {ok, pid()} | ignore | {error, term()}
</code></pre>
<br />

Start plumtree_partitions_coordinator and link to calling process.

<a name="stop-0"></a>

### stop/0 ###

<pre><code>
stop() -&gt; ok
</code></pre>
<br />

<a name="wait_for_hashtrees-0"></a>

### wait_for_hashtrees/0 ###

<pre><code>
wait_for_hashtrees() -&gt; ok | {error, timeout} | {error, FailedHashtrees::map()}
</code></pre>
<br />

Blocks the caller until all hastrees are built.
This is equivalent to calling `wait_for_hashtrees(infinity)`.

<a name="wait_for_hashtrees-1"></a>

### wait_for_hashtrees/1 ###

<pre><code>
wait_for_hashtrees(Timeout::timeout()) -&gt; ok | {error, timeout} | {error, FailedHashtrees::map()}
</code></pre>
<br />

Blocks the caller until all hastrees are built or the timeout TImeout
is reached.

<a name="wait_for_partitions-0"></a>

### wait_for_partitions/0 ###

<pre><code>
wait_for_partitions() -&gt; ok | {error, timeout} | {error, FailedPartitions::map()}
</code></pre>
<br />

Blocks the caller until all partitions are initialised.
This is equivalent to calling `wait_for_partitions(infinity)`.

<a name="wait_for_partitions-1"></a>

### wait_for_partitions/1 ###

<pre><code>
wait_for_partitions(Timeout::timeout()) -&gt; ok | {error, timeout} | {error, FailedPartitions::map()}
</code></pre>
<br />

Blocks the caller until all partitions are initialised
or the timeout TImeout is reached.

