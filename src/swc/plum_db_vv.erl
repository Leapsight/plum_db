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
%% @doc A Bitmapped Version Vector, where instead of having the
%% disjointed dots represented as a set of integers, we use a
%% bitmap where the least-significant bit represents the dot immediately after
%% the dot in the first element of the pair.
%% This is a concise implementation that represents the set of consecutive dots
%% since the first write for every peer node id, while keeping the rest of the
%% dots as a separate set.
%% @end
%% -----------------------------------------------------------------------------
-module(plum_db_vv).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

-type t()           ::  #{id() => counter()}.
-type id()          ::  term().
-type counter()     ::  non_neg_integer().

-export([add/2]).
-export([ids/1]).
-export([is_id/2]).
-export([new/0]).
-export([counter/2]).
-export([delete/2]).
-export([reset/1]).
-export([filter/2]).
-export([join/2]).
-export([left_join/2]).
-export([min_id/1]).
-export([min_counter/1]).
-export([min/1]).



%% =============================================================================
%% API
%% =============================================================================



%% -----------------------------------------------------------------------------
%% @doc Returns a new empty version vector.
%% @end
%% -----------------------------------------------------------------------------
-spec new() -> t().

new() ->
    maps:new().


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
-spec ids(t()) -> [id()].

ids(VV) ->
    maps:keys(VV).


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
-spec is_id(t(), id()) -> boolean().

is_id(VV, Id) ->
    maps:is_key(Id, VV).


%% -----------------------------------------------------------------------------
%% @doc Returns the counter associated with `Id'.
%% @end
%% -----------------------------------------------------------------------------
-spec counter(t(), id()) -> counter().

counter(VV, Id) ->
    maps:get(Id, VV, 0).


%% -----------------------------------------------------------------------------
%% @doc Returns the version vector without the entry whose id component matches
%% `Id'.
%% @end
%% -----------------------------------------------------------------------------
-spec delete(t(), id()) -> t().

delete(VV, Id) ->
    maps:remove(Id, VV).


%% -----------------------------------------------------------------------------
%% @doc Resets all counters to zero.
%% @end
%% -----------------------------------------------------------------------------
-spec reset(t()) -> t().

reset(VV) ->
    maps:map(fun(_, _) -> 0 end, VV).


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
-spec add(t(), {id(), counter()}) -> t().

add(VV, {Id, Counter}) ->
    Fun = fun(X) -> erlang:max(X, Counter) end,
    maps:update_with(Id, Fun, Counter, VV).


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
-spec filter(t(), fun((id(), counter()) -> boolean())) -> t().

filter(VV, Fun) when is_function(Fun, 2) ->
    maps:filter(Fun, VV).


%% -----------------------------------------------------------------------------
%% @doc Merges two version vectors `A' and `B', to create a new version vector.
%% All the entries from both version vectors are included in the new version
%% vector. If an `id' occurs in both version vectors, erlang:max/2 is called
%% with both values to return a new value.
%% @end
%% -----------------------------------------------------------------------------
-spec join(t(), t()) -> t().

join(A, B) ->
    FunMerge = fun(_Id, Counter1, Counter2) ->
        erlang:max(Counter1, Counter2)
    end,
    maps_utils:merge(FunMerge, A, B).


%% -----------------------------------------------------------------------------
%% @doc Merges two version vectors `A' and `B', to create a new version vector.
%% All the entries from `A' and all the entries in `B' that are also in `A' are
%% included in the new version vector. If an `id' occurs in both version
%% vectors, erlang:max/2 is called with both values to return a new value.
%% @end
%% -----------------------------------------------------------------------------
-spec left_join(t(), t()) -> t().

left_join(A, B0) ->
    Peers = ids(A),
    join(A, maps:with(Peers, B0)).


%% -----------------------------------------------------------------------------
%% @doc Returns the id with the minimum counter across all the entries in
%% the version vector.
%% @end
%% -----------------------------------------------------------------------------
-spec min_id(t()) -> id() | undefined.

min_id(VV) ->
    element(1, min(VV)).


%% -----------------------------------------------------------------------------
%% @doc Returns the id with the minimum counter across all the entries in
%% the version vector.
%% @end
%% -----------------------------------------------------------------------------
-spec min_counter(t()) -> counter() | undefined.

min_counter(VV) ->
    element(2, min(VV)).


%% -----------------------------------------------------------------------------
%% @doc Returns the entry with the minimum counter across all the entries in the version
%% vector.
%% @end
%% -----------------------------------------------------------------------------
-spec min(t()) -> {id(), counter()} | undefined.

min(VV) ->
    Fun = fun
        (Id, Counter, undefined) -> {Id, Counter};
        (Id, Counter, {_, Min}) when Counter < Min -> {Id, Counter};
        (_, _, Entry) -> Entry
    end,
    maps:fold(Fun, undefined, VV).



%% =============================================================================
%% PRIVATE
%% =============================================================================






%% =============================================================================
%% EUNIT
%% =============================================================================



-ifdef(TEST).

min_id_test() ->
    A0 = #{a => 2},
    A1 = #{a => 2, b => 4, c => 4},
    A2 = #{a => 5, b => 4, c => 4},
    A3 = #{a => 4, b => 4, c => 4},
    A4 = #{a => 5, b => 14, c => 4},
    ?assertEqual( a, min_id(A0)),
    ?assertEqual( a, min_id(A1)),
    ?assertEqual( b, min_id(A2)),
    ?assertEqual( a, min_id(A3)),
    ?assertEqual( c, min_id(A4)),
    ok.

min_counter_test() ->
    A0 = #{a => 2},
    A1 = #{a => 2, b => 4, c => 4},
    A2 = #{a => 5, b => 4, c => 4},
    A3 = #{a => 4, b => 4, c => 4},
    A4 = #{a => 5, b => 14, c => 4},
    ?assertEqual( 2, min_counter(A0)),
    ?assertEqual( 2, min_counter(A1)),
    ?assertEqual( 4, min_counter(A2)),
    ?assertEqual( 4, min_counter(A3)),
    ?assertEqual( 4, min_counter(A4)),
    ok.

reset_test() ->
    E = #{},
    A0 = #{a => 2},
    A1 = #{a => 2, b => 4, c => 4},
    ?assertEqual(reset(E), #{}),
    ?assertEqual(reset(A0), #{a => 0}),
    ?assertEqual(reset(A1), #{a => 0, b => 0, c => 0}),
    ok.

delete_test() ->
    E = #{},
    A0 = #{a => 2},
    A1 = #{a => 2, b => 4, c => 4},
    ?assertEqual(delete(E, a), #{}),
    ?assertEqual(delete(A0, a), #{}),
    ?assertEqual(delete(A0, b), #{a => 2}),
    ?assertEqual(delete(A1, a), #{b => 4, c => 4}),
    ok.


join_test() ->
    A0 = #{a => 4},
    A1 = #{a => 2, b => 4, c => 4},
    A2 = #{a => 1, z => 10},
    ?assertEqual(join(A0, A1), #{a => 4, b => 4, c => 4}),
    ?assertEqual(left_join(A0, A1), A0),
    ?assertEqual(left_join(A0, A2), A0).



-endif.
