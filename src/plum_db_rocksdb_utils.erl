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
    Bucket = "bondy." ++ lists:append(
        string:replace(
            DataRoot,
            "/",
            ".",
            all
        )
    ),
    Name = Bucket,

    Credentials = [
        {access_key_id, "yinyan1097"},
        {secret_key, "yinyan1097"}
    ],
    AwsOptions =  [{endpoint_override, "127.0.0.1:19000"}, {scheme, "http"}],
    EnvOptions = [
        {credentials, Credentials},
        {aws_options, AwsOptions},
        {keep_local_sst_files, true},
        {keep_local_log_files, true},
        {create_bucket_if_missing, true}
    ],
    {ok, CloudEnv} = rocksdb:new_cloud_env(
        Bucket, "", "", Bucket, "", "", EnvOptions),

    DBOptions =  [{create_if_missing, true}, {env, CloudEnv} | Opts],
    PersistentCacheSize = 128 bsl 20, %% 128 MB.
    Res = rocksdb:open_cloud_db(Name, DBOptions, DataRoot, PersistentCacheSize),
    case Res of
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


