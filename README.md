pdb
=====

An OTP application

Build
-----
```bash

```

```erlang
application:ensure_all_started(pdb).
pdb:put({foo, bar}, foo, 1).
pdb:put({foo, bar}, bar, 2).
pdb:put({bar, foo}, foo, 3).
pdb:put({bar, foo}, bar, 4).
pdb:put({bar, foo}, bar, 6).
pdb:put({bar, foo}, bar).

application:ensure_all_started(pdb).
pdb:fold(fun({K, V}, Acc) -> [{K, V}|Acc] end, [], {foo, bar}).
pdb:fold(fun({K, V}, Acc) -> [{K, V}|Acc] end, [], {bar, foo}).
```

## Cluster

On node 1:

```erlang
Peer = partisan_peer_service_manager:myself().
```

On node 2:
```erlang
partisan_peer_service:join(Peer).
partisan_peer_service:members().
```