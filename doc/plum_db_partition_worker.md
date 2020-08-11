

# Module plum_db_partition_worker #
* [Data Types](#types)
* [Function Index](#index)
* [Function Details](#functions)

__Behaviours:__ [`gen_server`](gen_server.md).

<a name="types"></a>

## Data Types ##




### <a name="type-state">state()</a> ###


<pre><code>
state() = #state{partition = non_neg_integer(), server_id = term()}
</code></pre>

<a name="index"></a>

## Function Index ##


<table width="100%" border="1" cellspacing="0" cellpadding="2" summary="function index"><tr><td valign="top"><a href="#code_change-3">code_change/3</a></td><td></td></tr><tr><td valign="top"><a href="#handle_call-3">handle_call/3</a></td><td></td></tr><tr><td valign="top"><a href="#handle_cast-2">handle_cast/2</a></td><td></td></tr><tr><td valign="top"><a href="#handle_info-2">handle_info/2</a></td><td></td></tr><tr><td valign="top"><a href="#init-1">init/1</a></td><td></td></tr><tr><td valign="top"><a href="#start_link-1">start_link/1</a></td><td>Start plum_db_partition_worker for the partition Id and link to calling
process.</td></tr><tr><td valign="top"><a href="#terminate-2">terminate/2</a></td><td></td></tr></table>


<a name="functions"></a>

## Function Details ##

<a name="code_change-3"></a>

### code_change/3 ###

<pre><code>
code_change(OldVsn::term() | {down, term()}, State::<a href="#type-state">state()</a>, Extra::term()) -&gt; {ok, <a href="#type-state">state()</a>}
</code></pre>
<br />

<a name="handle_call-3"></a>

### handle_call/3 ###

<pre><code>
handle_call(X1::term(), From::{pid(), term()}, State::<a href="#type-state">state()</a>) -&gt; {reply, term(), <a href="#type-state">state()</a>} | {reply, term(), <a href="#type-state">state()</a>, non_neg_integer()} | {noreply, <a href="#type-state">state()</a>} | {noreply, <a href="#type-state">state()</a>, non_neg_integer()} | {stop, term(), term(), <a href="#type-state">state()</a>} | {stop, term(), <a href="#type-state">state()</a>}
</code></pre>
<br />

<a name="handle_cast-2"></a>

### handle_cast/2 ###

<pre><code>
handle_cast(Msg::term(), State::<a href="#type-state">state()</a>) -&gt; {noreply, <a href="#type-state">state()</a>} | {noreply, <a href="#type-state">state()</a>, non_neg_integer()} | {stop, term(), <a href="#type-state">state()</a>}
</code></pre>
<br />

<a name="handle_info-2"></a>

### handle_info/2 ###

<pre><code>
handle_info(X1::term(), State::<a href="#type-state">state()</a>) -&gt; {noreply, <a href="#type-state">state()</a>} | {noreply, <a href="#type-state">state()</a>, non_neg_integer()} | {stop, term(), <a href="#type-state">state()</a>}
</code></pre>
<br />

<a name="init-1"></a>

### init/1 ###

<pre><code>
init(X1::[non_neg_integer()]) -&gt; {ok, <a href="#type-state">state()</a>} | {ok, <a href="#type-state">state()</a>, non_neg_integer() | infinity} | ignore | {stop, term()}
</code></pre>
<br />

<a name="start_link-1"></a>

### start_link/1 ###

<pre><code>
start_link(Id::non_neg_integer()) -&gt; {ok, pid()} | ignore | {error, term()}
</code></pre>
<br />

Start plum_db_partition_worker for the partition Id and link to calling
process.

<a name="terminate-2"></a>

### terminate/2 ###

<pre><code>
terminate(Reason::term(), State::<a href="#type-state">state()</a>) -&gt; term()
</code></pre>
<br />

