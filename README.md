plum_db
=====

An OTP application

Build
-----
```bash

```

```erlang
application:ensure_all_started(plum_db).
plum_db:put({foo, bar}, foo, 1).
plum_db:put({foo, bar}, bar, 2).
plum_db:put({bar, foo}, foo, 3).
plum_db:put({bar, foo}, bar, 4).
plum_db:put({bar, foo}, bar, 10).
plum_db:get({bar, foo}, bar).

application:ensure_all_started(plum_db).
plum_db:fold(fun({K, V}, Acc) -> [{K, V}|Acc] end, [], {undefined, undefined}).
```

## Cluster

On node 1:

```erlang
Peer = partisan_peer_service_manager:myself().
```

On node 2:
```erlang
partisan_peer_service:join(#{name => 'plum_db1@127.0.0.1', listen_addrs => [#{ip => {127,0,0,1}, port => 51107}]}).
partisan_peer_service:members().
```

## Sync

```erlang
dbg:tracer(), dbg:p(all,c).
dbg:tpl(plum_db_exchange_statem, '_', []).
```

## Disconnecting