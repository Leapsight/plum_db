
-define(WILDCARD, '_').
-define(EOT, '$end_of_table').
-define(TOMBSTONE, '$deleted').
-define(ERASED, '$erased').

%% Options for term_to_binary
-define(EXT_OPTS, [{minor_version, 2}]).

-define(DATA_CHANNEL, plum_db_data).

-define(LONG_TIMEOUT, 300000). %% 5m, very long but not infinity

-define(CALL_OPTS,
    ?CALL_OPTS(?LONG_TIMEOUT)
).
-define(CALL_OPTS(Timeout),
    ?CALL_OPTS(Timeout, plum_db_config:get(data_channel))
).

-define(CALL_OPTS(Timeout, Channel), [
    {timeout, Timeout},
    {channel, Channel}
]).

-define(CAST_OPTS,
    ?CAST_OPTS(plum_db_config:get(data_channel))
).
-define(CAST_OPTS(Channel),
    [{channel, Channel}]
).

-define(MONITOR_OPTS, ?MONITOR_OPTS(plum_db_config:get(data_channel))).
-define(MONITOR_OPTS(Channel),
    [{channel, Channel}]
).

-type plum_db_prefix()          ::  {binary() | atom(), binary() | atom()}.
-type plum_db_prefix_pattern()  ::  {
                                        binary() | atom() | plum_db_wildcard(),
                                        binary() | atom() | plum_db_wildcard()
                                    }.
-type plum_db_key()             ::  any().
-type plum_db_pkey()            ::  {plum_db_prefix(), plum_db_key()}.
-type plum_db_pkey_pattern()    ::  {
                                        plum_db_prefix_pattern(),
                                        plum_db_key() | plum_db_wildcard()
                                    }.
-type plum_db_value()           ::  any().
-type plum_db_tombstone()       ::  '$deleted'.
-type plum_db_wildcard()        ::  '_'.
-type plum_db_resolver()        ::  fun((
                                        plum_db_key() | plum_db_pkey(),
                                        plum_db_value() | plum_db_tombstone()
                                        ) -> plum_db_value()
                                    ).
-type plum_db_modifier()        ::  fun((
    [plum_db_value() | plum_db_tombstone()] | undefined) ->
        plum_db_value() | no_return()
    ).
-type plum_db_object()          ::  {object, plum_db_dvvset:clock()}.
-type plum_db_context()         ::  plum_db_dvvset:vector().

-record(plum_db_broadcast, {
    pkey  :: plum_db_pkey(),
    obj   :: plum_db_object()
}).
-type plum_db_broadcast()  ::  #plum_db_broadcast{}.


