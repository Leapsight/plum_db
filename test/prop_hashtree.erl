-module(prop_hashtree).
-include_lib("proper/include/proper.hrl").
-include_lib("stdlib/include/assert.hrl").

%% Import the functions you’re testing if they are in another module
%% -include("my_module.hrl").

prop_sha_test() ->
    ?FORALL({Size, NumChunks}, {proper_types:integer(memory:kibibytes(1), memory:mebibytes(1)), proper_types:integer(1, 16)},
        ?FORALL(Bin, proper_types:binary(Size),
            begin
                ChunkSize = max(1, (Size div NumChunks)),
                hashtree_utils:sha(ChunkSize, Bin) =:= hashtree_utils:esha(Bin)
            end)).

prop_correct_test() ->
    ?FORALL(Objects, objects(),
        ?FORALL({MissingN1, MissingN2, DifferentN}, lengths(length(Objects)),
            begin
                {RemoteOnly, Objects2} = lists:split(MissingN1, Objects),
                {LocalOnly, Objects3} = lists:split(MissingN2, Objects2),
                {Different, Same} = lists:split(DifferentN, Objects3),

                Different2 = [{Key, mutate(Hash)} || {Key, Hash} <- Different],

                Insert = fun(Tree, Vals) ->
                    lists:foldl(fun({Key, Hash}, Acc) ->
                        hashtree:insert(Key, Hash, Acc)
                    end, Tree, Vals)
                end,

                A0 = hashtree:new({0, 0}, new_opts()),
                B0 = hashtree:new({0, 0}, new_opts()),

                [begin
                     A1 = hashtree:new({0, Id}, A0),
                     B1 = hashtree:new({0, Id}, B0),

                     A2 = Insert(A1, Same),
                     A3 = Insert(A2, LocalOnly),
                     A4 = Insert(A3, Different),

                     B2 = Insert(B1, Same),
                     B3 = Insert(B2, RemoteOnly),
                     B4 = Insert(B3, Different2),

                     A5 = hashtree:update_tree(A4),
                     B5 = hashtree:update_tree(B4),

                     Expected =
                         [{missing, Key} || {Key, _} <- RemoteOnly] ++
                         [{remote_missing, Key} || {Key, _} <- LocalOnly] ++
                         [{different, Key} || {Key, _} <- Different],

                     KeyDiff = hashtree:local_compare(A5, B5),

                     ?assertEqual(lists:usort(Expected), lists:usort(KeyDiff)),

                     %% Reconcile trees
                     A6 = Insert(A5, RemoteOnly),
                     B6 = Insert(B5, LocalOnly),
                     B7 = Insert(B6, Different),
                     A7 = hashtree:update_tree(A6),
                     B8 = hashtree:update_tree(B7),
                     ?assertEqual([], hashtree:local_compare(A7, B8)),
                     true
                 end || Id <- lists:seq(0, 10)],
                hashtree:close(A0),
                hashtree:close(B0),
                hashtree:destroy(A0),
                hashtree:destroy(B0),
                true
            end)).

prop_est_test() ->
    %% It's hard to estimate under 10000 keys
    ?FORALL(
        N,
        proper_types:integer(10000, 5000000),
        begin
            {ok, EstKeys} = hashtree:estimate_keys(
                hashtree:update_tree(
                    hashtree:insert_many(
                        N, hashtree:new({0, 0}, new_opts())
                    )
                )
            ),
            Diff = abs(N - EstKeys),
            MaxDiff = N div 5,
            ?assertEqual(true, MaxDiff > Diff),
            true
        end
    ).




%% =============================================================================
%% PRIVATE
%% =============================================================================

objects() ->
    proper_types:sized(fun(Size) -> objects(Size + 3) end).

objects(N) ->
    ?LET(Keys, shuffle(lists:seq(1, N)),
        [{hashtree_utils:bin(K), proper_types:binary(8)} || K <- Keys]
    ).

lengths(N) ->
    ?LET(MissingN1, proper_types:integer(0, N),
        ?LET(MissingN2, proper_types:integer(0, N - MissingN1),
            ?LET(DifferentN, proper_types:integer(0, N - MissingN1 - MissingN2),
                {MissingN1, MissingN2, DifferentN}))).

mutate(Binary) ->
    L1 = binary_to_list(Binary),
    [X | Xs] = L1,
    X2 = (X + 1) rem 256,
    L2 = [X2 | Xs],
    list_to_binary(L2).


shuffle(L) ->
    %% Shuffle the list by adding a random number first,
    %% then sorting on it, and then removing it
    Shuffled = lists:sort([{rand:uniform(), X} || X <- L]),
    [X || {_, X} <- Shuffled].


new_opts() ->
    new_opts([]).

new_opts(List) ->
    [{open, [{create_if_missing, true}]} | List].



insert_many(N, T1) ->
    T2 =
        lists:foldl(fun(X, TX) ->
            hashtree:insert(hashtree_utils:bin(-X), hashtree_utils:bin(X*100), TX)
                    end, T1, lists:seq(1,N)),
    T2.

