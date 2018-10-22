# CHANGELOG

## v0.2.0

### New Features

* Adds in-memory store using ets.
    * Introduces prefix types (where by prefix we mean the first element of the full_prefix) to determine which storage type to use with the following types supported:
        * `ram`: only stored on ets
        * `ram_disk`: store on ets and leveldb (automatic restores to ets from leveldb when plum_db starts up)
        * `disk`: store on disk (leveledb)
    * The list of prefix types is provided via application env (and cannot be modified in runtime at the moment) e.g. `[{foo, ram}, {bar, disk}]`.
    * By default `disk` is used i.e. if a prefix is used that has no type assigned in the provided env.
* Adds `plum_db_config` module based on mochiglobal

### Bug Fixes

* Fixes `match` and added `first` option to iterators, `fold` and `to_list` functions
* Fixes combination of `first` and `match` options
* Adds `plum_db:match/1,2,3` with `remove_tombstones` option

### Incompatible Changes

* plum_db `object_update` event now includes the Existing Object, so previous subscriptions will need to be ammended to be able to work with the new callback signature.
* Deprecates the use of `'undefined'` in full prefixes for the more standard and unambiguous `'_'` wilcard.