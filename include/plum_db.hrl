-type plum_db_prefix()     :: {binary(), binary()}.
-type plum_db_key()        :: any().
-type plum_db_pkey()       :: {plum_db_prefix(), plum_db_key()}.
-type plum_db_value()      :: any().
-type plum_db_tombstone()  :: '$deleted'.
-type plum_db_resolver()   :: fun((plum_db_value() | plum_db_tombstone(),
                                    plum_db_value() | plum_db_tombstone()) -> plum_db_value()).
-type plum_db_modifier()   :: fun(([plum_db_value() | plum_db_tombstone()] | undefined) ->
                                          plum_db_value()).
-type plum_db_object()     :: {object, dvvset:clock()}.
-type plum_db_context()    :: dvvset:vector().

-record(plum_db_broadcast, {
    pkey  :: plum_db_pkey(),
    obj   :: plum_db_object()
}).
-type plum_db_broadcast()  ::  #plum_db_broadcast{}.
