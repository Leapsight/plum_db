%% -------------------------------------------------------------------
%%
%% Copyright (c) 2017 Ngineo Limited t/a Leapsight.  All Rights Reserved.
%%
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.
%%
%% -------------------------------------------------------------------

-module(plum_db_events).

-behaviour(gen_event).

%% API
-export([start_link/0]).
-export([subscribe/1]).
-export([unsubscribe/1]).
-export([subscribe/2]).
-export([add_handler/2]).
-export([add_sup_handler/2]).
-export([add_callback/1]).
-export([add_sup_callback/1]).
-export([update/1]).

%% gen_event callbacks
-export([init/1]).
-export([handle_event/2]).
-export([handle_call/2]).
-export([handle_info/2]).
-export([terminate/2]).
-export([code_change/3]).

-record(state, {
    callback
}).

%% ===================================================================
%% API functions
%% ===================================================================

start_link() ->
    gen_event:start_link({local, ?MODULE}).

%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
add_handler(Handler, Args) ->
    gen_event:add_handler(?MODULE, Handler, Args).


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
add_sup_handler(Handler, Args) ->
    gen_event:add_sup_handler(?MODULE, Handler, Args).


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
add_callback(Fn) when is_function(Fn) ->
    gen_event:add_handler(?MODULE, {?MODULE, make_ref()}, [Fn]).


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
add_sup_callback(Fn) when is_function(Fn) ->
    gen_event:add_sup_handler(?MODULE, {?MODULE, make_ref()}, [Fn]).


%% -----------------------------------------------------------------------------
%% @doc Subscribe to events of type Event.
%% Any events published  through update/1 will delivered to the current process,
%% along with all other subscribers.
%% This function will raise an exception if you try to subscribe to the same
%% event twice from the same process.
%% This function uses plum_db_pubsub:subscribe/2.
%% @end
%% -----------------------------------------------------------------------------
subscribe(Event) ->
    true = plum_db_pubsub:subscribe(l, Event),
    ok.


%% -----------------------------------------------------------------------------
%% @doc Subscribe conditionally to events of type Event.
%% This function is similar to subscribe/2, but adds a condition in the form of
%% an ets match specification.
%% The condition is tested and a message is delivered only if the condition is
%% true. Specifically, the test is:
%% `ets:match_spec_run([Msg], ets:match_spec_compile(Cond)) == [true]'
%% In other words, if the match_spec returns true for a message, that message
%% is sent to the subscriber.
%% For any other result from the match_spec, the message is not sent. `Cond ==
%% undefined' means that all messages will be delivered, which means that
%% `Cond=undefined' and `Cond=[{'_',[],[true]}]' are equivalent.
%% This function will raise an exception if you try to subscribe to the same
%% event twice from the same process.
%% This function uses `plum_db_pubsub:subscribe_cond/2'.
%% @end
%% -----------------------------------------------------------------------------
subscribe(Event, MatchSpec) ->
    true = plum_db_pubsub:subscribe_cond(l, Event, MatchSpec),
    ok.


%% -----------------------------------------------------------------------------
%% @doc Remove subscription created using `subscribe/1,2'
%% @end
%% -----------------------------------------------------------------------------
unsubscribe(Event) ->
    true = plum_db_pubsub:unsubscribe(l, Event),
    ok.


%% -----------------------------------------------------------------------------
%% @doc
%% Notify the event handlers, callback funs and subscribers of an updated
%% object.
%% The message delivered to each subscriber will be of the form:
%% `{plum_db_event, Event, Msg}'
%% @end
%% -----------------------------------------------------------------------------
update(PObject) ->
    %% We notify gen_event handlers and callback funs
    ok = gen_event:notify(?MODULE, {object_update, PObject}),
    %% We notify gproc subscribers
    %% _ = plum_db_pubsub:publish(l, object_update, PObject),
    %% We notify gproc conditional subscribers
    _ = plum_db_pubsub:publish_cond(l, object_update, PObject),
    ok.





%% =============================================================================
%% GEN_EVENT CALLBACKS
%% This is to support adding a fun via add_callback/1 and add_sup_callback/1
%% =============================================================================


init([Fn]) ->
    {ok, #state{callback = Fn}}.

handle_event({object_update, Obj}, State) ->
    (State#state.callback)(Obj),
    {ok, State}.

handle_call(_Request, State) ->
    {ok, ok, State}.

handle_info(_Info, State) ->
    {ok, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.