-module(plum_db_rocksdb_utils).

-type read_options() :: [
    %% Our additions
    {first, binary()} |
    %% Actual RDB read_options
    {read_tier, rocksdb:read_tier()} |
    {verify_checksums, boolean()} |
    {fill_cache, boolean()} |
    {iterate_upper_bound, binary()} |
    {iterate_lower_bound, binary()} |
    {tailing, boolean()} |
    {total_order_seek, boolean()} |
    {prefix_same_as_start, boolean()} |
    {snapshot, rocksdb:snapshot_handle()}
].
-type fold_fun() :: fun(({Key::binary(), Value::binary()}, any()) -> any()).

-export_type([read_options/0]).
-export_type([fold_fun/0]).

-export([fold/4]).
-export([fold/5]).



%% =============================================================================
%% API
%% =============================================================================


-spec fold(DBHandle, Fun, AccIn, ReadOpts) -> AccOut when
  DBHandle :: rocksdb:db_handle(),
  Fun :: fold_fun(),
  AccIn :: rocksdb:any(),
  ReadOpts :: read_options(),
  AccOut :: any().

fold(DBHandle, Fun, Acc0, ReadOpts0) ->
    {First, ReadOpts} = take_first_action(ReadOpts0),
    {ok, Itr} = rocksdb:iterator(DBHandle, ReadOpts),
    do_fold(Itr, Fun, Acc0, First).


-spec fold(DBHandle, CFHandle, Fun, AccIn, ReadOpts) -> AccOut when
    DBHandle :: rocksdb:db_handle(),
    CFHandle :: rocksdb:cf_handle(),
    Fun :: fold_fun(),
    AccIn :: any(),
    ReadOpts :: read_options(),
    AccOut :: any().

fold(DbHandle, CFHandle, Fun, Acc0, ReadOpts0) ->
    {First, ReadOpts} = take_first_action(ReadOpts0),
    {ok, Itr} = rocksdb:iterator(DbHandle, CFHandle, ReadOpts),
    do_fold(Itr, Fun, Acc0, First).



%% =============================================================================
%% PRIVATE
%% =============================================================================


take_first_action(ReadOpts0) ->
    case lists:keytake(first, 1, ReadOpts0) of
        false ->
            {first, ReadOpts0};

        {value, {first, Bin}, ReadOpts} when is_binary(Bin) ->
            {{seek, Bin}, ReadOpts};

        {value, {first, _}, _} ->
            error(badarg)
    end.


do_fold(Itr, Fun, Acc0, IterAction) ->
    try
        fold_loop(rocksdb:iterator_move(Itr, IterAction), Itr, Fun, Acc0)
    after
        rocksdb:iterator_close(Itr)
    end.


fold_loop({error, iterator_closed}, _Itr, _Fun, Acc0) ->
  throw({iterator_closed, Acc0});

fold_loop({error, invalid_iterator}, _Itr, _Fun, Acc0) ->
  Acc0;

fold_loop({ok, K}, Itr, Fun, Acc0) ->
  Acc = Fun(K, Acc0),
  fold_loop(rocksdb:iterator_move(Itr, next), Itr, Fun, Acc);

fold_loop({ok, K, V}, Itr, Fun, Acc0) ->
  Acc = Fun({K, V}, Acc0),
  fold_loop(rocksdb:iterator_move(Itr, next), Itr, Fun, Acc).




