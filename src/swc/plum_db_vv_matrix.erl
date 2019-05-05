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
%% @doc A version vector to track what other peers have seen of the locally
%% generated dots; we use a version vector and not a BVV, because we only care
%% for the contiguous set of dots seen by peers, to easily prune older segments
%% from plum_db_dotkeymap corresponding to keys seen by all peers.
%% @end
%% -----------------------------------------------------------------------------
-module(plum_db_vv_matrix).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.


-record(plum_db_vv_matrix, {
    a = #{}         ::  #{Key :: id() := Entry :: plum_db_vv:t()} | #{},
    b = #{}         ::  #{Key :: id() := Entry :: plum_db_vv:t()} | #{}
}).

-type t()           ::  #plum_db_vv_matrix{}.
-type id()          ::  term().
-type counter()     ::  non_neg_integer().

-export([new/0]).
-export([add_peer/3]).
-export([left_join/2]).
-export([replace_peer/3]).
-export([retire_peer/3]).
-export([update_peer/3]).
-export([update_cell/4]).
-export([min/2]).
-export([peers/1]).
-export([get/3]).
-export([reset/1]).
-export([delete_peer/2]).
-export([prune_retired_peers/3]).

-compile({no_auto_import, [min/2]}).



%% =============================================================================
%% API
%% =============================================================================



%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
-spec new() -> t().

new() ->
    #plum_db_vv_matrix{}.


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
-spec add_peer(t(), id(), [id()]) -> t().

