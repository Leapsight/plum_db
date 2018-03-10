%% -------------------------------------------------------------------
%%
%% Copyright (c) 2013 Basho Technologies, Inc.  All Rights Reserved.
%%
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.
%%
%% -------------------------------------------------------------------
-module(pdb_manager).
-behaviour(gen_server).
-include("pdb.hrl").


-record(state, {
    %% an ets table to hold iterators opened
    %% by other nodes
    iterators  :: ets:tab()
}).

-record(iterator, {
    prefix                  ::  pdb_prefix() | undefined,
    match                   ::  term() | undefined,
    keys_only = false       ::  boolean(),
    obj                     ::  {pdb_key(), pdb_object()}
                                | pdb_key()
                                | undefined,
    ref                     ::  pdb_store_server:iterator(),
    partitions              ::  [non_neg_integer()]
}).

-record(remote_iterator, {
    node   :: node(),
    ref    :: reference(),
    prefix :: pdb_prefix() | atom() | binary()
}).

-type state()           :: #state{}.
-type remote_iterator() :: #remote_iterator{}.
-opaque iterator()      :: #iterator{}.

-export_type([iterator/0]).


-export([iterate/1]).
-export([iterator/0]).
-export([iterator/1]).
-export([iterator/2]).
-export([iterator_close/1]).
-export([iterator_done/1]).
-export([iterator_prefix/1]).
-export([iterator_value/1]).
-export([remote_iterator/1]).
-export([remote_iterator/2]).
-export([start_link/0]).

%% API


%% gen_server callbacks
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
%% @doc Start plumtree_metadadata_manager and link to calling process.
%% @end
%% -----------------------------------------------------------------------------
-spec start_link() -> {ok, pid()} | ignore | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).



%% -----------------------------------------------------------------------------
%% @doc Returns a full-prefix iterator: an iterator for all full-prefixes that
%% have keys stored under them.
%% When done with the iterator, iterator_close/1 must be called
%% @end
%% -----------------------------------------------------------------------------
-spec iterator() -> iterator().
iterator() ->
    iterator(undefined).


%% -----------------------------------------------------------------------------
%% @doc Returns a sub-prefix iterator for a given prefix.
%% When done with the iterator, iterator_close/1 must be called
%% @end
%% -----------------------------------------------------------------------------
-spec iterator(binary() | atom()) -> iterator().
iterator(Prefix) when is_binary(Prefix) or is_atom(Prefix) ->
    new_iterator(undefined, Prefix).


%% -----------------------------------------------------------------------------
%% @doc Return an iterator for keys stored under a prefix. If KeyMatch is
%% undefined then all keys will may be visted by the iterator. Otherwise only
%% keys matching KeyMatch will be visited.
%%
%% KeyMatch can be either:
%%
%% * an erlang term - which will be matched exactly against a key
%% * '_' - which is equivalent to undefined
%% * an erlang tuple containing terms and '_' - if tuples are used as keys
%% * this can be used to iterate over some subset of keys
%%
%% When done with the iterator, iterator_close/1 must be called.
%% @end
%% -----------------------------------------------------------------------------
-spec iterator(pdb_prefix() , term()) -> iterator().
iterator({Prefix, SubPrefix}=FullPrefix, KeyMatch)
  when (is_binary(Prefix) orelse is_atom(Prefix)) andalso
       (is_binary(SubPrefix) orelse is_atom(SubPrefix)) ->
    new_iterator(FullPrefix, KeyMatch).


%% -----------------------------------------------------------------------------
%% @doc Create an iterator on `Node'. This allows for remote iteration by having
%% the worker keep track of the actual iterator (since ets
%% continuations cannot cross node boundaries). The iterator created iterates
%% all full-prefixes.
%% Once created the rest of the iterator API may be used as usual. When done
%% with the iterator, iterator_close/1 must be called
%% @end
%% -----------------------------------------------------------------------------
-spec remote_iterator(node()) -> remote_iterator().
remote_iterator(Node) ->
    remote_iterator(Node, undefined).


%% -----------------------------------------------------------------------------
%% @doc Create an iterator on `Node'. This allows for remote iteration
%% by having the worker keep track of the actual iterator
%% (since ets continuations cannot cross node boundaries). When
%% `Perfix' is not a full prefix, the iterator created iterates all
%% sub-prefixes under `Prefix'. Otherse, the iterator iterates all keys
%% under a prefix. Once created the rest of the iterator API may be used as
%% usual.
%% When done with the iterator, iterator_close/1 must be called
%% @end
%% -----------------------------------------------------------------------------
-spec remote_iterator(node(), pdb_prefix() | binary() | atom() | undefined) ->
    remote_iterator().

remote_iterator(Node, Prefix) when is_atom(Prefix); is_binary(Prefix) ->
    Ref = gen_server:call(
        {?MODULE, Node},
        {open_remote_iterator, self(), undefined, Prefix},
        infinity
    ),
    #remote_iterator{ref = Ref, prefix = Prefix, node = Node};

