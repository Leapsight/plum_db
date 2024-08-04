# CHANGELOG
## 2.0-rc.2
* Reuduce lock timeout and avoid loggin and error when object is not present during AAE


## 2.0-rc.1
* Replace `eleveldb` storage with `rocksdb`
* Added configuration option `key_encoding` that determines whether to use `sext` or `record_separator` which is not implemented at the moment.

## 1.2.0
### Bug Fixes

* Fixes a bug in `plum_db:is_stale` and `plum_db:get_object`. The latter now
returns `{ok, plum_db_object()}` and `{error, any()}`.

## 1.1.7
* Upgrade Partisan to latest

## v0.3.7


### Bug fixes
* Fixes bug when not using limit option



## v0.3.6
### New Features
* `fold` operation now supports limits and continuations

### Bug fixes
* Fixes continuations previous limitations to work only on a single partition


## v0.3.5


### Bug fixes
* Fixes a bug during AAE exchange introduced in 0.3.4 due to an API change

## v0.3.4

### New Features

* Increased throughput on reads and writes.

### Bug fixes

### Incompatible changes
None.

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
* Deprecates the use of `'undefined'` in full prefixes for the more standard and unambiguous `'_'` wildcard.