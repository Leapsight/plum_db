%% -----------------------------------------------------------------------------
%%    Copyright 2018 Ngineo Limited t/a Leapsight
%%
%%    Licensed under the Apache License, Version 2.0 (the "License");
%%    you may not use this file except in compliance with the License.
%%    You may obtain a copy of the License at
%%
%%        http://www.apache.org/licenses/LICENSE-2.0
%%
%%    Unless required by applicable law or agreed to in writing, software
%%    distributed under the License is distributed on an "AS IS" BASIS,
%%    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%%    See the License for the specific language governing permissions and
%%    limitations under the License.
%% -----------------------------------------------------------------------------

%% -----------------------------------------------------------------------------
%% @doc  A wrapper for an elevelb instance.
%% @end
%% -----------------------------------------------------------------------------
-module(plum_db_partition_server).
-behaviour(gen_server).


%% leveldb uses $\0 but since external term format will contain nulls
%% we need an additional separator. We use the ASCII unit separator
%% ($\31) that was design to separate fields of a record.
%% -define(KEY_SEPARATOR, <<0, $\31, 0>>).

-record(state, {
    partition                           ::  non_neg_integer(),
    db_ref 								::	eleveldb:db_ref() | undefined,
	config = []							::	opts(),
	data_root							::	file:filename(),
	open_opts = []						::	opts(),
	read_opts = []						::	opts(),
    write_opts = []						::	opts(),
    fold_opts = [{fill_cache, false}]	::	opts(),
    iterators = []                      ::  iterators()
}).


-type opts() 				            :: 	[{atom(), term()}].
-type iterator()                        ::  {reference(), eleveldb:itr_ref()}.
-type iterators()                       ::  [iterator()].
-type iterator_action()                 ::  first
                                            | last | next | prev
                                            | prefetch | prefetch_stop
                                            | binary().

-export_type([iterator/0]).

-export([byte_size/1]).
-export([delete/1]).
-export([delete/2]).
-export([get/1]).
-export([get/2]).
-export([is_empty/1]).
-export([iterator/1]).
-export([iterator_close/2]).
-export([iterator_move/2]).
-export([key_iterator/1]).
-export([name/1]).
-export([put/2]).
-export([put/3]).
-export([start_link/2]).



%% GEN_SERVER CALLBACKS
-export([init/1]).
-export([handle_call/3]).
-export([handle_cast/2]).
-export([handle_info/2]).
-export([terminate/2]).
-export([code_change/3]).



%% =============================================================================
%% API
%% =============================================================================


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
-spec start_link(Partition :: non_neg_integer(), Opts :: opts()) -> any().

start_link(Partition, Opts) ->
    Name = name(Partition),
    gen_server:start_link({local, Name}, ?MODULE, [Partition, Opts], []).


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
%% @private
name(Partition) ->
    list_to_atom(
        "plum_db_partition_" ++ integer_to_list(Partition) ++ "_server").


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
get(Key) ->
    get(name(plum_db:get_partition(Key)), Key).


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
get(Partition, Key) when is_integer(Partition) ->
    get(name(Partition), Key);

get(Name, Key) when is_atom(Name) ->
    gen_server:call(Name, {get, Key}, infinity).


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
put(Key, Value) ->
    put(name(plum_db:get_partition(Key)), Key, Value).


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
put(Partition, Key, Value) when is_integer(Partition) ->
    put(name(Partition), Key, Value);

put(Name, Key, Value) when is_atom(Name) ->
    gen_server:call(Name, {put, Key, Value}, infinity).


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
delete(Key) ->
    delete(name(plum_db:get_partition(Key)), Key).


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
delete(Partition, Key) when is_integer(Partition) ->
    delete(name(Partition), Key);

delete(Name, Key) when is_atom(Name) ->
    gen_server:call(Name, {delete, Key}, infinity).


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
is_empty(Id) when is_integer(Id) ->
    is_empty(name(valid_partition(Id)));