remote_iterator(Node, FullPrefix) when is_tuple(FullPrefix) ->
    Ref = gen_server:call(
        {?MODULE, Node},
        {open_remote_iterator, self(), FullPrefix, undefined},
        infinity
    ),
    #remote_iterator{ref = Ref, prefix = FullPrefix, node = Node}.


%% -----------------------------------------------------------------------------
%% @doc Advances the iterator by one key, full-prefix or sub-prefix
%% @end
%% -----------------------------------------------------------------------------
-spec iterate(iterator() | remote_iterator()) -> iterator() | remote_iterator().

iterate(#remote_iterator{ref = Ref, node = Node} = I) ->
    _ = gen_server:call({?MODULE, Node}, {iterate, Ref}, infinity),
    I;

iterate(#iterator{ref = undefined, partitions = []} = I) ->
    %% We are done
    %% '$end_of_table';
    I;

iterate(#iterator{ref = undefined, partitions = [H|_]} = I0) ->
    First = first_key(I0#iterator.prefix),
    Ref = case I0#iterator.keys_only of
        true ->
            pdb_store_server:key_iterator(H);
        false ->
            pdb_store_server:iterator(H)
    end,
    iterate(eleveldb:iterator_move(Ref, First), I0#iterator{ref = Ref});

iterate(#iterator{ref = Ref} = I) ->
    iterate(eleveldb:iterator_move(Ref, prefetch), I).


iterate({error, _}, #iterator{ref = Ref, partitions = [H|T]} = I) ->
    ok = pdb_store_server:iterator_close(H, Ref),
    iterate(I#iterator{ref = undefined, partitions = T});

iterate({ok, K}, #iterator{ref = Ref, partitions = [H|T]} = I) ->
    PKey = pdb:decode_key(K),
    case prefixed_key_matches(PKey, I) of
        true ->
            I#iterator{obj = PKey};
        false ->
            ok = pdb_store_server:iterator_close(H, Ref),
            iterate(I#iterator{ref = undefined, partitions = T})
    end;

iterate({ok, K, V},  #iterator{ref = Ref, partitions = [H|T]} = I) ->
    PKey = pdb:decode_key(K),
    case prefixed_key_matches(PKey, I) of
        true ->
            I#iterator{obj = {PKey, binary_to_term(V)}};
        false ->
            ok = pdb_store_server:iterator_close(H, Ref),
            iterate(I#iterator{ref = undefined, partitions = T})
    end.


prefixed_key_matches(PKey, #iterator{prefix = P, match = M}) ->
    prefixed_key_matches(PKey, P, M).

%% @private
prefixed_key_matches({_, _}, {undefined, undefined}, undefined) ->
    true;
prefixed_key_matches({_, Key}, {undefined, undefined}, Fun) ->
    Fun(Key);

prefixed_key_matches({{Prefix, _}, _}, {Prefix, undefined}, undefined) ->
    true;
prefixed_key_matches({{Prefix, _}, Key}, {Prefix, undefined}, Fun) ->
    Fun(Key);

prefixed_key_matches({{_, SubPrefix}, _}, {undefined, SubPrefix}, undefined) ->
    true;
prefixed_key_matches({{_, SubPrefix}, Key}, {undefined, SubPrefix}, Fun) ->
    Fun(Key);

prefixed_key_matches({FullPrefix, _}, FullPrefix, undefined) ->
    true;
prefixed_key_matches({{_, SubPrefix}, Key}, {undefined, SubPrefix}, Fun) ->
    Fun(Key);

prefixed_key_matches(_, _, _) ->
    false.


%% -----------------------------------------------------------------------------
%% @doc Returns the full-prefix or prefix being iterated by this iterator. If
%% the iterator is a full-prefix iterator undefined is returned.
%% @end
%% -----------------------------------------------------------------------------
-spec iterator_prefix(iterator() | remote_iterator()) ->
    pdb_prefix() | undefined | binary() | atom().

iterator_prefix(#remote_iterator{prefix = Prefix}) ->
    Prefix;
iterator_prefix(#iterator{prefix = undefined, match = undefined}) ->
    undefined;
iterator_prefix(#iterator{prefix = undefined, match = Prefix}) ->
    Prefix;
iterator_prefix(#iterator{prefix = Prefix}) ->
    Prefix.


%% -----------------------------------------------------------------------------
%% @doc Returns the key and object or the prefix pointed to by the iterator
%% @end
%% -----------------------------------------------------------------------------
-spec iterator_value(iterator() | remote_iterator()) ->
    {pdb_key(), pdb_object()}
    | pdb_prefix() | binary() | atom().

iterator_value(#remote_iterator{ref = Ref, node = Node}) ->
    gen_server:call({?MODULE, Node}, {iterator_value, Ref}, infinity);

iterator_value(#iterator{obj = Obj}) ->
    Obj.


%% -----------------------------------------------------------------------------
%% @doc Returns true if there are no more keys or prefixes to iterate over
%% @end
%% -----------------------------------------------------------------------------
-spec iterator_done(iterator() | remote_iterator()) -> boolean().

iterator_done(#remote_iterator{ref = Ref, node = Node}) ->
    gen_server:call({?MODULE, Node}, {iterator_done, Ref}, infinity);

iterator_done(#iterator{ref = undefined, partitions = []}) ->
    true;

iterator_done(#iterator{}) ->
    false.


%% -----------------------------------------------------------------------------
%% @doc Closes the iterator. This function must be called on all open iterators
%% @end
%% -----------------------------------------------------------------------------
-spec iterator_close(iterator() | remote_iterator()) -> ok.

iterator_close(#remote_iterator{ref = Ref, node = Node}) ->
    gen_server:call({?MODULE, Node}, {iterator_close, Ref}, infinity);

iterator_close(#iterator{ref = undefined}) ->
    ok;

iterator_close(#iterator{ref = Ref}) ->
    pdb_store_server:iterator_close(Ref).





%%%===================================================================
%%% gen_server callbacks
%%%===================================================================



%% @private
-spec init([]) ->
    {ok, state()}
    | {ok, state(), non_neg_integer() | infinity}
    | ignore
    | {stop, term()}.

init([]) ->
    ?MODULE = ets:new(
        ?MODULE,
        [named_table, {read_concurrency, true}, {write_concurrency, true}]
    ),
    {ok, #state{iterators = ?MODULE}}.

%% @private
-spec handle_call(term(), {pid(), term()}, state()) ->
    {reply, term(), state()}
    | {reply, term(), state(), non_neg_integer()}
    | {noreply, state()}
    | {noreply, state(), non_neg_integer()}
    | {stop, term(), term(), state()}
    | {stop, term(), state()}.

handle_call({open_remote_iterator, Pid, FullPrefix, KeyMatch}, _From, State) ->
    Iterator = new_remote_iterator(Pid, FullPrefix, KeyMatch, State),
    {reply, Iterator, State};

handle_call({iterate, RemoteRef}, _From, State) ->
    Next = iterate(RemoteRef, State),
    {reply, Next, State};

handle_call({iterator_value, RemoteRef}, _From, State) ->
    Res = from_remote_iterator(fun iterator_value/1, RemoteRef, State),
    {reply, Res, State};

handle_call({iterator_done, RemoteRef}, _From, State) ->
    Res = case from_remote_iterator(fun iterator_done/1, RemoteRef, State) of
              undefined -> true; %% if we don't know about iterator, treat it as done
              Other -> Other
          end,
    {reply, Res, State};

handle_call({iterator_close, RemoteRef}, _From, State) ->
    close_remote_iterator(RemoteRef, State),
    {reply, ok, State}.


%% @private
-spec handle_cast(term(), state()) ->
    {noreply, state()}
    | {noreply, state(), non_neg_integer()}
    | {stop, term(), state()}.

handle_cast(_Msg, State) ->
    {noreply, State}.


%% @private
-spec handle_info(term(), state()) ->
    {noreply, state()}
    | {noreply, state(), non_neg_integer()}
    | {stop, term(), state()}.

handle_info({'DOWN', ItRef, process, _Pid, _Reason}, State) ->
    close_remote_iterator(ItRef, State),
    {noreply, State}.


%% @private
-spec terminate(term(), state()) -> term().

terminate(_Reason, _State) ->
    ok.


%% @private
-spec code_change(term() | {down, term()}, state(), term()) -> {ok, state()}.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.



%% =============================================================================
%% PRIVATE
%% =============================================================================


first_key({undefined, undefined}) -> first;
first_key({Prefix, undefined}) -> sext:encode({{Prefix, ''}, ''});
first_key({_, _} = FullPrefix) -> sext:encode({FullPrefix, ''}).


%% @private
new_remote_iterator(Pid, FullPrefix, KeyMatch, #state{iterators = Iterators}) ->
    Ref = monitor(process, Pid),
    Iterator = new_iterator(FullPrefix, KeyMatch),
    ets:insert(Iterators, [{Ref, Iterator}]),
    Ref.


%% @private
from_remote_iterator(Fun, Ref, State) ->
    case ets:lookup(State#state.iterators, Ref) of
        [] -> undefined;
        [{Ref, It}] -> Fun(It)
    end.


%% @private
close_remote_iterator(Ref, #state{iterators = Iterators} = State) ->
    from_remote_iterator(fun iterator_close/1, Ref, State),
    ets:delete(Iterators, Ref).


%% @private
new_iterator(FullPrefix, KeyMatch) ->
    new_iterator(FullPrefix, KeyMatch, false).


%% @private
new_iterator(FullPrefix, KeyMatch, KeysOnly) ->
    #iterator{
        prefix = FullPrefix,
        match = KeyMatch,
        keys_only = KeysOnly,
        obj = undefined,
        ref = undefined,
        partitions = pdb:partitions()
    }.
