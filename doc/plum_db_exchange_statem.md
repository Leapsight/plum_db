

# Module plum_db_exchange_statem #
* [Function Index](#index)
* [Function Details](#functions)

__Behaviours:__ [`gen_statem`](gen_statem.md).

<a name="index"></a>

## Function Index ##


<table width="100%" border="1" cellspacing="0" cellpadding="2" summary="function index"><tr><td valign="top"><a href="#acquiring_locks-3">acquiring_locks/3</a></td><td></td></tr><tr><td valign="top"><a href="#callback_mode-0">callback_mode/0</a></td><td></td></tr><tr><td valign="top"><a href="#code_change-4">code_change/4</a></td><td></td></tr><tr><td valign="top"><a href="#exchanging_data-3">exchanging_data/3</a></td><td></td></tr><tr><td valign="top"><a href="#init-1">init/1</a></td><td></td></tr><tr><td valign="top"><a href="#start-2">start/2</a></td><td>Start an exchange of plum_db hashtrees between this node
and <code>Peer</code> for a given <code>Partition</code>.</td></tr><tr><td valign="top"><a href="#start_link-2">start_link/2</a></td><td></td></tr><tr><td valign="top"><a href="#terminate-3">terminate/3</a></td><td></td></tr><tr><td valign="top"><a href="#updating_hashtrees-3">updating_hashtrees/3</a></td><td></td></tr></table>


<a name="functions"></a>

## Function Details ##

<a name="acquiring_locks-3"></a>

### acquiring_locks/3 ###

`acquiring_locks(Type, Content, State) -> any()`

<a name="callback_mode-0"></a>

### callback_mode/0 ###

`callback_mode() -> any()`

<a name="code_change-4"></a>

### code_change/4 ###

`code_change(OldVsn, StateName, State, Extra) -> any()`

<a name="exchanging_data-3"></a>

### exchanging_data/3 ###

`exchanging_data(Type, Content, State) -> any()`

<a name="init-1"></a>

### init/1 ###

`init(X1) -> any()`

<a name="start-2"></a>

### start/2 ###

<pre><code>
start(Peer::node(), Opts::list() | map()) -&gt; {ok, pid()} | ignore | {error, term()}
</code></pre>
<br />

Start an exchange of plum_db hashtrees between this node
and `Peer` for a given `Partition`. `Timeout` is the number of milliseconds
the process will wait to aqcuire the remote lock or to update both trees.

<a name="start_link-2"></a>

### start_link/2 ###

<pre><code>
start_link(Peer::node(), Opts::list() | map()) -&gt; {ok, pid()} | ignore | {error, term()}
</code></pre>
<br />

<a name="terminate-3"></a>

### terminate/3 ###

`terminate(Reason, StateName, State) -> any()`

<a name="updating_hashtrees-3"></a>

### updating_hashtrees/3 ###

`updating_hashtrees(Type, Content, State) -> any()`

