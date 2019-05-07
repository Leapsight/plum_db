%% -----------------------------------------------------------------------------
%% @doc
%% https://www.percona.com/doc/percona-server/5.7/myrocks/variables.html
%% @end
%% -----------------------------------------------------------------------------
-module(plum_db_rocksdb_utils).

-export([open/2]).




%% =============================================================================
%% API
%% =============================================================================



%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
open(DataRoot, Opts) ->
    _ = lager:debug(
        "Opening Rocksdb; data_root=~p, opts=~p", [DataRoot, Opts]),
    Retries = plum_db_config:get(store_open_retry_Limit),
    do_open(DataRoot, Opts, max(1, Retries), undefined).



%% =============================================================================
%% PRIVATE
%% =============================================================================




%% @private
do_open(_, _, 0, Reason) ->
    {error, Reason};

do_open(DataRoot, Opts, RetriesLeft, _) ->
    case rocksdb:open(DataRoot, Opts) of
        {ok, _} = OK ->
            OK;
        {error, Reason} ->
            maybe_retry(Reason, DataRoot, Opts, RetriesLeft)
    end.



%% @private
maybe_retry(
    {db_open, "IO error: lock " ++ _ = Desc} = Reason,
    DataRoot,
    Opts,
    RetriesLeft0) ->
    %% Check specifically for lock error, this can be caused if
    %% a crashed vnode takes some time to flush leveldb information
    %% out to disk.The process is gone, but the NIF resource cleanup
    %% may not have completed.
    RetriesLeft = RetriesLeft0 - 1,
    SleepFor = plum_db_config:get(store_open_retries_delay),
    _ = lager:debug(
        "Rocksdb backend retrying ~p in ~p ms; error=~s, retries_left=~p",
        [DataRoot, SleepFor, Desc, RetriesLeft]
    ),
    timer:sleep(SleepFor),
    do_open(DataRoot, Opts, RetriesLeft, Reason);


maybe_retry(
    {db_open, "Corruption " ++ _ = Desc} = Reason, DataRoot, Opts, _) ->
    _ = lager:info(
        "Starting repair of corrupted rocksdb store; "
        "data_root=~p, reason=~p",
        [DataRoot, Desc]
    ),
    _ = rocksdb:repair(DataRoot, Opts),
    _ = lager:info(
        "Finished repair of corrupted rocksdb store; "
        "data_root=~p, reason=~p",
        [DataRoot, Desc]
    ),
    do_open(DataRoot, Opts, 0, Reason);

maybe_retry(Reason, _, _, _) ->
    {error, Reason}.


