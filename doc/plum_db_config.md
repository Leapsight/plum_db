

# Module plum_db_config #
* [Description](#description)
* [Function Index](#index)
* [Function Details](#functions)

.

<a name="index"></a>

## Function Index ##


<table width="100%" border="1" cellspacing="0" cellpadding="2" summary="function index"><tr><td valign="top"><a href="#get-1">get/1</a></td><td></td></tr><tr><td valign="top"><a href="#get-2">get/2</a></td><td></td></tr><tr><td valign="top"><a href="#init-0">init/0</a></td><td>Initialises plum_db configuration.</td></tr><tr><td valign="top"><a href="#set-2">set/2</a></td><td></td></tr></table>


<a name="functions"></a>

## Function Details ##

<a name="get-1"></a>

### get/1 ###

<pre><code>
get(Key::atom() | tuple() | [atom()]) -&gt; term()
</code></pre>
<br />

<a name="get-2"></a>

### get/2 ###

<pre><code>
get(Key::atom() | tuple() | [atom()], Default::term()) -&gt; term()
</code></pre>
<br />

<a name="init-0"></a>

### init/0 ###

`init() -> any()`

Initialises plum_db configuration

<a name="set-2"></a>

### set/2 ###

<pre><code>
set(Key::atom() | tuple(), Value::term()) -&gt; ok
</code></pre>
<br />

