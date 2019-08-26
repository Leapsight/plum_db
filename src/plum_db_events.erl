%% =============================================================================
%%  plum_db_events.erl -
%%
%%  Copyright (c) 2017-2019 Ngineo Limited t/a Leapsight. All rights reserved.
%%
%%  Licensed under the Apache License, Version 2.0 (the "License");
%%  you may not use this file except in compliance with the License.
%%  You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%%  Unless required by applicable law or agreed to in writing, software
%%  distributed under the License is distributed on an "AS IS" BASIS,
%%  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%%  See the License for the specific language governing permissions and
%%  limitations under the License.
%% =============================================================================

-module(plum_db_events).

-behaviour(gen_event).

%% API
-export([start_link/0]).
-export([subscribe/1]).
-export([unsubscribe/1]).
-export([subscribe/2]).
-export([delete_handler/1]).
-export([delete_handler/2]).
-export([add_handler/2]).
-export([add_sup_handler/2]).
-export([add_callback/1]).
-export([add_sup_callback/1]).
-export([update/1]).
-export([notify/2]).

%% gen_event callbacks
-export([init/1]).
-export([handle_event/2]).
-export([handle_call/2]).
-export([handle_info/2]).
-export([terminate/2]).
-export([code_change/3]).

-record(state, {
    callback    :: function() | undefined
}).

%% ===================================================================
%% API functions
%% ===================================================================



start_link() ->
    case gen_event:start_link({local, ?MODULE}) of
        {ok, _} = OK ->
            %% Ads this module as an event handler.
            %% This is to implement the pubsub capabilities.
            ok = gen_event:add_handler(?MODULE, {?MODULE, pubsub}, [pubsub]),
            OK;
        Error ->
            Error
    end.


%% -----------------------------------------------------------------------------
%% @doc Adds an event handler.
%% Calls `gen_event:add_handler(?MODULE, Handler, Args)'.
%% @end
%% -----------------------------------------------------------------------------
add_handler(Handler, Args) ->
    gen_event:add_handler(?MODULE, Handler, Args).


%% -----------------------------------------------------------------------------
%% @doc Adds a supervised event handler.
%% Calls `gen_event:add_sup_handler(?MODULE, Handler, Args)'.
%% @end
%% -----------------------------------------------------------------------------
add_sup_handler(Handler, Args) ->
    gen_event:add_sup_handler(?MODULE, Handler, Args).


%% -----------------------------------------------------------------------------
%% @doc Adds a callback function.
%% The function needs to have a single argument representing the event that has
%% been fired.
%% @end
%% -----------------------------------------------------------------------------
-spec add_callback(fun((any()) -> any())) -> {ok, reference()}.

add_callback(Fn) when is_function(Fn, 1) ->
    Ref = make_ref(),
    gen_event:add_handler(?MODULE, {?MODULE, Ref}, [Fn]),
    {ok, Ref}.


%% -----------------------------------------------------------------------------
%% @doc Adds a supervised callback function.
%% The function needs to have a single argument representing the event that has
%% been fired.
%% @end
%% -----------------------------------------------------------------------------
-spec add_sup_callback(fun((any()) -> any())) -> {ok, reference()}.

add_sup_callback(Fn) when is_function(Fn, 1) ->
    Ref = make_ref(),
    gen_event:add_sup_handler(?MODULE, {?MODULE, Ref}, [Fn]),
    {ok, Ref}.


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
-spec delete_handler(module() | reference()) ->
    term() | {error, module_not_found} | {'EXIT', Reason :: term()}.

delete_handler(Handler) ->
    delete_handler(Handler, normal).


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
-spec delete_handler(module() | reference(), Args :: term()) ->
    term() | {error, module_not_found} | {'EXIT', Reason :: term()}.

delete_handler(Ref, Args) when is_reference(Ref) ->
    gen_event:delete_handler(?MODULE, {?MODULE, Ref}, Args);

delete_handler(Handler, Args) when is_atom(Handler) ->
    gen_event:delete_handler(?MODULE, Handler, Args).


%% -----------------------------------------------------------------------------
%% @doc Subscribe to events of type Event.
%% Any events published through update/1 will delivered to the calling process,
%% along with all other subscribers.
%% This function will raise an exception if you try to subscribe to the same
%% event twice from the same process.
%% This function uses plum_db_pubsub:subscribe/2.
%% @end
%% -----------------------------------------------------------------------------
-spec subscribe(term()) -> ok.

subscribe(EventType) ->
    true = plum_db_pubsub:subscribe(l, EventType),
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
subscribe(EventType, MatchSpec) ->
    true = plum_db_pubsub:subscribe_cond(l, EventType, MatchSpec),
    ok.


%% -----------------------------------------------------------------------------
%% @doc Remove subscription created using `subscribe/1,2'
%% @end
%% -----------------------------------------------------------------------------
unsubscribe(EventType) ->
    true = plum_db_pubsub:unsubscribe(l, EventType),
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
    notify(object_update, PObject).


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
notify(Event, Message) ->
    gen_event:notify(?MODULE, {Event, Message}).



%% =============================================================================
%% GEN_EVENT CALLBACKS
%% This is to support adding a fun via add_callback/1 and add_sup_callback/1
%% =============================================================================



init([pubsub]) ->
    {ok, #state{}};

init([Fn]) when is_function(Fn, 1) ->
    {ok, #state{callback = Fn}}.


handle_event({Event, Message}, #state{callback = undefined} = State) ->
    %% This is the pubsub handler instance
    %% We notify gproc conditional subscribers
    _ = plum_db_pubsub:publish_cond(l, Event, Message),
    {ok, State};

handle_event({Event, Message}, State) ->
    %% We notify callback funs
    (State#state.callback)({Event, Message}),
    {ok, State}.


handle_call(_Request, State) ->
    {ok, ok, State}.


handle_info(_Info, State) ->
    {ok, State}.


terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.