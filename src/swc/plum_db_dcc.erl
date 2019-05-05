%% -----------------------------------------------------------------------------
%% Copyright (c) 2016, Ricardo Gonçalves
%% Copyright (c) 2019 Ngineo Limited t/a Leapsight. All Rights Reserved.
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
%% -----------------------------------------------------------------------------

%% -----------------------------------------------------------------------------
%% @doc A Dotted Causal Container (dcc) is a container-like data structure, in
%% the spirit of a dvvs, which stores both concurrent versions and causality
%% information for a given Key, to be used together with the node logical clock
%% ({@link plum_db_bvv}).
%%
%% The extrinsic set of dots is represented as a version vector, while
%% concurrents versions are grouped and tagged with their respective dots.
%%
%% A Dotted Causal Container (DCC for short) is a pair (I × N → V) × (I → N),
%% where the first component is a map from dots (identifier-integer pairs) to
%% values, representing a set of versions, and the second component is a
%% version vector (map from [replica node] identifiers to integers),
%% representing a set extrinsic to the collective causal past of the set of
%% versions in the first component.
%% @end
%% -----------------------------------------------------------------------------
-module(plum_db_dcc).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

-record(plum_db_dcc, {
    versions        :: versions(),
    context         :: plum_db_vv:t() %  Casual Context
}).

-type t()           ::  #plum_db_dcc{}.
-type versions()    ::  #{dot() := value()} | #{}.
-type dot()         ::  {id(), counter()}.
-type id()          ::  term().
-type counter()     ::  non_neg_integer().
-type value()       ::  any().

-export([add/3]).
-export([context/1]).
-export([discard/2]).
-export([dots/1]).
-export([fill/2]).
-export([fill/3]).
-export([new/0]).
-export([strip/2]).
-export([sync/2]).
-export([values/1]).
-export([values_count/1]).



%% =============================================================================
%% API
%% =============================================================================


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
-spec new() -> t().

new() ->
    #plum_db_dcc{
        versions = maps:new(),
        context = plum_db_vv:new()
    }.


%% -----------------------------------------------------------------------------
%% @doc Returns the dots of the concurrent versions in a dcc.
%% @end
%% -----------------------------------------------------------------------------
-spec dots(t()) -> [id()].

