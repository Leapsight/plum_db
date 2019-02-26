-module(plum_db_SUITE).
-include_lib("common_test/include/ct.hrl").


all() ->
    [
        fold_concurrency
    ].



init_per_suite(Config) ->
    %% Pid = spawn(fun loop/0),
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


