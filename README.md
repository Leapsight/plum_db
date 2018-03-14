# plum_db

A database globally replicated via Epidemic Broadcast Trees and lasp-lang’s Partisan. An offspring of Plumtree and Partisan, a descendant of Riak Core Metadata Store.

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

Go to node 1 and run

```erlang
> plum_db_peer_service:myself().
#{name => 'plum_db1@127.0.0.1', listen_addrs => [#{ip => {127,0,0,1}, port => 51107}]}
```

Copy the result and in the other two nodes do:

```erlang
> plum_db_peer_service:join(#{name => 'plum_db1@127.0.0.1', listen_addrs => [#{ip => {127,0,0,1}, port => 51107}]}).
```

Check that the three nodes are visible in each node

```erlang
> plum_db_peer_service:members().
```

On node 1 do:

```erlang
> plum_db:put({foo, bar}, foo, 1).
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
