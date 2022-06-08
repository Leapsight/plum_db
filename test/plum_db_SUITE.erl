-module(plum_db_SUITE).
-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").

all() ->
    [
        fold_disk,
        fold_ram,
        fold_ram_disk,
        fold_match_disk,
        fold_match_ram,
        fold_match_ram_disk
        % ,
        % fold_concurrency
    ].



init_per_suite(Config) ->
    %% Pid = spawn(fun loop/0),
    {ok, Hostname} = inet:gethostname(),
    Nodename = [list_to_atom("runner@" ++ Hostname), shortnames],
    case net_kernel:start(Nodename) of
        {ok, _} ->
            ok;
        {error, {already_started, _}} ->
            ok
    end,
    application:ensure_all_started(plum_db),
    N = 15000,
    {N, Time} = insert(0, N),
    ct:pal(
        info, "Insert worker finished in ~p msecs, inserts=~p~n", [Time, N]
    ),
    Config.

end_per_suite(Config) ->
    %% T = ?config(trie, Config),
    {save_config, Config}.


fold_concurrency(_) ->
    Me = self(),
    Timeout = 5000,
    Fun = fun
        (Ref, X) when (X >= 0) and (X rem 2 =:= 0) ->
            fun() ->
                ct:pal(info, "Fold worker init", []),
                T0 = erlang:system_time(millisecond),
                Fold = fun(E, Acc) -> [E|Acc] end,
                Opts = [{resolver, lww}],
                Res = plum_db:fold(Fold, [], {foo, bar}, Opts),
                T1 = erlang:system_time(millisecond),
                Diff = T1 -T0,
                ct:pal(
                    info, "Fold worker finished in ~p msecs, results=~p~n", [Diff, length(Res)]
                ),
                Me ! promise(Ref, {Res, Diff})
            end;
        (Ref, X) ->
            fun() ->
                N = 5000,
                ct:pal(info, "Insert worker init", []),
                {N, Time} = insert(5000 * X, N),
                ct:pal(
                    info, "Insert worker finished in ~p msecs, inserts=~p~n", [Time, N]
                ),
                Me ! promise(Ref, {N, Time})
            end
    end,

    Refs = [begin
            Ref = make_ref(),
            _ = spawn(Fun(Ref, X)),
            Ref
        end || X <- lists:seq(1, 10)
    ],
    T0 = erlang:system_time(second),
    _ = [yield(Ref, Timeout) || Ref <- lists:reverse(Refs)],
    T1 = erlang:system_time(second),
    ct:pal("Test finished in ~p secs ~n", [T1 - T0]).



fold_disk(_) ->
    Prefix = {disk, disk},
    _ = [plum_db:put(Prefix, X, X) || X <- lists:seq(1, 100)],
    fold_test(Prefix),
    fold_keys_test(Prefix).


fold_ram(_) ->
    Prefix = {ram, ram},
    _ = [plum_db:put(Prefix, X, X) || X <- lists:seq(1, 100)],
    fold_test(Prefix),
    fold_keys_test(Prefix).



fold_ram_disk(_) ->
    Prefix = {ram_disk, ram_disk},
    _ = [plum_db:put(Prefix, X, X) || X <- lists:seq(1, 100)],
    fold_test(Prefix),
    fold_keys_test(Prefix).


fold_match_disk(_) ->
    Prefix = {disk, disk},
    _ = [plum_db:put(Prefix, {foo, X}, X) || X <- lists:seq(1, 100)],
    fold_match_test(Prefix),
    fold_match_keys_test(Prefix).


fold_match_ram(_) ->
    Prefix = {ram, ram},
    _ = [plum_db:put(Prefix, {foo, X}, X) || X <- lists:seq(1, 100)],
    fold_match_test(Prefix),
    fold_match_keys_test(Prefix).



fold_match_ram_disk(_) ->
    Prefix = {ram_disk, ram_disk},
    _ = [plum_db:put(Prefix, {foo, X}, X) || X <- lists:seq(1, 100)],
    fold_match_test(Prefix),
    fold_match_keys_test(Prefix).



%% =============================================================================
%% UTILS
%% =============================================================================

insert(From, N) ->
    T0 = erlang:system_time(millisecond),
    _ = [
        plum_db:put({foo, bar}, integer_to_binary(X), X)
        || X <- lists:seq(From, From + N)
    ],
    T1 = erlang:system_time(millisecond),
    {N, T1 - T0}.


