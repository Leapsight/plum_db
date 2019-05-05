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
%% @doc An implementation of a Server Wide Logical Clock, using a Bitmapped
%% Version Vector (BVV), represents a set of known writes to keys that this
%% node is replica node of.
%%
%% Each node i has a logical clock that represents all locally known
%% writes to keys that node i replicates, including writes to those keys
%% coordinated by other replica nodes, that arrive at node i via replication or
%% anti-entropy mechanisms.
%% @end
%% -----------------------------------------------------------------------------
-module(plum_db_bvv).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

-record(plum_db_dot, {
    id              ::  id(),
    counter         ::  counter()
}).

-type t()           ::  #{id() => {id(), counter()}}.
-type counter()     ::  non_neg_integer().
-type id()          ::  term().
-type dot()         ::  #plum_db_dot{}.

-type dcc()         ::  plum_db_dcc:t().
-type entry()       ::  plum_db_bvv_entry:t().


-export([add_dot/2]).
-export([add_entry/3]).
-export([entry/2]).
-export([event/2]).
-export([merge/2]).
-export([ids/1]).
-export([is_id/2]).
-export([new/0]).
-export([normalise/1]).
-export([reset/1]).
-export([missing_dots/3]).
-export([join/2]).



%% =============================================================================
%% API
%% =============================================================================



%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
-spec new() -> t().

new() ->
    maps:new().


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
-spec ids(t()) -> list(id()).

ids(BVV) ->
    maps:keys(BVV).


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
-spec is_id(t(), id()) -> boolean().

is_id(BVV, Id) ->
    maps:is_key(Id, BVV).


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
-spec entry(t(), id()) -> entry().

entry(BVV, Id) ->
    case maps:find(Id, BVV) of
        {ok, Entry} -> Entry;
        error -> plum_db_bvv_entry:new()
    end.


%% -----------------------------------------------------------------------------
%% @doc Normalises all entries in the
%% @end
%% -----------------------------------------------------------------------------
-spec normalise(t()) -> t().

