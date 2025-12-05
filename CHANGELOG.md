# CHANGELOG
## 2.3.6
- Fix RocksDB configuration environment. Now the config must be pased as a PlumDB key e.g. `{plum_db, [{rocksdb, [{open, [...], {read, [...]}}]}]}`
- The new default configuration reduces the number of threads and removes compression at the bottom levels

## 2.3.5
* Fix invalid Cuttlefish Schema type introduced in 2.3.4

## 2.3.4
* Fix RocksDB configuration issues
    * Move configuration inside plum_db configuration e.g. 
      `{plum_db, [{rocksdb, [{open, [...]}, {read, [...]}]}, ...]}`
* Set more sensible RocksDB configuration defaults to avoid CPU consumption due to compaction frequency
* Added telemetry events with RocksDB statistics
* Added `plum_db_partition_server:format_stats/1`

## 2.3.3
* Upgrade to latest Partisan v5.0.3

## 2.3.2
* Upgrade to latest Partisan v5.0.2

## 2.3.1
* Bug fixes in iterator error recovery

## 2.2.1
* Upgrade to latest Partisan v5.0.1

## 2.2.0
* Fix erlang term serialization by using `deterministic` option. Due to maps encoding varying across nodes and version, pinning down `minor_version` is not enough. For hashes to be deterministic we need `deterministic` encoding.

## 2.1.3
* Upgrade RocksDB to latest

## 2.1.2
* Upgrade `utils` and added `resulto` and `memory` to app.src file
* Make sure iterators are closed during exception in hashtree module
## 2.1.1
* Fixes an issue by which a hashtree reset would shutdown the hashtree server

## 2.1.0
* Fixes to Hashtree algorithm (integrated upstream changes from Riak KV) adapted to `rocksdb` and fixed previous iterator API translation between original `eleveldb` to `rocksdb`.
* Added `rocksdb` condifuration option and provided sensitive defaults.
* Fixed Common Test suites and ported Riak's `eqc` test cases to `proper`
* Added shared write buffer and shared block cache for all used `rocksdb` instances

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