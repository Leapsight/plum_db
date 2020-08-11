

# Module plum_db_events #
* [Function Index](#index)
* [Function Details](#functions)

__Behaviours:__ [`gen_event`](gen_event.md).

<a name="index"></a>

## Function Index ##


<table width="100%" border="1" cellspacing="0" cellpadding="2" summary="function index"><tr><td valign="top"><a href="#add_callback-1">add_callback/1</a></td><td>Adds a callback function.</td></tr><tr><td valign="top"><a href="#add_handler-2">add_handler/2</a></td><td>Adds an event handler.</td></tr><tr><td valign="top"><a href="#add_sup_callback-1">add_sup_callback/1</a></td><td>Adds a supervised callback function.</td></tr><tr><td valign="top"><a href="#add_sup_handler-2">add_sup_handler/2</a></td><td>Adds a supervised event handler.</td></tr><tr><td valign="top"><a href="#code_change-3">code_change/3</a></td><td></td></tr><tr><td valign="top"><a href="#delete_handler-1">delete_handler/1</a></td><td></td></tr><tr><td valign="top"><a href="#delete_handler-2">delete_handler/2</a></td><td></td></tr><tr><td valign="top"><a href="#handle_call-2">handle_call/2</a></td><td></td></tr><tr><td valign="top"><a href="#handle_event-2">handle_event/2</a></td><td></td></tr><tr><td valign="top"><a href="#handle_info-2">handle_info/2</a></td><td></td></tr><tr><td valign="top"><a href="#init-1">init/1</a></td><td></td></tr><tr><td valign="top"><a href="#notify-2">notify/2</a></td><td></td></tr><tr><td valign="top"><a href="#start_link-0">start_link/0</a></td><td></td></tr><tr><td valign="top"><a href="#subscribe-1">subscribe/1</a></td><td>Subscribe to events of type Event.</td></tr><tr><td valign="top"><a href="#subscribe-2">subscribe/2</a></td><td>Subscribe conditionally to events of type Event.</td></tr><tr><td valign="top"><a href="#terminate-2">terminate/2</a></td><td></td></tr><tr><td valign="top"><a href="#unsubscribe-1">unsubscribe/1</a></td><td>Remove subscription created using <code>subscribe/1,2</code></td></tr><tr><td valign="top"><a href="#update-1">update/1</a></td><td>
Notify the event handlers, callback funs and subscribers of an updated
object.</td></tr></table>


<a name="functions"></a>

## Function Details ##

<a name="add_callback-1"></a>

### add_callback/1 ###

<pre><code>
add_callback(Fn::fun((any()) -&gt; any())) -&gt; {ok, reference()}
</code></pre>
<br />

Adds a callback function.
The function needs to have a single argument representing the event that has
been fired.

<a name="add_handler-2"></a>

### add_handler/2 ###

`add_handler(Handler, Args) -> any()`

Adds an event handler.
Calls `gen_event:add_handler(?MODULE, Handler, Args)`.

<a name="add_sup_callback-1"></a>

### add_sup_callback/1 ###

<pre><code>
add_sup_callback(Fn::fun((any()) -&gt; any())) -&gt; {ok, reference()}
</code></pre>
<br />

Adds a supervised callback function.
The function needs to have a single argument representing the event that has
been fired.

<a name="add_sup_handler-2"></a>

### add_sup_handler/2 ###

`add_sup_handler(Handler, Args) -> any()`

Adds a supervised event handler.
Calls `gen_event:add_sup_handler(?MODULE, Handler, Args)`.

<a name="code_change-3"></a>

### code_change/3 ###

`code_change(OldVsn, State, Extra) -> any()`

<a name="delete_handler-1"></a>

### delete_handler/1 ###

<pre><code>
delete_handler(Handler::module() | reference()) -&gt; term() | {error, module_not_found} | {EXIT, Reason::term()}
</code></pre>
<br />

<a name="delete_handler-2"></a>

### delete_handler/2 ###

<pre><code>
delete_handler(Ref::module() | reference(), Args::term()) -&gt; term() | {error, module_not_found} | {EXIT, Reason::term()}
</code></pre>
<br />

<a name="handle_call-2"></a>

### handle_call/2 ###

`handle_call(Request, State) -> any()`

<a name="handle_event-2"></a>

### handle_event/2 ###

`handle_event(X1, State) -> any()`

<a name="handle_info-2"></a>

### handle_info/2 ###

`handle_info(Info, State) -> any()`

<a name="init-1"></a>

### init/1 ###

`init(X1) -> any()`

<a name="notify-2"></a>

### notify/2 ###

`notify(Event, Message) -> any()`

<a name="start_link-0"></a>

### start_link/0 ###

`start_link() -> any()`

<a name="subscribe-1"></a>

### subscribe/1 ###

<pre><code>
subscribe(EventType::term()) -&gt; ok
</code></pre>
<br />

Subscribe to events of type Event.
Any events published through update/1 will delivered to the calling process,
along with all other subscribers.
This function will raise an exception if you try to subscribe to the same
event twice from the same process.
This function uses plum_db_pubsub:subscribe/2.

<a name="subscribe-2"></a>

### subscribe/2 ###

`subscribe(EventType, MatchSpec) -> any()`

Subscribe conditionally to events of type Event.
This function is similar to subscribe/2, but adds a condition in the form of
an ets match specification.
The condition is tested and a message is delivered only if the condition is
true. Specifically, the test is:
`ets:match_spec_run([Msg], ets:match_spec_compile(Cond)) == [true]`
In other words, if the match_spec returns true for a message, that message
is sent to the subscriber.
For any other result from the match_spec, the message is not sent. `Cond ==
undefined` means that all messages will be delivered, which means that
`Cond=undefined` and `Cond=[{`_',[],[true]}]' are equivalent.
This function will raise an exception if you try to subscribe to the same
event twice from the same process.
This function uses `plum_db_pubsub:subscribe_cond/2`.

<a name="terminate-2"></a>

### terminate/2 ###

`terminate(Reason, State) -> any()`

<a name="unsubscribe-1"></a>

### unsubscribe/1 ###

`unsubscribe(EventType) -> any()`

Remove subscription created using `subscribe/1,2`

<a name="update-1"></a>

### update/1 ###

`update(PObject) -> any()`

Notify the event handlers, callback funs and subscribers of an updated
object.
The message delivered to each subscriber will be of the form:
`{plum_db_event, Event, Msg}`

