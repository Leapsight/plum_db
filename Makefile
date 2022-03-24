
REBAR = rebar3

.PHONY: compile test xref dialyzer node1 node2 node3

compile-no-deps:
	${REBAR} compile

docs: compile
	${REBAR} as docs edoc

test: xref compile
	${REBAR} ct

xref: compile
	${REBAR} xref skip_deps=true

dialyzer: compile
	${REBAR} dialyzer

node1:
	${REBAR} as node1 release
	ERL_DIST_PORT=37781 _build/node1/rel/plum_db/bin/plum_db console

node2:
	${REBAR} as node2 release
	ERL_DIST_PORT=37782 _build/node2/rel/plum_db/bin/plum_db console

node3:
	${REBAR} as node3 release
	ERL_DIST_PORT=37783 _build/node3/rel/plum_db/bin/plum_db console


