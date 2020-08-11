

# Module plum_db_table_owner #
* [Function Index](#index)
* [Function Details](#functions)

__Behaviours:__ [`gen_server`](gen_server.md).

<a name="index"></a>

## Function Index ##


<table width="100%" border="1" cellspacing="0" cellpadding="2" summary="function index"><tr><td valign="top"><a href="#add-2">add/2</a></td><td>Creates a new ets table, sets itself as heir and gives it away
to Requester.</td></tr><tr><td valign="top"><a href="#add_or_claim-2">add_or_claim/2</a></td><td>If the table exists, it gives it away to Requester.</td></tr><tr><td valign="top"><a href="#code_change-3">code_change/3</a></td><td></td></tr><tr><td valign="top"><a href="#delete-1">delete/1</a></td><td>Deletes the ets table with name Name iff the caller is the owner.</td></tr><tr><td valign="top"><a href="#give_away-2">give_away/2</a></td><td>Used by the table owner to delegate the ownership to another process.</td></tr><tr><td valign="top"><a href="#handle_call-3">handle_call/3</a></td><td></td></tr><tr><td valign="top"><a href="#handle_cast-2">handle_cast/2</a></td><td></td></tr><tr><td valign="top"><a href="#handle_info-2">handle_info/2</a></td><td></td></tr><tr><td valign="top"><a href="#init-1">init/1</a></td><td></td></tr><tr><td valign="top"><a href="#lookup-1">lookup/1</a></td><td></td></tr><tr><td valign="top"><a href="#start_link-0">start_link/0</a></td><td></td></tr><tr><td valign="top"><a href="#terminate-2">terminate/2</a></td><td></td></tr></table>


<a name="functions"></a>

## Function Details ##

<a name="add-2"></a>

### add/2 ###

`add(Name, Opts) -> any()`

Creates a new ets table, sets itself as heir and gives it away
to Requester

<a name="add_or_claim-2"></a>

### add_or_claim/2 ###

`add_or_claim(Name, Opts) -> any()`

If the table exists, it gives it away to Requester.
Otherwise, creates a new ets table, sets itself as heir and
gives it away to Requester.

<a name="code_change-3"></a>

### code_change/3 ###

`code_change(OldVsn, St, Extra) -> any()`

<a name="delete-1"></a>

### delete/1 ###

<pre><code>
delete(Name::atom()) -&gt; boolean()
</code></pre>
<br />

Deletes the ets table with name Name iff the caller is the owner.

<a name="give_away-2"></a>

### give_away/2 ###

<pre><code>
give_away(Name::atom(), NewOwner::pid()) -&gt; boolean()
</code></pre>
<br />

Used by the table owner to delegate the ownership to another process.
NewOwner must be alive, local and not already the owner of the table.

<a name="handle_call-3"></a>

### handle_call/3 ###

`handle_call(Request, From, St) -> any()`

<a name="handle_cast-2"></a>

### handle_cast/2 ###

`handle_cast(X1, St) -> any()`

<a name="handle_info-2"></a>

### handle_info/2 ###

`handle_info(Info, St) -> any()`

<a name="init-1"></a>

### init/1 ###

`init(X1) -> any()`

<a name="lookup-1"></a>

### lookup/1 ###

`lookup(Name) -> any()`

<a name="start_link-0"></a>

### start_link/0 ###

<pre><code>
start_link() -&gt; {ok, pid()} | ignore | {error, term()}
</code></pre>
<br />

<a name="terminate-2"></a>

### terminate/2 ###

`terminate(Reason, State) -> any()`

