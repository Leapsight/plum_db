-type pdb_prefix()     :: {binary(), binary()}.
-type pdb_key()        :: any().
-type pdb_pkey()       :: {pdb_prefix(), pdb_key()}.
-type pdb_value()      :: any().
-type pdb_tombstone()  :: '$deleted'.
-type pdb_resolver()   :: fun((pdb_value() | pdb_tombstone(),
                                    pdb_value() | pdb_tombstone()) -> pdb_value()).
-type pdb_modifier()   :: fun(([pdb_value() | pdb_tombstone()] | undefined) ->
                                          pdb_value()).
-type pdb_object()     :: {metadata, dvvset:clock()}.
-type pdb_context()    :: dvvset:vector().

-record(pdb_broadcast, {
    pkey  :: pdb_pkey(),
    obj   :: pdb_object()
}).
-type pdb_broadcast()  ::  #pdb_broadcast{}.