-spec yield(pid() | reference(), timeout()) -> term() | {error, timeout}.
yield(Key, Timeout) when is_pid(Key); is_reference(Key) ->
    receive
        {Key, {promise_reply, Reply}} ->
            Reply
    after
        Timeout ->
            {error, timeout}
    end.



-spec promise(pid() | reference(), term()) -> {pid() | reference(), {promise_reply, term()}}.
promise(Key, Reply) ->
    {Key, {promise_reply, Reply}}.


fold_test(Prefix) ->

    Expected = [{X, X} || X <- lists:seq(1, 100)],

    ?assertEqual(
        Expected,
        plum_db:fold(
            fun({K, [V]}, Acc) -> [{K, V} | Acc] end,
            [],
            Prefix,
            []
        )
    ),

    ?assertEqual(
        Expected,
        plum_db:fold(
            fun({K, [V]}, Acc) -> [{K, V} | Acc] end,
            [],
            Prefix,
            [{keys_only, false}]
        )
    ),

    ?assertEqual(
        Expected,
        plum_db:fold(
            fun({K, V}, Acc) -> [{K, V} | Acc] end,
            [],
            Prefix,
            [{resolver, lww}]
        )
    ),

    ?assertEqual(
        [{99, 99}, {100, 100}],
        plum_db:fold(
            fun({K, V}, Acc) -> [{K, V} | Acc] end,
            [],
            Prefix,
            [{resolver, lww}, {first, 99}]
        )
    ).


fold_keys_test(Prefix) ->

    Expected = lists:seq(1, 100),

    ?assertEqual(
        Expected,
        plum_db:fold(
            fun(K, Acc) -> [K | Acc] end,
            [],
            Prefix,
            [{keys_only, true}]
        )
    ),

    ?assertEqual(
        Expected,
        plum_db:fold(
            fun(K, Acc) -> [K | Acc] end,
            [],
            Prefix,
            [{keys_only, true}, {resolver, lww}]
        )
    ),

    ?assertEqual(
        [99, 100],
        plum_db:fold(
            fun(K, Acc) -> [K | Acc] end,
            [],
            Prefix,
            [{keys_only, true}, {resolver, lww}, {first, 99}]
        )
    ).


fold_match_test(Prefix) ->

    Expected = [{{foo, X}, X} || X <- lists:seq(1, 100)],

    ?assertEqual(
        Expected,
        plum_db:fold(
            fun({K, V}, Acc) -> [{K, V} | Acc] end,
            [],
            Prefix,
            [{resolver, lww}, {match, {foo, '_'}}]
        )
    ),

    ?assertEqual(
        [{{foo, 99}, 99}, {{foo, 100}, 100}],
        plum_db:fold(
            fun({K, V}, Acc) -> [{K, V} | Acc] end,
            [],
            Prefix,
            [{resolver, lww}, {first, {foo, 99}}, {match, {foo, '_'}}]
        )
    ),

    ?assertEqual(
        [{{foo, 99}, 99}],
        plum_db:fold(
            fun({K, V}, Acc) -> [{K, V} | Acc] end,
            [],
            Prefix,
            [{resolver, lww}, {first, {foo, 99}}, {match, {foo, 99}}]
        )
    ),

    ?assertEqual(
        [],
        plum_db:fold(
            fun({K, V}, Acc) -> [{K, V} | Acc] end,
            [],
            Prefix,
            [{resolver, lww}, {match, {bar, '_'}}]
        )
    ).




fold_match_keys_test(Prefix) ->

    Expected = [{foo, X} || X <- lists:seq(1, 100)],

    ?assertEqual(
        Expected,
        plum_db:fold(
            fun(K, Acc) -> [K | Acc] end,
            [],
            Prefix,
            [
                {keys_only, true},
                {resolver, lww},
                {match, {foo, '_'}}
            ]
        )
    ),

    ?assertEqual(
        [{foo, 99}, {foo, 100}],
        plum_db:fold(
            fun(K, Acc) -> [K | Acc] end,
            [],
            Prefix,
            [
                {keys_only, true},
                {resolver, lww},
                {first, {foo, 99}},
                {match, {foo, '_'}}
            ]
        )
    ),

    ?assertEqual(
        [{foo, 99}],
        plum_db:fold(
            fun(K, Acc) -> [K | Acc] end,
            [],
            Prefix,
            [
                {keys_only, true},
                {resolver, lww},
                {first, {foo, 99}},
                {match, {foo, 99}}
            ]
        )
    ),

    ?assertEqual(
        [],
        plum_db:fold(
            fun(K, Acc) -> [K | Acc] end,
            [],
            Prefix,
            [{resolver, lww}, {match, {bar, '_'}}]
        )
    ).
