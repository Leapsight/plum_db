%% =============================================================================
%%  plum_db_key.erl -
%%
%%  Copyright (c) 2018-2021 Leapsight. All rights reserved.
%%
%%  Licensed under the Apache License, Version 2.0 (the "License");
%%  you may not use this file except in compliance with the License.
%%  You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%%  Unless required by applicable law or agreed to in writing, software
%%  distributed under the License is distributed on an "AS IS" BASIS,
%%  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%%  See the License for the specific language governing permissions and
%%  limitations under the License.
%% =============================================================================

-module(plum_db_key).

-export([encoder/0]).
-export([decoder/0]).
-export([prefix_encoder/0]).
-export([encode/1]).
-export([encode/2]).
-export([decode/1]).
-export([prefix/1]).



%% =============================================================================
%% API
%% =============================================================================


encoder() ->
    Mode = plum_db_config:get(key_encoding),
    fun(Key, Opts) -> encode(Key, Opts, Mode) end.

prefix_encoder() ->
    Mode = plum_db_config:get(key_encoding),
    fun(Key) -> prefix(Key, Mode) end.

decoder() ->
    Mode = plum_db_config:get(key_encoding),
    fun(Key) -> decode(Key, Mode) end.


encode(Key) ->
    encode(Key, []).

encode(Key, Opts) ->
    encode(Key, Opts, plum_db_config:get(key_encoding)).


decode(Bin) when is_binary(Bin) ->
    decode(Bin, plum_db_config:get(key_encoding)).


prefix(Key) ->
    prefix(Key, plum_db_config:get(key_encoding)).



%% =============================================================================
%% PRIVATE
%% =============================================================================



encode({{_, _} = Prefix, Key}, Opts, record_separator) ->
    <<
    (encode_tuple(Prefix, Opts))/binary, $\30,
    (encode_field(Key, Opts))/binary
    >>;

encode({{_, _}, _} = FPKey, _, sext) ->
    sext:encode(FPKey).


decode(_Bin, record_separator) ->
    error(not_implemented);

decode(Bin, sext) ->
    sext:decode(Bin).


prefix({_FullPrefix, _Value} = Term, record_separator) ->
    sext:prefix(Term);

prefix({{_Prefix, _Tab}, _} = Term, sext) ->
    sext:prefix(Term).


encode_tuple({A, B}, Opts) ->
    <<
        (encode_field(A, Opts))/binary, $\30,
        (encode_field(B, Opts))/binary
    >>;

encode_tuple({A, B, C}, Opts) ->
    <<
        (encode_field(A, Opts))/binary, $\30,
        (encode_field(B, Opts))/binary, $\30,
        (encode_field(C, Opts))/binary
    >>;

encode_tuple({A, B, C, D}, Opts) ->
    <<
        (encode_field(A, Opts))/binary, $\30,
        (encode_field(B, Opts))/binary, $\30,
        (encode_field(C, Opts))/binary, $\30,
        (encode_field(D, Opts))/binary
    >>;

encode_tuple({A, B, C, D, E}, Opts) ->
    <<
        (encode_field(A, Opts))/binary, $\30,
        (encode_field(B, Opts))/binary, $\30,
        (encode_field(C, Opts))/binary, $\30,
        (encode_field(D, Opts))/binary, $\30,
        (encode_field(E, Opts))/binary
    >>;

encode_tuple({A, B, C, D, E, F}, Opts) ->
    <<
        (encode_field(A, Opts))/binary, $\30,
        (encode_field(B, Opts))/binary, $\30,
        (encode_field(C, Opts))/binary, $\30,
        (encode_field(D, Opts))/binary, $\30,
        (encode_field(E, Opts))/binary, $\30,
        (encode_field(F, Opts))/binary
    >>;

encode_tuple(Tuple, Opts) when is_tuple(Tuple) ->
    Size = tuple_size(Tuple),
    {Head, [Last]} = lists:split(Size - 1, tuple_to_list(Tuple)),

    Bin = << <<(encode_field(F, Opts))/binary, $\30>> || F <- Head >>,
    <<Bin/binary, $\30, (encode_field(Last, Opts))/binary>>.



encode_field(Term, _) when is_binary(Term) ->
    Term;

encode_field(Term, Opts) when is_tuple(Term) ->
    encode_tuple(Term, Opts);

encode_field(Term, Opts) ->
    term_to_binary(Term, Opts).