normalise(BVV) when is_map(BVV) ->
    Fun = fun(Id, VV0, Acc) ->
        case plum_db_bvv_entry:normalise(VV0) of
            {0, 0} -> Acc;
            VV1 -> maps:put(Id, VV1, Acc)
        end
    end,
    maps:fold(Fun, #{}, BVV).


%% -----------------------------------------------------------------------------
%% @doc returns a new node logical clock with only the contiguous dots from
%% clock, i.e., with the bitmaps set to zero.
%% Example: reset({a => (2, 2), . . .}) = {a => (2,0),...};
%%
%% Called `base' in the paper.
%% @end
%% -----------------------------------------------------------------------------
-spec reset(t()) -> t().

reset(BVV) when is_map(BVV) ->
    Fun = fun(_, VV) -> plum_db_bvv_entry:reset(VV) end,
    maps:map(Fun, BVV).


%% -----------------------------------------------------------------------------
%% @doc Adds all the dots in the DCC to the BVV, using the standard
%% fold higher-order function with the function add defined over BVVs.
%% @end
%% -----------------------------------------------------------------------------
-spec add_dot(t(), dcc() | dot()) -> t().

add_dot(BVV0, #plum_db_dot{id = Id, counter = Counter}) ->
    {_, BVV1} = add_dot(BVV0, Id, fun(_) -> Counter end),
    BVV1;

add_dot(BVV, DCC) ->
    Dots = plum_db_dcc:dots(DCC),
    Fun = fun(Dot, Acc) -> add_dot(Acc, Dot) end,
    lists:foldl(Fun, BVV, Dots).


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
-spec add_entry(t(), id(), entry()) -> t().

add_entry(BVV, Id, NewEntry) ->
    case plum_db_bvv_entry:is_empty(NewEntry) of
        true ->
            BVV;
        false ->
            N = plum_db_bvv_entry:base(NewEntry),
            case maps:find(Id, BVV) of
                {ok, OldEntry} ->
                    case plum_db_bvv_entry:base(OldEntry) of
                        M when M >= N -> BVV;
                        M when M < N -> maps:put(Id, NewEntry, BVV)
                    end;
                error ->
                    maps:put(Id, NewEntry, BVV)
            end
    end.


%% -----------------------------------------------------------------------------
%% @doc Takes the node logical clock `Clock' and its own node id `Id', and
%% returns a tuple with the new counter for a new write in this node and the
%% original logical clock with the new counter added as a dot.
%% Example:
%% ```erlang
%%  event(#{a := {4, 0},...}, a).
%% {5, {a => {5, 0},...}}
%% '''
%% @end
%% -----------------------------------------------------------------------------
-spec event(t(), integer()) -> {integer(), t()}.

event(BVV, Id) ->
    Fun = fun(Entry) -> plum_db_bvv_entry:base(Entry) + 1 end,
    add_dot(BVV, Id, Fun).


%% -----------------------------------------------------------------------------
%% @doc Returns the dots in clock `A' that are missing in clock `B' for the ids
%% contained in `Ids'.
%% @end
%% -----------------------------------------------------------------------------
-spec missing_dots(t(), t(), [id()]) -> t().

missing_dots(A, B, Ids) ->
    Fun = fun
        (Id, AEntry, Acc) ->
            case maps:find(Id, B) of
                {ok, BEntry} ->
                    Values = plum_db_bvv_entry:subtract(
                        AEntry, BEntry),
                    case Values of
                        [] -> Acc;
                        _ -> [{Id, Values} | Acc]
                    end;
                error ->
                    Values = plum_db_bvv_entry:values(AEntry),
                    [{Id, Values} | Acc]
            end
    end,
    maps:fold(Fun, [], maps:with(Ids, A)).


%% -----------------------------------------------------------------------------
%% @doc Merges all entries from the two BVVs.
%% @end
%% -----------------------------------------------------------------------------
-spec merge(t(), t()) -> t().

merge(A, B) ->
    Fun = fun (_Id, E1, E2) -> plum_db_bvv_entry:join(E1, E2) end,
    normalise(maps_utils:merge(Fun, A, B)).


%% -----------------------------------------------------------------------------
%% @doc Joins entries from BVV2 that are also IDs in BVV1, into BVV1.
%% @end
%% -----------------------------------------------------------------------------
-spec join(t(), t()) -> t().

join(A, B0) ->
    B1 = maps:with(ids(A), B0),
    Fun = fun(_Id, E1, E2) -> plum_db_bvv_entry:join(E1, E2) end,
    normalise(maps_utils:merge(Fun, A, B1)).



%% =============================================================================
%% PRIVATE
%% =============================================================================



%% -----------------------------------------------------------------------------
%% @private
%% @doc
%% @end
%% -----------------------------------------------------------------------------
add_dot(BVV, Id, Fun) when is_function(Fun, 1) ->
    Entry0 = entry(BVV, Id),
    Counter = Fun(Entry0),
    Entry1 = plum_db_bvv_entry:add(Entry0, Counter),
    {Counter, maps:put(Id, Entry1, BVV)}.





%% =============================================================================
%% EUNIT
%% =============================================================================



-ifdef(TEST).

norm_test() ->
    ?assertEqual(normalise(#{a => {0,0}}), #{}),
    ?assertEqual(normalise(#{a => {5,3}}), #{a => {7,0}}).

missing_dots_test() ->
    B1 = #{a => {12,0}, b => {7,0}, c => {4,0}, d => {5,0}, e => {5,0}, f => {7,10}, g => {5,10}, h => {5,14}},
    B2 = #{a => {5,14}, b => {5,14}, c => {5,14}, d => {5,14}, e => {15,0}, f => {5,14}, g => {7,10}, h => {7,10}},
    ?assertEqual(lists:sort(missing_dots(B1,B2,[])), []),
    ?assertEqual(lists:sort(missing_dots(B1,B2,[a,b,c,d,e,f,g,h])), [{a,[6,10,11,12]}, {b,[6]}, {f,[6,11]}, {h,[8]}]),
    ?assertEqual(lists:sort(missing_dots(B1,B2,[a,c,d,e,f,g,h])), [{a,[6,10,11,12]}, {f,[6,11]}, {h,[8]}]),
    ?assertEqual(lists:sort(missing_dots(#{a => {2,2}, b => {3,0}}, #{}, [a])), [{a,[1,2,4]}]),
    ?assertEqual(lists:sort(missing_dots(#{a => {2,2}, b => {3,0}}, #{}, [a,b])), [{a,[1,2,4]}, {b,[1,2,3]}]),
    ?assertEqual(missing_dots(#{}, B1, [a,b,c,d,e,f,g,h]), []).


add_dot_test() ->
    ?assertEqual(add_dot(#{a => {5, 3}}, {plum_db_dot, b, 0}), #{a => {5, 3}, b => {0,0}} ),
    ?assertEqual(add_dot(#{a => {5, 3}}, {plum_db_dot, a, 1}), #{a => {7, 0}}),
    ?assertEqual(add_dot(#{a => {5, 3}}, {plum_db_dot, a, 8}), #{a => {8, 0}}),
    ?assertEqual(add_dot(#{a => {5, 3}}, {plum_db_dot, b, 8}), #{a => {5, 3}, b => {0,128}} ).

merge_test() ->
    ?assertEqual(merge( #{a => {5,3}} , #{a => {2,4}} ), #{a => {7,0}} ),
    ?assertEqual(merge( #{a => {5,3}} , #{b => {2,4}} ), #{a => {7,0}, b => {2,4}} ),
    ?assertEqual(merge( #{a => {5,3}, c => {1,2}} , #{b => {2,4}, d => {5,3}} ),
                  #{a => {7,0}, b => {2,4}, c => {1,2}, d => {7,0}} ),
    ?assertEqual(merge( #{a => {5,3}, c => {1,2}} , #{b => {2,4}, c => {5,3}} ),
                  #{a => {7,0}, b => {2,4}, c => {7,0}}).


join_test() ->
    ?assertEqual(
        #{a => {7, 0}},
        join(#{a => {5, 3}}, #{a => {2, 4}})
    ),
    ?assertEqual(
        #{a => {7, 0}},
        join(#{a => {5, 3}}, #{b => {2, 4}})
    ),
    ?assertEqual(
        #{a => {7, 0}, c => {1, 2}},
        join(#{a => {5, 3}, c => {1, 2}} , #{b => {2, 4}, d => {5, 3}})
    ),
    ?assertEqual(
        #{a => {7,0}, c => {7,0}},
        join(#{a => {5, 3}, c => {1, 2}} , #{b => {2,4}, c => {5,3}})
    ).


reset_test() ->
    %% dbg:tracer(), dbg:p(all,c), dbg:tpl(?MODULE, '_', x),
    ?assertEqual(
        #{a => {5, 0}},
        reset(#{a => {5, 3}})
    ),
    ?assertEqual(
        #{a => {5, 0}},
        reset(#{a => {5, 2}})
    ),
    ?assertEqual(
        #{a => {5, 0}, b => {2, 0}, c => {1, 0}, d=> {5, 0}},
        reset(#{a => {5, 3}, b => {2, 4}, c => {1, 2}, d=> {5, 2}})
    ).


event_test() ->
    ?assertEqual(
        {8, #{a => {8, 0}}},
        event( #{a => {7, 0}}, a)
    ),
    ?assertEqual(
        {1, #{a => {5, 3}, b => {1, 0}}},
        event( #{a => {5, 3}}, b)
    ),
    ?assertEqual(
        {3, #{a => {5, 3}, b => {3, 0}, c => {1, 2}, d => {5, 3}}},
        event( #{a => {5, 3}, b => {2, 0}, c => {1, 2}, d => {5, 3}}, b)
    ).


add_entry_test() ->
    ?assertEqual(
        #{a => {7, 0}},
        add_entry(#{a => {7, 0}}, a, {0, 0})
    ),
    ?assertEqual(
        #{a => {7, 0}},
        add_entry(#{a => {7, 0}}, b, {0, 0})
    ),
    ?assertEqual(
        #{a => {9, 0}},
        add_entry(#{a => {7, 0}}, a, {9, 0})
    ),
    ?assertEqual(
        #{a => {90, 0}},
        add_entry(#{a => {7, 1234}}, a, {90, 0})
    ),
    ?assertEqual(
        #{a => {7, 0}, b => {9, 0}},
        add_entry(#{a => {7, 0}}, b, {9, 0})
    ).

-endif.