add_peer(#plum_db_vv_matrix{a = A} = M, NewPeer, ItsPeers) ->
    Entry = lists:foldl(
        fun(Id, Acc) -> plum_db_vv:add(Acc, {Id, 0}) end,
        plum_db_vv:new(),
        [NewPeer | ItsPeers]
    ),
    M#plum_db_vv_matrix{a = maps:put(NewPeer, Entry, A)}.

%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
-spec update_peer(t(), id(), plum_db_bvv:t()) -> t().

update_peer(#plum_db_vv_matrix{a = A, b = B} = M, Peer, BVV) ->
    M#plum_db_vv_matrix{
        a = update_peer(A, Peer, BVV),
        b = update_peer(B, Peer, BVV)
    };

update_peer(Map, Peer, BVV) ->
    Fun = fun(Id, Ctxt) ->
        case plum_db_vv:is_id(Ctxt, Peer) of
            false ->
                Ctxt;
            true  ->
                Entry = plum_db_bvv:entry(BVV, Id),
                Base = plum_db_bvv_entry:base(Entry),
                plum_db_vv:add(Ctxt, {Peer, Base})
        end
    end,
    maps:map(Fun, Map).


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
-spec replace_peer(t(), id(), id()) -> t().

replace_peer(#plum_db_vv_matrix{a = A0, b = B} = M0, Old, New) ->
    A2 = case maps:is_key(Old, A0) of
        true ->
            OldPeers0 = plum_db_vv:ids(maps:get(Old, A0)),
            OldPeers = lists:delete(Old, OldPeers0),
            #plum_db_vv_matrix{a = A1, b = B} = add_peer(M0, New, OldPeers),
            maps:remove(Old, A1);
        false ->
            A0
    end,
    Fun = fun(_K, V) ->
        case maps:find(Old, V) of
            {ok, _} ->
                V2 = plum_db_vv:delete(V, Old),
                plum_db_vv:add(V2, {New, 0});
            error ->
                V
        end
    end,
    #plum_db_vv_matrix{
        a = maps:map(Fun, A2),
        b = maps:map(Fun, B)
    }.



%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
-spec retire_peer(t(), id(), id()) -> t().

retire_peer(#plum_db_vv_matrix{a = A, b = B} = M0, Old, New) ->
    case maps:find(Old, A) of
        {ok, OldEntry} ->
            B1 = maps:put(Old, OldEntry, B),
            M1 = M0#plum_db_vv_matrix{b = B1},
            replace_peer(M1, Old, New);
        error ->
            replace_peer(M0, Old, New)
    end.


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
-spec left_join(t(), t()) -> t().

left_join(#plum_db_vv_matrix{} = L, #plum_db_vv_matrix{} = R) ->
    #plum_db_vv_matrix{
        a = left_join(L#plum_db_vv_matrix.a, R#plum_db_vv_matrix.a),
        b = left_join(L#plum_db_vv_matrix.b, R#plum_db_vv_matrix.b)
    };

left_join(L, R0) ->
    %% Filter entry peers from B that are not in A
    LPeers = maps:keys(L),
    Fun = fun(Id,_) -> lists:member(Id, LPeers) end,
    R1 = maps:filter(Fun, R0),
    maps_utils:merge(fun(_, V1, V2) -> plum_db_vv:left_join(V1, V2) end, L, R1).


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
-spec update_cell(t(), id(), id(), counter()) -> t().

update_cell(#plum_db_vv_matrix{a = A0} = M, EntryId, PeerId, Counter) ->
    Top = {PeerId, Counter},
    A1 = maps:update_with(
        EntryId,
        fun(VV) -> plum_db_vv:add(VV, Top) end,
        plum_db_vv:add(plum_db_vv:new(), Top),
        A0
    ),
    M#plum_db_vv_matrix{a = A1}.


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
-spec min(t(), id()) -> counter().

min(#plum_db_vv_matrix{a = A, b = B}, Id) ->
    erlang:max(min(A, Id), min(B, Id));

min(Map, Id) ->
    case maps:find(Id, Map) of
        {ok, VV} -> plum_db_vv:min_counter(VV);
        error -> 0
    end.


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
-spec peers(t()) -> [id()].

peers(#plum_db_vv_matrix{a = A}) ->
    maps:keys(A).


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
-spec get(t(), id(), id()) -> counter().

get(#plum_db_vv_matrix{a = A}, Peer1, Peer2) ->
    case maps:find(Peer1, A) of
        {ok, VV} -> plum_db_vv:counter(VV, Peer2);
        error -> 0
    end.


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
-spec reset(t()) -> t().

reset(#plum_db_vv_matrix{a = A, b = B}) ->
    #plum_db_vv_matrix{
        a = maps:map(fun(_Id, VV) -> plum_db_vv:reset(VV) end, A),
        b = maps:map(fun(_Id, VV) -> plum_db_vv:reset(VV) end, B)
    }.


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
-spec delete_peer(t(), id()) -> t().

delete_peer(#plum_db_vv_matrix{a = A0} = M, Id) ->
    A1 = maps:remove(Id, A0),
    A2 = maps:map(fun(_Id,VV) -> plum_db_vv:delete(VV, Id) end, A1),
    M#plum_db_vv_matrix{a = A2}.


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
-spec prune_retired_peers(t(), plum_db_dotkeymap:t(), [id()]) -> t().

prune_retired_peers(#plum_db_vv_matrix{b = B0} = M, DKM, DontRemotePeers) ->
    Fun = fun(Peer, _) ->
        plum_db_dotkeymap:is_key(DKM, Peer) orelse
        lists:member(Peer, DontRemotePeers)
    end,
    B1 = maps:filter(Fun, B0),
    M#plum_db_vv_matrix{b = B1}.





%% =============================================================================
%% EUNIT
%% =============================================================================




-ifdef(TEST).

new(A, B) ->
    #plum_db_vv_matrix{a = A, b = B}.


to_map(Orddict) ->
    maps:from_list(
      orddict:to_list(
        orddict:map(fun(_K,V) when is_list(V) -> maps:from_list(orddict:to_list(V));
                       (_K,V) -> V
                    end, Orddict))).

update_test() ->
    C1 = to_map([{"a",{12,0}}, {"b",{7,0}}, {"c",{4,0}}, {"d",{5,0}}, {"e",{5,0}}, {"f",{7,10}}, {"g",{5,10}}, {"h",{5,14}}]),
    C2 = to_map([{"a",{5,14}}, {"b",{5,14}}, {"c",{50,14}}, {"d",{5,14}}, {"e",{15,0}}, {"f",{5,14}}, {"g",{7,10}}, {"h",{7,10}}]),
    M = new(),
    M1 = update_cell(M, "a", "b",4),
    M2 = update_cell(M1, "a", "c",10),
    M3 = update_cell(M2, "c", "c",2),
    M4 = update_cell(M3, "c", "c",20),
    M5 = update_cell(M4, "c", "c",15),
    M6 = update_peer(M5, "c", C1),
    M7 = update_peer(M5, "c", C2),
    M8 = update_peer(M5, "a", C1),
    M9 = update_peer(M5, "a", C2),
    M10 = update_peer(M5, "b", C1),
    M11 = update_peer(M5, "b", C2),

    N = new(
        to_map([{"c",[{"c",4},{"d",3},{"z",0}]}, {"d",[{"c",0},{"d",1},{"e",2}]}, {"z", [{"a",0},{"c",0},{"z",0}]}]),
        to_map([{"b",[{"a",2},{"b",2},{"c",3}]}])
    ),

    ?assertEqual(
        new(
            to_map([{"c",[{"c",4},{"d",3},{"z",0}]}, {"d",[{"c",0},{"d",1},{"e",2}]}, {"z", [{"a",0},{"c",0},{"z",0}]}]),
            to_map([{"b",[{"a",7},{"b",2},{"c",3}]}])
        ),
        update_peer(N,"a",C1)
    ),
    ?assertEqual( update_peer(N,"c",C2),
        new(
            to_map([{"c",[{"c",50},{"d",3},{"z",0}]}, {"d",[{"c",5},{"d",1},{"e",2}]}, {"z", [{"a",0},{"c",0},{"z",0}]}]),
            to_map([{"b",[{"a",2},{"b",2},{"c",5}]}])
        )
    ),
    ?assertEqual(new(to_map([{"a",[{"b",4}]}]), #{}), M1),
    ?assertEqual( new(to_map([{"a",[{"b",4}, {"c",10}]}]), #{}), M2),
    ?assertEqual(
        new(to_map([{"a",[{"b",4}, {"c",10}]},    {"c",[{"c",2}]}]), #{}),
        M3
    ),
    ?assertEqual(
        new(to_map([{"a",[{"b",4}, {"c",10}]},    {"c",[{"c",20}]}]), #{}),
        M4
    ),
    ?assertEqual( M4,  M5),
    ?assertEqual(
        new(to_map([{"a",[{"b",4},  {"c",12}]},   {"c",[{"c",20}]}]), #{}),
        M6
    ),
    ?assertEqual(
        new(to_map([{"a",[{"b",4},  {"c",10}]},   {"c",[{"c",50}]}]), #{}),
        M7
    ),
    ?assertEqual(
        new(to_map([{"a",[{"b",4},  {"c",10}]},   {"c",[{"c",20}]}]), #{}),
        M8
    ),
    ?assertEqual(
        new(to_map([{"a",[{"b",4},  {"c",10}]},   {"c",[{"c",20}]}]), #{}),
        M9
    ),
    ?assertEqual(
        new(to_map([{"a",[{"b",12}, {"c",10}]},   {"c",[{"c",20}]}]), #{}),
        M10
    ),
    ?assertEqual(
        new(to_map([{"a",[{"b",5},  {"c",10}]},   {"c",[{"c",20}]}]), #{}),
        M11
    ).

left_join_test() ->
    A = new(to_map([{"a",[{"b",4}, {"c",10}]}, {"c",[{"c",20}]}, {"z",[{"t1",0},{"t2",0},{"z",0}]}]), #{}),
    Z = new(to_map([{"a",[{"b",5}, {"c",8}, {"z",2}]}, {"c",[{"c",20}]}, {"z",[{"t1",0},{"t2",0},{"z",0}]}]), #{}),
    B = new(to_map([{"a",[{"b",2}, {"c",10}]}, {"b",[]}, {"c",[{"c",22}]}]), #{}),
    C = new(to_map([{"z",[{"a",1}, {"b",0}, {"z",4}]}]), #{}),
    ?assertEqual(
        new(to_map([{"a",[{"b",4},{"c",10}]}, {"c",[{"c",22}]}, {"z",[{"t1",0},{"t2",0},{"z",0}]}]), #{}),
        left_join(A,B)
    ),
    ?assertEqual(
        new(to_map([{"a",[{"b",5},{"c",10}]}, {"c",[{"c",20}]}, {"z",[{"t1",0},{"t2",0},{"z",0}]}]), #{}),
        left_join(A,Z)
    ),
    ?assertEqual(
        new(to_map([{"a",[{"b",4},{"c",10}]}, {"c",[{"c",20}]}, {"z",[{"t1",0},{"t2",0},{"z",4}]}]), #{}),
        left_join(A,C)
    ),
    ?assertEqual(
        new(to_map([{"a",[{"b",4},{"c",10}]}, {"b",[]}, {"c",[{"c",22}]}]), #{}),
        left_join(B,A)
    ),
    ?assertEqual(B, left_join(B,C)),
    ?assertEqual(C, left_join(C,A)),
    ?assertEqual(C, left_join(C,B)).


add_peers_test() ->
    M = new(),
    M1 = update_cell(M, "a", "b",4),
    M2 = update_cell(M1, "a", "c",10),
    M3 = update_cell(M2, "c", "c",2),
    M4 = update_cell(M3, "c", "c",20),
    ?assertEqual(
        add_peer(add_peer(M, "z", ["b","a"]), "l", ["z","y"]),
        add_peer(add_peer(M, "l", ["y","z"]), "z", ["a","b"])
    ),
    ?assertEqual(
        new(to_map([{"z",[{"a",0},{"b",0},{"z",0}]}]), #{}),
        add_peer(M, "z",["a","b"])
    ),
    ?assertEqual(
        new(to_map([{"a",[{"b",4}, {"c",10}]}, {"c",[{"c",20}]}, {"z",[{"t1",0},{"t2",0},{"z",0}]}]), #{}),
        add_peer(M4, "z",["t2","t1"])
    ).

min_test() ->
    M = new(),
    M1 = update_cell(M, "a", "b",4),
    M2 = update_cell(M1, "a", "c",10),
    M3 = update_cell(M2, "c", "c",2),
    M4 = update_cell(M3, "c", "c",20),
    ?assertEqual( min(M, "a"), 0),
    ?assertEqual( min(M1, "a"), 4),
    ?assertEqual( min(M1, "b"), 0),
    ?assertEqual( min(M4, "a"), 4),
    ?assertEqual( min(M4, "c"), 20),
    ?assertEqual( min(M4, "b"), 0).

peers_test() ->
    M = new(),
    M1 = update_cell(M, "a", "b",4),
    M2 = update_cell(M1, "a", "c",10),
    M3 = update_cell(M2, "c", "c",2),
    M4 = update_cell(M3, "c", "c",20),
    M5 = update_cell(M4, "c", "c",15),
    ?assertEqual( peers(M), []),
    ?assertEqual( peers(M1), ["a"]),
    ?assertEqual( peers(M5), ["a", "c"]).


get_test() ->
    M = new(),
    M1 = update_cell(M, "a", "b",4),
    M2 = update_cell(M1, "a", "c",10),
    M3 = update_cell(M2, "c", "c",2),
    M4 = update_cell(M3, "c", "c",20),
    ?assertEqual( get(M, "a", "a"), 0),
    ?assertEqual( get(M1, "a", "a"), 0),
    ?assertEqual( get(M1, "b", "a"), 0),
    ?assertEqual( get(M4, "c", "c"), 20),
    ?assertEqual( get(M4, "a", "c"), 10).

reset_test() ->
    M = new(),
    M1 = update_cell(M, "a", "b",4),
    M2 = update_cell(M1, "a", "c",10),
    M3 = update_cell(M2, "c", "c",2),
    M4 = update_cell(M3, "c", "c",20),
    ?assertEqual(M, reset(M)),
    ?assertEqual(
        new(to_map([{"a",[{"b",0}]}]), #{}),
        reset(M1)
    ),
    ?assertEqual(
        new(to_map([{"a",[{"b",0}, {"c",0}]}]), #{}),
        reset(M2)
    ),
    ?assertEqual(
        new(to_map([{"a",[{"b",0}, {"c",0}]}, {"c",[{"c",0}]}]), #{}),
        reset(M3)
    ),
    ?assertEqual(
        new(to_map([{"a",[{"b",0}, {"c",0}]}, {"c",[{"c",0}]}]), #{}),
        reset(M4)
    ).

delete_peer_test() ->
    M = new(),
    M1 = update_cell(M, "a", "b",4),
    M2 = update_cell(M1, "a", "c",10),
    M3 = update_cell(M2, "c", "c",2),
    M4 = update_cell(M3, "c", "c",20),
    ?assertEqual(new(to_map([]), #{}), delete_peer(M1, "a")),
    ?assertEqual(new(to_map([{"a",[]}]), #{}), delete_peer(M1, "b")),
    ?assertEqual(new(to_map([{"a",[{"b",4}]}]), #{}), delete_peer(M1, "c")),
    ?assertEqual(new(to_map([{"c",[{"c",20}]}]), #{}), delete_peer(M4, "a")),
    ?assertEqual(new(to_map([{"a",[{"b",4}]}]), #{}), delete_peer(M4, "c")).

replace_peer_test() ->
    A = add_peer(new(), "a", ["b","c"]),
    B = add_peer(A,     "b", ["a","c"]),
    C = add_peer(B,     "c", ["a","b"]),
    Z = new(to_map([{"a",[{"a",9},{"c",2},{"z",3}]}, {"c",[{"a",1},{"c",4},{"z",3}]}, {"z", [{"a",0},{"c",1},{"z",2}]}]), #{}),
    W = new(to_map([{"b",[{"a",9},{"b",2},{"c",3}]}, {"c",[{"b",1},{"c",4},{"d",3}]}, {"d", [{"c",0},{"d",1},{"e",2}]}]), #{}),
    ?assertEqual(
        new(to_map([{"a",[{"a",0},{"c",0},{"z",0}]}, {"c",[{"a",0},{"c",0},{"z",0}]}, {"z", [{"a",0},{"c",0},{"z",0}]}]), #{}),
        replace_peer(C,"b","z")
    ),
    ?assertEqual(
        new(to_map([{"b",[{"b",0},{"c",0},{"z",0}]}, {"c",[{"b",0},{"c",4},{"z",3}]}, {"z", [{"b",0},{"c",1},{"z",2}]}]), #{}),
        replace_peer(Z,"a","b")
    ),
    ?assertEqual(
        new(to_map([{"c",[{"c",4},{"d",3},{"z",0}]}, {"d",[{"c",0},{"d",1},{"e",2}]}, {"z", [{"a",0},{"c",0},{"z",0}]}]), #{}),
        replace_peer(W,"b","z")
    ),
    ?assertEqual(
        new(to_map([{"b",[{"b",2},{"c",3},{"z",0}]}, {"c",[{"b",1},{"c",4},{"d",3}]}, {"d", [{"c",0},{"d",1},{"e",2}]}]), #{}),
        replace_peer(W,"a","z")
    ).

retire_peer_test() ->
    A = add_peer(new(), "a", ["b","c"]),
    B = add_peer(A,     "b", ["a","c"]),
    C = add_peer(B,     "c", ["a","b"]),
    Z = new(to_map([{"a",[{"a",9},{"c",2},{"z",3}]}, {"c",[{"a",1},{"c",4},{"z",3}]}, {"z", [{"a",0},{"c",1},{"z",2}]}]), #{}),
    W = new(to_map([{"b",[{"a",9},{"b",2},{"c",3}]}, {"c",[{"b",1},{"c",4},{"d",3}]}, {"d", [{"c",0},{"d",1},{"e",2}]}]), #{}),
    ?assertEqual(
        new(to_map([{"a",[{"a",0},{"c",0},{"z",0}]}, {"c",[{"a",0},{"c",0},{"z",0}]}, {"z", [{"a",0},{"c",0},{"z",0}]}]), to_map([{"b",[{"a",0},{"c",0},{"z",0}]}])),
        retire_peer(C,"b","z")
    ),
    ?assertEqual(
        new(to_map([{"b",[{"b",0},{"c",0},{"z",0}]}, {"c",[{"b",0},{"c",4},{"z",3}]}, {"z", [{"b",0},{"c",1},{"z",2}]}]), to_map([{"a",[{"b",0},{"c",2},{"z",3}]}])),
        retire_peer(Z,"a","b")
    ),
    ?assertEqual(
        new(to_map([{"c",[{"c",4},{"d",3},{"z",0}]}, {"d",[{"c",0},{"d",1},{"e",2}]}, {"z", [{"a",0},{"c",0},{"z",0}]}]), to_map([{"b",[{"a",9},{"c",3},{"z",0}]}])),
        retire_peer(W,"b","z")
    ),
    ?assertEqual(
        new(to_map([{"b",[{"b",2},{"c",3},{"z",0}]}, {"c",[{"b",1},{"c",4},{"d",3}]}, {"d", [{"c",0},{"d",1},{"e",2}]}]), #{}),
        retire_peer(W,"a","z")
    ).

prune_retired_peers_test() ->
    D1 = [{"a",[1,2,22]}, {"b",[4,5,11]}],
    D2 = [{"a",[1,2,22]}, {"z",[4,5,11]}],
    A = new(to_map([{"a",[{"a",0},{"c",0},{"z",0}]}, {"c",[{"a",0},{"c",0},{"z",0}]}, {"z", [{"a",0},{"c",0},{"z",0}]}]), to_map([{"b",[{"a",0},{"b",0},{"c",0}]}])),
    A2 = new(to_map([{"a",[{"a",0},{"c",0},{"z",0}]}, {"c",[{"a",0},{"c",0},{"z",0}]}, {"z", [{"a",0},{"c",0},{"z",0}]}]), #{}),
    ?assertEqual(A, prune_retired_peers(A, D1, [])),
    ?assertEqual(A, prune_retired_peers(A, D1, ["a", "b","c","z"])),
    ?assertEqual(A2, prune_retired_peers(A, D2, [])),
    ?assertEqual(A, prune_retired_peers(A, D2, ["b"])),
    ?assertEqual(A2, prune_retired_peers(A, [], [])).



-endif.
