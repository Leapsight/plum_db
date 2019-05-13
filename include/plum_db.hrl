-ifdef(OTP_RELEASE). %% => OTP is 21 or higher
-define(EXCEPTION(Class, Reason, Stacktrace), Class:Reason:Stacktrace).
-define(STACKTRACE(Stacktrace), Stacktrace).
-else.
-define(EXCEPTION(Class, Reason, _), Class:Reason).
-define(STACKTRACE(_), erlang:get_stacktrace()).
-endif.

-define(WILDCARD, '_').
-define(EOT, '$end_of_table').
-define(TOMBSTONE, '$deleted').

-type plum_db_prefix()          ::  {binary() | atom(), binary() | atom()}.
-type plum_db_prefix_pattern()  ::  {
                                        binary() | atom() | plum_db_wildcard(), binary() | atom() | plum_db_wildcard()
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
    [plum_db_value() | plum_db_tombstone()] | undefined) -> plum_db_value()).
-type plum_db_object()          ::  {object, dvvset:clock()}.
-type plum_db_context()         ::  dvvset:vector().

-record(plum_db_broadcast, {
    pkey  :: plum_db_pkey(),
    obj   :: plum_db_object()
}).
-type plum_db_broadcast()  ::  #plum_db_broadcast{}.
