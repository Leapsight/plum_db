devrun1:
	rebar3 as node1 release && _build/node1/rel/plum_db/bin/plum_db console

devrun2:
	rebar3 as node2 release && _build/node2/rel/plum_db/bin/plum_db console

devrun3:
	rebar3r3 as node3 release && _build/node3/rel/plum_db/bin/plum_db console