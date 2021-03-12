# PlumDB

[[_TOC_]]

PlumDB is a globally replicated database using eventual consistency. It uses [Epidemic Broadcast Trees](https://www.gsd.inesc-id.pt/~ler/reports/srds07.pdf) and lasp-lang’s [Partisan](https://github.com/lasp-lang/partisan), an alternative runtime system for improved scalability and reduced latency in distributed Erlang applications.

It is an offspring of [Helium's Plumtree](https://github.com/helium/plumtree) – a descendant of [Riak Core](https://github.com/basho/riak_core)'s Metadata Store – and Partisan.

The original Plumtree project was the result of extracting the Metadata Store from Riak Core and replacing the cluster membership state by an ORSWOT CRDT.

PlumDB builds on top of Plumtree but changes its architecture offering additional features.

|Feature|PlumDB|Plumtree|
|---|---|---|
|Cluster membership state| Partisan's membership state which uses an AWSET | ORSWOT (riak_dt)|
|Data model| Riak Core Metadata (dvvset)| Riak Core Metadata (dvvset)|
|Persistence|leveldb. A key is sharded across `N` instances of a store. Stores can be in-memory (`ets`), on disk (Basho's Eleveldb i.e. Leveldb) or both. `N` is configurable at deployment time.|Each prefix has its own ets and dets table.|
|API|A simplification of the Riak Core Metadata API. A single function to iterate over the whole database i.e. across one or all shards and across a single or many prefixes. |Riak Core Metadata API (`plumtree_metadata_manager`) is used to iterate over prefixes whereas `plumtree_metadata` is used to iterate over keys within each prefix. The API is confusing and is the result of having a store (ets + dets) per prefix.|
|Active anti-entropy|Based on Riak Core Metadata AAE, uses a separate instance of leveldb to store a merkle tree on disk. Updated to use the new API and gen_statem|Based on Riak Core Metadata AAE, uses a separate instance of leveldb to store a merkle tree on disk.|
|Pubsub|Based on a combination of gen_event and [gproc](https://github.com/uwiger/gproc), allowing to register a Callback module or function to be executed when an event is generated. gproc dependency allows to pattern match events using a match spec | Based on gen_event, allowing to register a Callback module or function to be executed when an event is generated|

## Installation

You will use PlumDB as a dependency in your Erlang application.

### Configuration

PlumDB is configured using the standard Erlang sys.config.

The following is an example configuration:

```erlang
{plum_db, [
    {aae_enabled, true},
    {store_open_retries_delay, 2000},
    {store_open_retry_Limit, 30},
    {data_exchange_timeout, 60000},
    {hashtree_timer, 10000},
    {data_dir, "data"},
    {partitions, 8},
    {prefixes, [
        {foo, ram},
        {bar, ram_disk},
        {<<"baz">>, disk}
    ]}
]}
```

* `partitions` (integer) – the number of shards.
* `prefixes` – a list of `{Prefix, prefix_type()}`
  * Prefix is a user defined atom or binary
  * `prefix_type()` is one of `ram`, `ram_disk` and `disk`.
* `aae_enabled` (boolean) – whether the Active Anti-Entropy mechanism is enabled.
* `store_open_retries_delay` (milliseconds) – controls thre underlying disk store (leveldb) delay between open retries.
* `store_open_retry_Limit` (integer) – controls thre underlying disk store (leveldb) open retry limit
* `data_exchange_timeout` (milliseconds) – the timeout for the AAE workers
* `hashtree_timer` (seconds) –

At the moment additional configuration is required for Partisan and Plumtree
dependencies:

```erlang
{partisan, [
    {peer_port, 18086}, % port for inter-node communication
    {parallelism, 4} % number of tcp connections
]}
```

```erlang
{plumtree, [
    {broadcast_exchange_timer, 60000} % Perform AAE exchange every 1 min.
]}
```

## Usage

Learn more by reading the source code [Documentation](https://gitlab.com/leapsight/plum_db/-/blob/master/DOCS.md).

## Standalone testing

We have three rebar3 release profiles that you can use for testing PlumDB itself.

### Running a 3-node cluster

To run a three node cluster do the following in three separate shells.

In shell #1:

```bash
$ rebar3 as dev1 run
```

In shell #2:

```bash
$ rebar3 as dev2 run
```

In shell #3:

```bash
$ rebar3 as dev3 run
```

Make node 2 and 3 join node 1

In node #2:

```erlang
> Peer = plum_db_peer_service:peer('plum_db1@127.0.0.1', {{127,0,0,1}, 18086}).
> plum_db_peer_service:join(Peer).
```

In node #3:

```erlang
> Peer = plum_db_peer_service:peer('plum_db1@127.0.0.1', {{127,0,0,1}, 18086}).
> plum_db_peer_service:join(Peer).
```

Check that the other two nodes are visible in each node

In node #1:

```erlang
> plum_db_peer_service:members().
{ok,['plum_db3@127.0.0.1','plum_db2@127.0.0.1']}
```

In node #2:

```erlang
> plum_db_peer_service:members().
{ok,['plum_db3@127.0.0.1','plum_db1@127.0.0.1']}
```

In node #3:

```erlang
> plum_db_peer_service:members().
{ok,['plum_db2@127.0.0.1','plum_db1@127.0.0.1']}
```

In node #1:

```erlang
> [plum_db:put({foo, a}, x, 1).
ok
```

In node #2:

```erlang
> plum_db:put({foo, a}, y, 2).
ok
```

In node #3:

```erlang
> plum_db:put({foo, a}, z, 3).
ok
```

Do the following on each node to check they now all have the three elements:

``` erlang
> plum_db:fold(fun(Tuple, Acc) -> [Tuple|Acc] end, [], {'_', '_'}).
[{x,1},{y,2},{z,3}]
```

We are folding over the whole database (all shards) using the full prefix wildcard `{'_', '_'}`.

The following are examples of prefix wildcards:

* `{'_', '_'}` - matches all full prefixes
* `{foo, '_'}` - matches all subprefixes of Prefix `foo`
* `{foo, x}` - matches the subprefix `x` of prefix `foo`

> Notice that the pattern `{'_', bar}` is NOT allowed.
