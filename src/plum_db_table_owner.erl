%% --------------------------------------------------------------
%% Copyright (C) Ngineo Limited 2011 - 2014. All rights reserved.
%% --------------------------------------------------------------

-module(plum_db_table_owner).
-behaviour(gen_server).

-record(state, {
}).

%% API
-export([add/2]).
-export([add_or_claim/2]).
-export([delete/1]).
-export([give_away/2]).
-export([lookup/1]).

%% SUPERVISOR CALLBACKS
-export([start_link/0]).

%% GEN_SERVER CALLBACKS
-export([init/1]).
-export([handle_call/3]).
-export([handle_cast/2]).
-export([handle_info/2]).
-export([terminate/2]).
-export([code_change/3]).


%% ====================================================================
%% API
%% ====================================================================



%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
lookup(Name) when is_atom(Name) ->
	case ets:lookup(?MODULE, Name) of
		[] ->
			false;
		[{Name, Tab}] ->
			{ok, Tab}
	end.


%% -----------------------------------------------------------------------------
%% @doc Creates a new ets table, sets itself as heir and gives it away
%% to Requester
%% @end
%% -----------------------------------------------------------------------------
add(Name, Opts)
when is_atom(Name) andalso Name =/= undefined andalso is_list(Opts) ->
  gen_server:call(?MODULE, {add, Name, Opts}).


%% -----------------------------------------------------------------------------
%% @doc If the table exists, it gives it away to Requester.
%% Otherwise, creates a new ets table, sets itself as heir and
%% gives it away to Requester.
%% @end
%% -----------------------------------------------------------------------------
add_or_claim(Name, Opts)
when is_atom(Name) andalso Name =/= undefined andalso is_list(Opts) ->
  gen_server:call(?MODULE, {add_or_claim, Name, Opts}).


%% -----------------------------------------------------------------------------
%% @doc Deletes the ets table with name Name iff the caller is the owner.
%% @end
%% -----------------------------------------------------------------------------
-spec delete(Name :: atom()) -> boolean().
delete(Name) when is_atom(Name) ->
	try ets:delete(Name) of
		true ->
  			gen_server:call(?MODULE, {delete, Name})
	catch
		_:badarg ->
			%% Not the owner
			false
	end.


%% -----------------------------------------------------------------------------
%% @doc Used by the table owner to delegate the ownership to another process.
%% NewOwner must be alive, local and not already the owner of the table.
%% @end
%% -----------------------------------------------------------------------------
-spec give_away(Name :: atom(), NewOwner :: pid()) -> boolean().

give_away(Name, NewOwner)
when is_atom(Name) andalso Name =/= undefined andalso is_pid(NewOwner) ->
	gen_server:call(?MODULE, {give_away, Name, NewOwner}).



%% ============================================================================
%% SUPERVISOR CALLBACKS
%% ============================================================================

-spec start_link() -> {ok, pid()} | ignore | {error, term()}.
start_link() ->
	gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).




%% ============================================================================
%% GEN SERVER CALLBACKS
%% ============================================================================



init([]) ->
	?MODULE = ets:new(
        ?MODULE,
        [named_table, {read_concurrency, true}, {write_concurrency, true}]),
  	{ok, #state{}}.

handle_call(stop, _From, St) ->
  {stop, normal, St};

handle_call({add, Name, Opts0}, {From, _Tag}, St) ->
  Opts1 = lists:keystore(heir, 1, Opts0, {heir, self(), []}),
  Tab = ets:new(Name, Opts1),
  ets:give_away(Tab, From, []),
  ets:insert(?MODULE, [{Name, Tab}]),
  {reply, {ok, Tab}, St};

handle_call({add_or_claim, Name, Opts0}, {From, _Tag}, St) ->
  case ets:lookup(?MODULE, Name) of
	[] ->
		Opts1 = lists:keystore(heir, 1, Opts0, {heir, self(), []}),
		Tab = ets:new(Name, Opts1),
		ets:give_away(Tab, From, []),
		ets:insert(?MODULE, [{Name, Tab}]),
		{reply, {ok, Tab}, St};
	[{Name, Tab}] ->
		ets:give_away(Tab, From, []),
		{reply, {ok, Tab}, St}
  end;

handle_call({delete, Name}, {_From, _Tag}, St) ->
	Reg = ?MODULE,
	case ets:lookup(Reg, Name) of
		[] ->
			{reply, false, St};
		[{Name, _} = Obj] ->
			true = ets:delete_object(Reg, Obj),
			{reply, true, St}
	end;


handle_call({give_away, Name, NewOwner}, {From, _Tag}, St) ->
	Reply =  case ets:lookup(?MODULE, Name) of
		[] ->
			false;
		{Name, Tab} ->
			TrueOwner = ets:info(Tab, owner),
			% If TrueOwner == self() the previous owner died
			case
				(TrueOwner == From orelse TrueOwner == self()) andalso
				is_process_alive(NewOwner) andalso
				node(self()) == node(NewOwner)
			of
				true ->
					ets:give_away(Tab, NewOwner, []);
				false ->
					% The table does not exist or belongs to another process
					false
			end
	end,
	{reply, Reply, St};

handle_call(_Request, _From, St) ->
	{reply, {error, unsupported_call}, St}.


handle_cast({'ETS-TRANSFER', _Tid, _, values_table}, St) ->
	{noreply, St};

handle_cast({'ETS-TRANSFER', _Tid, _, indices_table}, St) ->
	{noreply, St};

handle_cast(_, St) ->
	{noreply, St}.


handle_info(_Info, St) ->
	{noreply, St}.


terminate(_Reason, _State) ->
	ets:foldl(
		fun({_, Tab}, ok) -> catch ets:delete(Tab), ok end,
		ok,
        ?MODULE
    ),
	true = ets:delete(?MODULE),
  	ok.

code_change(_OldVsn, St, _Extra) ->
	{ok, St}.