dots(#plum_db_dcc{versions = Versions}) ->
    maps:keys(Versions).


%% -----------------------------------------------------------------------------
%% @doc Returns the values of the concurrent versions in a dcc.
%% @end
%% -----------------------------------------------------------------------------
-spec values(t()) -> [value()].

values(#plum_db_dcc{versions = Versions}) ->
    maps:values(Versions).


%% -----------------------------------------------------------------------------
%% @doc Returns the number of siblings in the given object
%% @end
%% -----------------------------------------------------------------------------
-spec values_count(t()) -> non_neg_integer().

values_count(#plum_db_dcc{versions = Versions}) ->
    maps:size(Versions).


%% -----------------------------------------------------------------------------
%% @doc Returns causal context (a version vector) of the DCC (object) ,
%% which represents the totality of causal history for that DCC (note that the
%% dots of the concurrent versions are also included in the version vector
%% component).
%% @end
%% -----------------------------------------------------------------------------
-spec context(t()) -> plum_db_vv:t().

context(#plum_db_dcc{context = VV}) -> VV.


%% -----------------------------------------------------------------------------
%% @doc Adds to versions d a mapping from the dot (i, n) to the value x, and
%% also advances the i component of the vv v to n.
%% @end
%% -----------------------------------------------------------------------------
-spec add(t(), dot(), value()) -> t().

add(#plum_db_dcc{} = DCC, Dot, Value) ->
    Versions = DCC#plum_db_dcc.versions,
    VV = DCC#plum_db_dcc.context,
    #plum_db_dcc{
        versions = maps:put(Dot, Value, Versions),
        context = plum_db_vv:add(VV, Dot)
    }.


%% -----------------------------------------------------------------------------
%% @doc Function sync merges two dccs: it discards versions in one dcc made
%% obsolete by the other dcc’s causal history, while the version vectors are
%% merged by performing the pointwise maximum.
%% @end
%% -----------------------------------------------------------------------------
-spec sync(t(), t()) -> t().

sync(#plum_db_dcc{} = A, #plum_db_dcc{} = B) ->
    Va = A#plum_db_dcc.versions,
    Vb = B#plum_db_dcc.versions,
    Ca = A#plum_db_dcc.context,
    Cb = B#plum_db_dcc.context,

    %% Filter outdated versions
    Filter = fun({Id, Counter}, _Value) ->
        X = erlang:min(
            plum_db_vv:counter(Ca, Id), plum_db_vv:counter(Cb, Id)
        ),
        Counter > X
    end,
    Vfiltered = maps:filter(Filter, maps:merge(Va, Vb)),

    %% Get the versions that are in both DCCs
    Vboth = maps:with(dots(A), Vb),

    V = maps:merge(Vfiltered, Vboth),
    C = plum_db_vv:join(Ca, Cb),

    #plum_db_dcc{versions = V, context = C}.


%% -----------------------------------------------------------------------------
%% @doc Discards versions in DCC  which are made obsolete by a causal
%% context (a version vector) `VV', and also merges `VV' into `DCC' causal context V.
%% @end
%% -----------------------------------------------------------------------------
-spec discard(BVV :: t(), Ctxt :: plum_db_vv:t()) -> t().

discard(#plum_db_dcc{} = DCC, Ctxt) ->
    Fun = fun({Id, Counter}, _Val) ->
        Counter > plum_db_vv:counter(Ctxt, Id)
    end,

    Versions = maps:filter(Fun, DCC#plum_db_dcc.versions),
    NewCtxt = plum_db_vv:join(DCC#plum_db_dcc.context, Ctxt),
    #plum_db_dcc{versions = Versions, context = NewCtxt}.


%% -----------------------------------------------------------------------------
%% @doc Discards all entries from the vv v in a dcc that are covered by the
%% corresponding base component of the bvv c; only entries with greater
%% sequence numbers are kept. The idea is to only store dccs after stripping
%% the causality information that is already present in the node logical clock.
%% @end
%% -----------------------------------------------------------------------------
-spec strip(t(), node_clock:t()) -> any().

strip(#plum_db_dcc{} = DCC, BVV) ->
    Fun = fun(Id, Counter) ->
        Entry = plum_db_bvv:entry(BVV, Id),
        Base = plum_db_bvv_entry:base(Entry),
        Counter > Base
    end,

    Versions = DCC#plum_db_dcc.versions,
    NewCtxt = plum_db_vv:filter(DCC#plum_db_dcc.context, Fun),
    #plum_db_dcc{versions = Versions, context = NewCtxt}.


%% -----------------------------------------------------------------------------
%% @doc Adds back causality information (dots) to a stripped DCC,
%% before performing functions over it.
%% @end
%% -----------------------------------------------------------------------------
-spec fill(t(), plum_db_bvv:t()) -> t().

fill(#plum_db_dcc{} = DCC, BVV) ->
    Fun = fun(Id, Acc) ->
        Entry = plum_db_bvv:entry(BVV, Id),
        Base = plum_db_bvv_entry:base(Entry),
        plum_db_vv:add(Acc, {Id, Base})
    end,

    Versions = DCC#plum_db_dcc.versions,
    Ids = plum_db_bvv:ids(BVV),
    NewCtxt = lists:foldl(Fun, DCC#plum_db_dcc.context, Ids),
    #plum_db_dcc{versions = Versions, context = NewCtxt}.


%% -----------------------------------------------------------------------------
%% @doc Same as fill/2 but only adds entries that are elements of a list of Ids,
%% instead of adding all entries in the BVV.
%% @end
%% -----------------------------------------------------------------------------
-spec fill(t(), plum_db_bvv:t(), [id()]) -> t().

fill(#plum_db_dcc{} = DCC, BVV, Ids) ->
    Fun = fun(Id, Acc) ->
        Entry = plum_db_bvv:entry(BVV, Id),
        Base = plum_db_bvv_entry:base(Entry),
        plum_db_vv:add(Acc, {Id, Base})
    end,

    Versions = DCC#plum_db_dcc.versions,
    Selection = sets:to_list(
        sets:intersection(
            sets:from_list(plum_db_bvv:ids(BVV)),
            sets:from_list(Ids)
        )
    ),
    NewCtxt = lists:foldl(Fun, DCC#plum_db_dcc.context, Selection),
    #plum_db_dcc{versions = Versions, context = NewCtxt}.



%% =============================================================================
%% EUNIT
%% =============================================================================



-ifdef(TEST).

d1() ->
    {plum_db_dcc, #{{a,8} => "red", {b,2} => "green"} , #{} }.

d2() ->
    {plum_db_dcc, #{} , #{a => 4, b => 20} }.

d3() ->
    {
        plum_db_dcc,
        #{
            {a,1} => "black",
            {a,3} => "red",
            {b,1} => "green",
            {b,2} => "green"
        } ,
        #{a => 4, b => 7}
    }.

d4() ->
    {
        plum_db_dcc,
        #{
            {a,2} => "gray",
            {a,3} => "red",
            {a,5} => "red",
            {b,2} => "green"} ,
        #{a => 5, b => 5}
    }.
d5() ->
    {
        plum_db_dcc,
        #{{a, 5} => "gray"} ,
        #{a => 5, b => 5, c => 4}
    }.


values_test() ->
    ?assertEqual(["red", "green"], values(d1())),
    ?assertEqual([], values(d2())).

context_test() ->
    ?assertEqual(#{}, context(d1())),
    ?assertEqual(#{a => 4, b => 20}, context(d2())).

sync_test() ->
    D34 = {
        plum_db_dcc,
        #{{a, 3} => "red", {a, 5} => "red", {b, 2} => "green"},
        #{a => 5, b => 7}
    },
    ?assertEqual(d3(), sync(d3(), d3())),
    ?assertEqual(d4(), sync(d4(), d4())),
    ?assertEqual(D34, sync(d3(), d4())).


discard_test() ->
    ?assertEqual(d3(), discard(d3(), #{})),
    ?assertEqual(
        {plum_db_dcc, #{{a,3} => "red"} , #{a => 4, b => 15, c => 15}},
        discard(d3(), #{a => 2, b => 15, c => 15})
    ),
    ?assertEqual(
        {plum_db_dcc, #{} , #{a => 4, b => 15, c => 15}},
        discard(d3(), #{a => 3, b => 15, c => 15})
    ).

strip_test() ->
    ?assertEqual(
        d5(),
        strip(d5(), #{a=> {4,4}} )
    ),
    ?assertEqual(
        {plum_db_dcc, #{{a,5} => "gray"} , #{b => 5, c => 4} },
        strip(d5(), #{a=> {5,0}} )
    ),
    ?assertEqual(
        {plum_db_dcc, #{{a,5} => "gray"} , #{b => 5, c => 4} },
        strip(d5(), #{a=> {15,0}})
    ),
    ?assertEqual(
        {plum_db_dcc, #{{a, 5} => "gray"} , #{b => 5, c => 4} },
        strip(d5(), #{a=> {15, 4}, b => {1, 2}})
    ),
    ?assertEqual(
        {plum_db_dcc, #{{a,5} => "gray"} , #{a => 5, c => 4} },
        strip(d5(), #{b=> {15,4}, c => {1,2}} )
    ),
    ?assertEqual(
        {plum_db_dcc, #{{a,5} => "gray"} , #{} },
        strip(d5(), #{a=> {15,4}, b =>{15,4}, c => {5,2}} )
    ).

fill_test() ->
    ?assertEqual( fill(d5(), #{a => {4,4}} ) , d5()),
    ?assertEqual( fill(d5(), #{a => {5,0}} ) , d5()),
    ?assertEqual(
        {plum_db_dcc, #{{a,5} => "gray"} , #{a => 6, b => 5, c => 4} },
        fill(d5(), #{a => {6,0}} )
    ),
    ?assertEqual(
        {plum_db_dcc, #{{a,5} => "gray"} , #{a => 15,b => 5, c => 4} },
        fill(d5(), #{a => {15,12}} )
    ),
    ?assertEqual(
        {plum_db_dcc, #{{a,5} => "gray"} , #{a => 5, b => 15,c => 4} },
        fill(d5(), #{b => {15,12}} )
    ),
    ?assertEqual(
        {plum_db_dcc, #{{a,5} => "gray"} , #{a => 5, b => 5, c => 4, d => 15}},
        fill(d5(), #{d => {15,12}})
    ),
    ?assertEqual(
        {plum_db_dcc, #{{a,5} => "gray"}, #{a => 9, b => 5, c => 4, d => 15}},
        fill(d5(), #{a => {9,6}, d => {15,12}})
    ),
    ?assertEqual(
        {plum_db_dcc, #{{a,5} => "gray"}, #{a => 9, b => 5, c => 4}},
        fill(d5(), #{a => {9,6}, d => {15,12}}, [a])
    ),
    ?assertEqual(
        {plum_db_dcc, #{{a,5} => "gray"}, #{a => 9, b => 5, c => 4}},
        fill(d5(), #{a => {9,6}, d => {15,12}}, [b,a])
    ),
    ?assertEqual(
       {plum_db_dcc, #{{a,5} => "gray"}, #{a => 9, b => 5, c => 4, d => 15}},
       fill(d5(), #{a => {9,6}, d => {15,12}}, [d,a])
    ),
    ?assertEqual(
        d5(),
        fill(d5(), #{a => {9,6}, d => {15,12}}, [b])
    ),
    ?assertEqual(
        d5(),
        fill(d5(), #{a => {9,6}, d => {15,12}}, [f])
    ).

add3_test() ->
    ?assertEqual(
        {plum_db_dcc,
            #{{a,8} => "red", {a,11} => "purple", {b,2} => "green"} ,
            #{a => 11}
        },
        add(d1(), {a,11}, "purple")
    ),
    ?assertEqual(
        {plum_db_dcc, #{{b,11} => "purple"} , #{a => 4, b => 20} },
        add(d2(), {b,11}, "purple")
    ).

-endif.