is_empty(Store) when is_pid(Store); is_atom(Store) ->
    gen_server:call(Store, is_empty, infinity).


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
byte_size(Id) when is_integer(Id) ->
    ?MODULE:byte_size(name(valid_partition(Id)));

byte_size(Store) when is_pid(Store); is_atom(Store) ->
    gen_server:call(Store, byte_size, infinity).


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
iterator(Id) when is_integer(Id) ->
    iterator(name(valid_partition(Id)));

iterator(Store) when is_pid(Store); is_atom(Store) ->
    gen_server:call(Store, {iterator, self()}, infinity).


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
key_iterator(Id) when is_integer(Id) ->
    key_iterator(name(valid_partition(Id)));

key_iterator(Store) when is_pid(Store); is_atom(Store) ->
    gen_server:call(Store, {key_iterator, self()}, infinity).


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
iterator_close(Id, Iter) when is_integer(Id) ->
    iterator_close(name(valid_partition(Id)), Iter);

iterator_close(Store, {OwnerRef, _DbIter} = Iter)
when (is_pid(Store) orelse is_atom(Store)) andalso is_reference(OwnerRef) ->
    gen_server:call(Store, {iterator_close, Iter}, infinity).


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
-spec iterator_move(iterator(), iterator_action()) ->
    {ok, Key :: binary(), Value :: binary()}
    | {ok, Key :: binary()}
    | {error, invalid_iterator}
    | {error, iterator_closed}.

iterator_move({OwnerRef, DbIter}, Action) when is_reference(OwnerRef) ->
    eleveldb:iterator_move(DbIter, Action).




%% =============================================================================
%% GEN_SERVER CALLBACKS
%% =============================================================================



init([Partition, Opts]) ->
    %% Initialize random seed
    rand:seed(exsplus, erlang:timestamp()),

    DataRoot = filename:join([
        app_helper:get_prop_or_env(data_dir, Opts, plum_db),
        "db",
        integer_to_list(Partition)
    ]),

	case filelib:ensure_dir(DataRoot) of
        ok ->
            case open_db(init_state(Partition, DataRoot, Opts)) of
                {ok, State} ->
                    process_flag(trap_exit, true),
                    {ok, State};
                {error, Reason} ->
                    {stop, Reason}
            end;
		{error, Reason} ->
		 	{stop, Reason}
    end.


handle_call({get, Key}, _From, State) ->
    DbRef = State#state.db_ref,
    Opts = State#state.read_opts,
    Result = result(eleveldb:get(DbRef, encode_key(Key), Opts)),
    {reply, Result, State};

handle_call({put, Key, Value}, _From, State) ->
    DbRef = State#state.db_ref,
    Opts = State#state.write_opts,
    Actions = [{put, encode_key(Key), term_to_binary(Value)}],
    Result = result(eleveldb:write(DbRef, Actions, Opts)),
    {reply, Result, State};

handle_call({delete, Key}, _From, State) ->
    DbRef = State#state.db_ref,
    Opts = State#state.write_opts,
    Actions = [{delete, encode_key(Key)}],
    Result = result(eleveldb:write(DbRef, Actions, Opts)),
    {reply, Result, State};

handle_call(byte_size, _From, State) ->
    DbRef = State#state.db_ref,
    try eleveldb:status(DbRef, <<"leveldb.total-bytes">>) of
        {ok, Bin} ->
            {reply, binary_to_integer(Bin), State}
    catch
        error:_ ->
            {reply, undefined, State}
    end;

handle_call(is_empty, _From, State) ->
    DbRef = State#state.db_ref,
    Result = eleveldb:is_empty(DbRef),
    {reply, Result, State};

