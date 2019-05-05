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
%% @doc An encapsulation of the BVV entry, used by {@link plum_db_bvv} module.
%% A Bitmapped Version Vector, where instead of having the
%% disjointed dots represented as a set of integers, we use a
%% bitmap where the least-significant bit represents the dot immediately after
%% the dot in the first element of the pair.
%% This is a concise implementation that represents the set of consecutive dots
%% since the first write for every peer node id, while keeping the rest of the
%% dots as a separate set.
%%
%% This is part of the implementation of the paper [Server Global Clocks](http://haslab.uminho.pt/tome/files/global_logical_clocks.pdf).
%%
%% Some of the implementation code and most of the Test cases code
%% was borrowed from Ricardo Gonçalves implementation [^1].
%%
%% [^1]: [ricardobcl/ServerWideClocks](https://github.com/ricardobcl/ServerWideClocks)
%% @end
%% -----------------------------------------------------------------------------
-module(plum_db_bvv_entry).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

-type t()           ::  {base(), bitmap()}.
%% The base component representing a downward-closed set of events,
%% with no gaps. As gaps after the base are filled, the base moves forward,
%% and thus keeps the bitmap with a reasonable size.
%% The idea is that as time passes, the base will describe most events that
%% have occurred, while the bitmap describes a relatively small set of events.
%% The base describes in fact a set of events that is extrinsic to the events
%% relevant to the node, and its progress relies on the anti-entropy algorithm.
-type base()        ::  integer().
%% The bitmap component, describing events with possible gaps, where the
%% least-significant bit represents the event after those given by the base
%% component.
-type bitmap()      ::  integer().
-type counter()     ::  non_neg_integer().

-export([add/2]).
-export([base/1]).
-export([bitmap/1]).
-export([is_empty/1]).
-export([new/0]).
-export([new/2]).
-export([normalise/1]).
-export([reset/1]).
-export([subtract/2]).
-export([values/1]).
-export([join/2]).



%% =============================================================================
%% API
%% =============================================================================


%% -----------------------------------------------------------------------------
%% @doc Returns a new version vector with base and bitmap components initialised
%% to zero.
%% @end
%% -----------------------------------------------------------------------------
new() ->
    {0, 0}.


%% -----------------------------------------------------------------------------
%% @doc Returns true if the entry is empty i.e. equals `{0, 0}'.
%% @end
%% -----------------------------------------------------------------------------
-spec is_empty(t()) -> boolean().

is_empty({0, 0}) -> true;
is_empty(_) -> false.


%% -----------------------------------------------------------------------------
%% @doc Returns a new entry with base `Base' and bitmap `Bitmap'.
%% @end
%% -----------------------------------------------------------------------------
-spec new(Base :: integer(), Bitmap :: integer()) -> t().

new(Base, Bitmap)
when is_integer(Base) andalso Base >= 0
andalso is_integer(Bitmap) andalso Bitmap >= 0 ->
    {Base, Bitmap}.


%% -----------------------------------------------------------------------------
%% @doc Normalises the version vector.
%% In other words, it removes dots from the disjointed set if they are
%% contiguous to the base, while incrementing the base by the number of dots
%% removed.
%% Example:
%% ```erlang
%% > dot:norm(2, <<0:1, 0:1, 1:1, 1:1>>).
%% {4, <<0:4>>}
%% '''
%% @end
%% -----------------------------------------------------------------------------
-spec normalise(t()) -> any().

normalise({_, Bitmap} = Dot)
when is_integer(Bitmap) andalso Bitmap rem 2 == 0 ->
    Dot;

normalise({Base, Bitmap}) ->
    normalise(Base, Bitmap).


%% -----------------------------------------------------------------------------
%% @doc Returns the counter values for the all the dots
%% represented by the pair (base, bitmap). Example: `{1, 2, 4} = values(2, 2).'.
%% @end
%% -----------------------------------------------------------------------------
-spec values(t()) -> [counter()].

values({Base, Bitmap})
when is_integer(Base) andalso Base >= 0
andalso is_integer(Bitmap) andalso Bitmap >= 0 ->
    lists:append(lists:seq(1, Base), values(Base, Bitmap, [])).


%% -----------------------------------------------------------------------------
%% @doc Returns the value for the base component.
%% @end
%% -----------------------------------------------------------------------------
-spec base(t()) -> t().

base({Val, _}) -> Val.


%% -----------------------------------------------------------------------------
%% @doc Returns the value for the bitmap component.
%% @end
%% -----------------------------------------------------------------------------
-spec bitmap(t()) -> t().

bitmap({_, Val}) -> Val.


%% -----------------------------------------------------------------------------
%% @doc Sets the dot's bitmap to zero.
%% @end
%% -----------------------------------------------------------------------------
-spec reset(t()) -> t().

reset({Base, _}) ->
    {Base, 0}.


%% -----------------------------------------------------------------------------
%% @doc Adds the counter M to the dot.
%% Example:
%% ```erlang
%% dot:add({2, 2}, 3).
%% {4, 0}
%% '''
%% @end
%% -----------------------------------------------------------------------------
-spec add(t(), counter()) -> t().

add({Base, _} = VV, M) when Base >= M ->
    normalise(VV);

add({Base, Bitmap0}, M) ->
    Bitmap1 = Bitmap0 bor (1 bsl (M - Base - 1)),
    normalise({Base, Bitmap1}).


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
-spec subtract(t(), t()) -> [counter()].

subtract({ABase, ABitmap}, {BBase, BBitmap}) when ABase > BBase ->
    Dots1 = lists:seq(BBase + 1, ABase) ++ values(ABase, ABitmap, []),
    Dots2 = values(BBase, BBitmap, []),
    ordsets:subtract(Dots1, Dots2);

subtract({ABase, ABitmap}, {BBase, BBitmap}) when ABase =< BBase ->
    Dots1 = values(ABase, ABitmap, []),
    Dots2 = lists:seq(ABase + 1, BBase) ++ values(BBase, BBitmap, []),
    ordsets:subtract(Dots1, Dots2).


%% -----------------------------------------------------------------------------
%% @doc Returns a (normalised) entry that results from the union of dots from
%% two other entries.
%% @end
%% -----------------------------------------------------------------------------
-spec join(t(), t()) -> t().

join({ABase, ABitmap}, {BBase, BBitmap}) when ABase > BBase ->
    {ABase, ABitmap bor (BBitmap bsr (ABase - BBase))};

join({ABase, ABitmap}, {BBase, BBitmap}) ->
    {BBase, BBitmap bor (ABitmap bsr (BBase - ABase))}.



%% =============================================================================
%% PRIVATE
%% =============================================================================



%% @private
normalise(Base, Bitmap) when is_integer(Bitmap) andalso Bitmap rem 2 == 0 ->
    {Base, Bitmap};

normalise(Base, Bitmap) when is_integer(Bitmap) ->
    normalise(Base + 1, Bitmap bsr 1).


%% @private
values(_, 0, Acc) ->
    lists:reverse(Acc);

values(N, Bitmap, Acc) when Bitmap rem 2 == 0 ->
    values(N + 1, Bitmap bsr 1, Acc);

values(N, Bitmap, Acc) ->
    M = N + 1,
    values(M, Bitmap bsr 1, [M | Acc]).



%% =============================================================================
%% EUNIT
%% =============================================================================



-ifdef(TEST).

add_test() ->
    ?assertEqual(add({5, 3}, 8), {8, 0}),
    ?assertEqual(add({5, 3}, 7), {7, 0}),
    ?assertEqual(add({5, 3}, 4), {7, 0}),
    ?assertEqual(add({2, 5}, 4), {5, 0}),
    ?assertEqual(add({2, 5}, 6), {3, 6}),
    ?assertEqual(add({2, 4}, 6), {2, 12}).

normalise_test() ->
    ?assertEqual(normalise({5, 3}), {7, 0}),
    ?assertEqual(normalise({5, 2}), {5, 2}).

values_test() ->
    ?assertEqual(lists:sort(values({0, 0})), lists:sort([])),
    ?assertEqual(lists:sort(values({5, 3})), lists:sort([1, 2, 3, 4, 5, 6, 7])),
    ?assertEqual(lists:sort(values({2, 5})), lists:sort([1, 2, 3, 5])).

join_test() ->
    ?assertEqual(join({5, 3}, {2, 4}), join({2, 4}, {5, 3})),
    ?assertEqual(join({5, 3}, {2, 4}), {5, 3} ),
    ?assertEqual(join({2, 2}, {3, 0}), {3, 1} ),
    ?assertEqual(join({2, 2}, {3, 1}), {3, 1} ),
    ?assertEqual(join({2, 2}, {3, 2}), {3, 3} ),
    ?assertEqual(join({2, 2}, {3, 4}), {3, 5} ),
    ?assertEqual(join({3, 2}, {1, 4}), {3, 3} ),
    ?assertEqual(join({3, 2}, {1, 16}), {3, 6} ).

subtract_test() ->
    ?assertEqual(subtract({12, 0}, {5, 14}), [6, 10, 11, 12]),
    ?assertEqual(subtract({7, 0}, {5, 14}), [6]),
    ?assertEqual(subtract({4, 0}, {5, 14}), []),
    ?assertEqual(subtract({5, 0}, {5, 14}), []),
    ?assertEqual(subtract({5, 0}, {15, 0}), []),
    ?assertEqual(subtract({7, 10}, {5, 14}), [6, 11]),
    ?assertEqual(subtract({5, 10}, {7, 10}), []),
    ?assertEqual(subtract({5, 14}, {7, 10}), [8]).

-endif.