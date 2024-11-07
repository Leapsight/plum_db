
REBAR = rebar3
PDB_EQWALIZER = 0
OTPVSN 			= $(shell erl -eval 'erlang:display(erlang:system_info(otp_release)), halt().' -noshell)


.PHONY: compile test xref dialyzer eqwalizer node1 node2 node3

compile-no-deps:
	${REBAR} compile

docs: compile
	${REBAR} as docs edoc

eunit:
	${REBAR} eunit

ct:
	rm -rf /tmp/plum_db/ct
	${REBAR} ct

test: xref compile eunit ct

xref: compile
	${REBAR} xref skip_deps=true

dialyzer: compile
	${REBAR} dialyzer

# This is super slow as we are invoking equalizer for each source file as
# opposed to once. We do this becuase we want to ignore modules in the otp_src
# directory but at the moment Eqwalizer does not allow that option
# eqwalizer: src/*.erl
# ifeq ($(shell expr $(OTPVSN) \> 24),1)
# 	export PARTISAN_EQWALIZER=1 && for file in $(shell ls $^ | sed 's|.*/\(.*\)\.erl|\1|'); do elp eqwalize $${file}; done
# else
# 	$(info OTPVSN is not higher than 24)
# 	$(eval override mytarget=echo "skipping eqwalizer target. Eqwalizer tool  requires OTP25 or higher")
# endif
eqwalizer:
	elp eqwalize-all


node1:
	${REBAR} as node1 release
	ERL_DIST_PORT=37781 _build/node1/rel/plum_db/bin/plum_db console

node2:
	${REBAR} as node2 release
	ERL_DIST_PORT=37782 _build/node2/rel/plum_db/bin/plum_db console

node3:
	${REBAR} as node3 release
	ERL_DIST_PORT=37783 _build/node3/rel/plum_db/bin/plum_db console