handle_call({iterator, Pid}, _From, State) ->
    DbRef = State#state.db_ref,
    Ref = erlang:monitor(process, Pid),
    {ok, DbIter} = eleveldb:iterator(DbRef, State#state.fold_opts),
    Iter = {Ref, DbIter},
    {reply, Iter, add_iterator(Iter, State)};

handle_call({key_iterator, Pid}, _From, State) ->
    DbRef = State#state.db_ref,
    Ref = erlang:monitor(process, Pid),
    {ok, DbIter} = eleveldb:iterator(DbRef, State#state.fold_opts, keys_only),
    Iter = {Ref, DbIter},
    {reply, Iter, add_iterator(Iter, State)};

handle_call({iterator_close, Iter}, _From, State0) ->
    case take_iterator(Iter, State0) of
        {{Ref, DbIter}, State1} ->
            _ = erlang:demonitor(Ref, [flush]),
            _ = eleveldb:iterator_close(DbIter),
            {reply, ok, State1};
        error ->
            {reply, ok, State0}
    end.


handle_cast(_Msg, State) ->
    {noreply, State}.


handle_info({'DOWN', Ref, process, _, _}, State0) ->
    case take_iterator(Ref, State0) of
        {{Ref, DbIter}, State1} ->
            _ = eleveldb:iterator_close(DbIter),
            {noreply, State1};
        error ->
            {noreply, State0}
    end;

handle_info(_Info, State) ->
    {noreply, State}.


terminate(_Reason, #state{db_ref = DbRef}) ->
    eleveldb:close(DbRef),
    ok.


code_change(_OldVsn, State, _Extra) ->
    {ok, State}.



%% =============================================================================
%% PRIVATE: ELEVELDB INIT
%% Borrowed from riak_kv_eleveldb_backend.erl
%% =============================================================================


%% @private
init_state(Partition, DataRoot, Config) ->
    %% Merge the proplist passed in from Config with any values specified by the
    %% eleveldb app level; precedence is given to the Config.
    MergedConfig = orddict:merge(
        fun(_K, VLocal, _VGlobal) -> VLocal end,
        orddict:from_list(Config), % Local
        orddict:from_list(application:get_all_env(eleveldb))), % Global

    %% Use a variable write buffer size in order to reduce the number
    %% of vnodes that try to kick off compaction at the same time
    %% under heavy uniform load...
    WriteBufferMin = config_value(
        write_buffer_size_min, MergedConfig, 30 * 1024 * 1024),
    WriteBufferMax = config_value(
        write_buffer_size_max, MergedConfig, 60 * 1024 * 1024),
    WriteBufferSize = WriteBufferMin + rand:uniform(
        1 + WriteBufferMax - WriteBufferMin),

    %% Update the write buffer size in the merged config and make sure create_if_missing is set
    %% to true
    FinalConfig = orddict:store(
        write_buffer_size,
        WriteBufferSize,
        orddict:store(create_if_missing, true, MergedConfig)),

    %% Parse out the open/read/write options
    {OpenOpts, _BadOpenOpts} = eleveldb:validate_options(open, FinalConfig),
    {ReadOpts, _BadReadOpts} = eleveldb:validate_options(read, FinalConfig),
    {WriteOpts, _BadWriteOpts} = eleveldb:validate_options(write, FinalConfig),

    %% Use read options for folding, but FORCE fill_cache to false
    FoldOpts = lists:keystore(fill_cache, 1, ReadOpts, {fill_cache, false}),

    %% Warn if block_size is set
    SSTBS = proplists:get_value(sst_block_size, OpenOpts, false),
    BS = proplists:get_value(block_size, OpenOpts, false),

    case BS /= false andalso SSTBS == false of
        true ->
            lager:warning(
                "eleveldb block_size has been renamed sst_block_size "
                "and the current setting of ~p is being ignored.  "
                "Changing sst_block_size is strongly cautioned "
                "against unless you know what you are doing.  Remove "
                "block_size from app.config to get rid of this "
                "message.\n", [BS]);
        _ ->
            ok
    end,

    #state {
        partition = Partition,
		config = FinalConfig,
        data_root = DataRoot,
		open_opts = OpenOpts,
		read_opts = ReadOpts,
		write_opts = WriteOpts,
		fold_opts = FoldOpts
	}.


%% @private
config_value(Key, Config, Default) ->
    case orddict:find(Key, Config) of
        error ->
            Default;
        {ok, Value} ->
            Value
    end.


%% @private
open_db(State0) ->
    RetriesLeft = app_helper:get_env(plum_db, store_open_retry_Limit, 30),
    open_db(State0, max(1, RetriesLeft), undefined).


%% @private
open_db(_State0, 0, LastError) ->
    {error, LastError};

open_db(State0, RetriesLeft, _) ->
    case eleveldb:open(State0#state.data_root, State0#state.open_opts) of
        {ok, Ref} ->
            {ok, State0#state{db_ref = Ref}};
        %% Check specifically for lock error, this can be caused if
        %% a crashed vnode takes some time to flush leveldb information
        %% out to disk.  The process is gone, but the NIF resource cleanup
        %% may not have completed.
    	{error, {db_open, OpenErr} = Reason} ->
            case lists:prefix("IO error: lock ", OpenErr) of
                true ->
                    SleepFor = app_helper:get_env(
                        plum_db, store_open_retries_delay, 2000),
                    lager:debug("Leveldb backend retrying ~p in ~p ms after error ~s\n",
                                [State0#state.data_root, SleepFor, OpenErr]),
                    timer:sleep(SleepFor),
                    open_db(State0, RetriesLeft - 1, Reason);
                false ->
                    {error, Reason}
            end;
        {error, Reason} ->
            {error, Reason}
    end.




%% =============================================================================
%% PRIVATE
%% =============================================================================



%% -----------------------------------------------------------------------------
%% @private
%% @doc Validates the id is within range, returning the Id if it is or failing
%% with invalid_store_id otherwise.
%% @end
%% -----------------------------------------------------------------------------
valid_partition(Id) ->
   plum_db:is_partition(Id) orelse error(invalid_store_id),
   Id.


%% @private
add_iterator({OwnerRef, _DbIter} = Iter, State) when is_reference(OwnerRef) ->
    Iterators1 = lists:keystore(OwnerRef, 1, State#state.iterators, Iter),
    State#state{iterators = Iterators1}.


%% @private
take_iterator({OwnerRef, _DbIter}, State) ->
    take_iterator(OwnerRef, State);

take_iterator(OwnerRef, State) when is_reference(OwnerRef) ->
    case lists:keytake(OwnerRef, 1, State#state.iterators) of
        {value, {OwnerRef, _} = Iter, Iterators1} ->
            {Iter, State#state{iterators = Iterators1}};
        false ->
            error
    end.


%% @private
result(ok) ->
    ok;

result({ok, Value}) ->
    {ok, binary_to_term(Value)};

result(not_found) ->
    {error, not_found};

result({error, _} = Error) ->
    Error.


%% @private
encode_key(Key) ->
    sext:encode(Key).





%% encode_key({}) ->
%% 	E = <<>>,
%% 	<<
%% 		Idx/binary, ?KEY_SEPARATOR/binary,
%% 		TenId/binary, ?KEY_SEPARATOR/binary,
%% 		(encode_element(G))/binary, ?KEY_SEPARATOR/binary,
%% 		E/binary, ?KEY_SEPARATOR/binary,
%% 		E/binary, ?KEY_SEPARATOR/binary,
%% 		E/binary, ?KEY_SEPARATOR/binary,
%% 		(encode_element(Txid))/binary
%% 	>>;

%% encode_key(Term) ->
%%     term_to_binary(Bin);


%% %% @private
%% decode_key(Bin) when is_binary(Bin) ->
%% 	decode_key(binary:split(Bin, ?KEY_SEPARATOR, [global]));

%% decode_key([Term]) ->
%%     binary_to_term(Term);

%% decode_key(_L) when is_list(L) ->
%%     error(not_implemented).

