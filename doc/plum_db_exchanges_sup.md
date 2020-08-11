

# Module plum_db_exchanges_sup #
* [Function Index](#index)
* [Function Details](#functions)

__Behaviours:__ [`supervisor`](supervisor.md).

<a name="index"></a>

## Function Index ##


<table width="100%" border="1" cellspacing="0" cellpadding="2" summary="function index"><tr><td valign="top"><a href="#init-1">init/1</a></td><td></td></tr><tr><td valign="top"><a href="#start_exchange-2">start_exchange/2</a></td><td>Starts a new exchange provided we would not reach the limit set by the
<code>aae_concurrency</code> config parameter.</td></tr><tr><td valign="top"><a href="#start_link-0">start_link/0</a></td><td></td></tr><tr><td valign="top"><a href="#stop_exchange-1">stop_exchange/1</a></td><td></td></tr></table>


<a name="functions"></a>

## Function Details ##

<a name="init-1"></a>

### init/1 ###

`init(X1) -> any()`

<a name="start_exchange-2"></a>

### start_exchange/2 ###

<pre><code>
start_exchange(Peer::node(), Opts::list() | map()) -&gt; {ok, pid()} | {error, any()}
</code></pre>
<br />

Starts a new exchange provided we would not reach the limit set by the
`aae_concurrency` config parameter.
If the limit is reached returns the error tuple `{error, concurrency_limit}`

<a name="start_link-0"></a>

### start_link/0 ###

<pre><code>
start_link() -&gt; {ok, pid()} | ignore | {error, term()}
</code></pre>
<br />

<a name="stop_exchange-1"></a>

### stop_exchange/1 ###

`stop_exchange(Pid) -> any()`

