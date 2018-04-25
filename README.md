# plum_db

plum_db is database globally replicated via Epidemic Broadcast Trees and lasp-lang’s Partisan. It is an offspring of plumtree and partisan, and as such, a descendant of Riak Core Metadata Store.

## Differences with Plumtree

The original plumtree project was the result of extracting the Metadata Store from Riak Core and replacing the cluster membership state by an ORSWOT CRDT. plum_db replaces the cluster membership state with partisan's

|Feature|plum_db|plumtree|
|---|---|---|
|cluster membership state| partisan membership state which uses an AWSET | ORSWOT (riak_dt)}
|data model| Riak Core Metadata (dvvset)| Riak Core Metadata (dvvset)|
|persistence|leveldb. A key is sharded across N instances of leveldb, where N is configurable at deployment time.|Each prefix has its own ets and dets table.|
|API|A simplification of the Riak Core Metadata API. A single function to iterate over the whole database i.e. across one or all shards and across a sigle or many prefixes |Riak Core Metadata API (plumtree_metadata_manager is used to iterate over prefixes whereas plumtree_metadata is used to iterate over keys within each prefix. The API is confusing and is the result of having a store (ets + dets) per prefix.|
|active anti-entropy|Based on Riak Core Metadata AAE, uses a separate instance of leveldb to store a merkle tree on disk. Updated to use the new API and gen_statem|Based on Riak Core Metadata AAE, uses a separate instance of leveldb to store a merkle tree on disk.|
|pubsub|Based on a combination of gen_event and gproc, allowing to register a Callback module or function to be executed when an event is generated. gproc dependency allows to pattern match events using a match spec | Based gen_event, allowing to register a Callback module or function to be executed when an event is generated|


## Running a 3-node cluster

To run a three node cluster do the following in three separate shells.

```bash
$ rebar3 as dev1 run
```

```bash
$ rebar3 as dev2 run
```

```bash
$ rebar3 as dev3 run
```

Make node 2 and 3 join node 1

```erlang
plum_db2@127.0.0.1> plum_db_peer_service:join('plum_db1@127.0.0.1').
```

```erlang
plum_db3@127.0.0.1> plum_db_peer_service:join('plum_db1@127.0.0.1').
```

Check that the three nodes are visible in each node

```erlang
plum_db1@127.0.0.1> plum_db_peer_service:members().
{ok,['plum_db3@127.0.0.1','plum_db2@127.0.0.1']}
```

```erlang
plum_db2@127.0.0.1> plum_db_peer_service:members().
{ok,['plum_db3@127.0.0.1','plum_db1@127.0.0.1']}
```

```erlang
plum_db3@127.0.0.1> plum_db_peer_service:members().
{ok,['plum_db2@127.0.0.1','plum_db1@127.0.0.1']}
```

On node 1 do:

```erlang
> [plum_db:put({foo, bar}, foo, 1).
```

On node 2 do:

```erlang
> plum_db:put({foo, bar}, bar, 2).
```

On node 3 do:

```erlang
> plum_db:put({foo, bar}, foobar, 3).
```

Do the following on each node to check they now all have the three elements:

``` erlang
> plum_db:fold(fun({K, V}, Acc) -> [{K, V}|Acc] end, [], {undefined, undefined}).
```

```
[plum_db:put({foo, 3}, integer_to_binary(X), 1) || X <- lists:seq(1, 1000)].
```