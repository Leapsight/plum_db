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

add_handler(Handler, Args) ->
    gen_event:add_handler(?MODULE, Handler, Args).

add_sup_handler(Handler, Args) ->
    gen_event:add_sup_handler(?MODULE, Handler, Args).

add_callback(Fn) when is_function(Fn) ->
    gen_event:add_handler(?MODULE, {?MODULE, make_ref()}, [Fn]).

add_sup_callback(Fn) when is_function(Fn) ->
    gen_event:add_sup_handler(?MODULE, {?MODULE, make_ref()}, [Fn]).


%% -----------------------------------------------------------------------------
%% @doc
%% Notify the event handlers of an updated object
%% @end
%% -----------------------------------------------------------------------------
update(Obj) ->
    gen_event:notify(?MODULE, {object_update, Obj}).





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