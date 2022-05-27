%% =============================================================================
%%  plum_db_object.erl -
%%
%%  Copyright (c) 2013 Basho Technologies, Inc.  All Rights Reserved.
%%  Copyright (c) 2017-2021 Leapsight. All rights reserved.
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

-module(plum_db_object).
-include("plum_db.hrl").

-export([value/1,
         values/1,
         value_count/1,
         context/1,
         empty_context/0,
         hash/1,
         modify/4,
         reconcile/2,
         resolve/2,
         is_stale/2,
         equal_context/2]).



%% @doc returns a single value. if the object holds more than one value an error is generated
%% @see values/2
-spec value(plum_db_object()) -> plum_db_value().
value(Obj) ->
    [Value] = values(Obj),
    Value.

%% @doc returns a list of values held in the object
-spec values(plum_db_object()) -> [plum_db_value()].
values({object, Object}) ->
    [Value || {Value, _Ts} <- plum_db_dvvset:values(Object)].

%% @doc returns the number of siblings in the given object
-spec value_count(plum_db_object()) -> non_neg_integer().
value_count({object, Object}) ->
    plum_db_dvvset:size(Object).

%% @doc returns the context (opaque causal history) for the given object
-spec context(plum_db_object()) -> plum_db_context().
context({object, Object}) ->
    plum_db_dvvset:join(Object).

%% @doc returns the representation for an empty context (opaque causal history)
-spec empty_context() -> plum_db_context().
empty_context() -> [].

%% @doc returns a hash representing the objects contents
-spec hash(plum_db_object()) -> binary().
hash({object, Object}) ->
    crypto:hash(sha, term_to_binary(Object)).

%% @doc modifies a potentially existing object, setting its value and updating
%% the causual history. If a function is provided as the third argument
%% then this function also is used for conflict resolution. The difference
%% between this function and resolve/2 is that the logical clock is advanced in the
%% case of this function. Additionally, the resolution functions are slightly different.
-spec modify(plum_db_object() | undefined,
             plum_db_context(),
             plum_db_value() | plum_db_modifier(),
             term()) -> plum_db_object() | no_return().
modify(undefined, Context, Fun, ServerId) when is_function(Fun) ->
    %% Fun could raise an exception
    modify(undefined, Context, Fun(undefined), ServerId);
modify(Obj, Context, Fun, ServerId) when is_function(Fun) ->
    modify(Obj, Context, Fun(values(Obj)), ServerId);
modify(undefined, _Context, Value, ServerId) ->
    %% Ignore the context since we dont have a value, its invalid if not
    %% empty anyways, so give it a valid one
    NewRecord = plum_db_dvvset:new(timestamped_value(Value)),
    {object, plum_db_dvvset:update(NewRecord, ServerId)};
modify({object, Existing}, Context, Value, ServerId) ->
    InsertRec = plum_db_dvvset:new(Context, timestamped_value(Value)),
    {object, plum_db_dvvset:update(InsertRec, Existing, ServerId)}.

%% @doc Reconciles a remote object received during replication or anti-entropy
%% with a local object. If the remote object is an anscestor of or is equal to the local one
%% `false' is returned, otherwise the reconciled object is returned as the second
%% element of the two-tuple
-spec reconcile(plum_db_object(), plum_db_object() | undefined) ->
                       false | {true, plum_db_object()}.
reconcile(undefined, _LocalObj) ->
    false;
reconcile(RemoteObj, undefined) ->
    {true, RemoteObj};
reconcile({object, RemoteObj}, {object, LocalObj}) ->
    Less  = plum_db_dvvset:less(RemoteObj, LocalObj),
    Equal = plum_db_dvvset:equal(RemoteObj, LocalObj),
    case not (Equal or Less) of
        false -> false;
        true ->
            {true, {object, plum_db_dvvset:sync([LocalObj, RemoteObj])}}
    end.

%% @doc Resolves siblings using either last-write-wins or the provided function and returns
%% an object containing a single value. The causal history is not updated
-spec resolve(plum_db_object(), lww | fun(([plum_db_value()]) -> plum_db_value())) ->
                     plum_db_object().
resolve({object, Object}, lww) ->
    LWW = fun ({_,TS1}, {_,TS2}) -> TS1 =< TS2 end,
    {object, plum_db_dvvset:lww(LWW, Object)};
resolve({object, Existing}, Reconcile) when is_function(Reconcile) ->
    ResolveFun = fun({A, _}, {B, _}) -> timestamped_value(Reconcile(A, B)) end,
    F = fun([Value | Rest]) -> lists:foldl(ResolveFun, Value, Rest) end,
    {object, plum_db_dvvset:reconcile(F, Existing)}.

%% @doc Determines if the given context (version vector) is causually newer than
%% an existing object. If the object missing or if the context does not represent
%% an anscestor of the current key, false is returned. Otherwise, when the context
%% does represent an ancestor of the existing object or the existing object itself,
%% true is returned
-spec is_stale(plum_db_context(), plum_db_object()) -> boolean().
is_stale(_, undefined) ->
    false;
is_stale(RemoteContext, {object, Obj}) ->
    LocalContext = plum_db_dvvset:join(Obj),
    %% returns true (stale) when local context is causally newer or equal to remote context
    descends(LocalContext, RemoteContext).

descends(_, []) ->
    true;
descends(Ca, Cb) ->
    [{NodeB, CtrB} | RestB] = Cb,
    case lists:keyfind(NodeB, 1, Ca) of
        false -> false;
        {_, CtrA} ->
            (CtrA >= CtrB) andalso descends(Ca, RestB)
    end.

%% @doc Returns true if the given context and the context of the existing object are equal
-spec equal_context(plum_db_context(), plum_db_object()) -> boolean().
equal_context(Context, {object, Obj}) ->
    Context =:= plum_db_dvvset:join(Obj).

timestamped_value(Value) ->
    {Value, os:timestamp()}.