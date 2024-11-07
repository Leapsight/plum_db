-module(hashtree_utils).

-export([hash/1]).
-export([sha/1]).
-export([md5/1]).
-export([bin/1]).



%% =============================================================================
%% API
%% =============================================================================

bin(X) ->
    list_to_binary(integer_to_list(X)).

-spec hash(term()) -> empty | binary().

hash([]) ->
    empty;
hash(X) ->
    %% erlang:phash2(X).
    sha(term_to_binary(X)).

sha(Bin) ->
    Chunk = plum_db_config:get(aae_sha_chunk, 4096),
    sha(Chunk, Bin).

sha(Chunk, Bin) ->
    Ctx1 = esha_init(),
    Ctx2 = sha(Chunk, Bin, Ctx1),
    SHA = esha_final(Ctx2),
    SHA.

sha(Chunk, Bin, Ctx) ->
    case Bin of
        <<Data:Chunk/binary, Rest/binary>> ->
            Ctx2 = esha_update(Ctx, Data),
            sha(Chunk, Rest, Ctx2);
        Data ->
            Ctx2 = esha_update(Ctx, Data),
            Ctx2
    end.

-ifndef(old_hash).
md5(Bin) ->
    crypto:hash(md5, Bin).

-ifdef(TEST).
esha(Bin) ->
    crypto:hash(sha, Bin).
-endif.

esha_init() ->
    crypto:hash_init(sha).

esha_update(Ctx, Bin) ->
    crypto:hash_update(Ctx, Bin).

esha_final(Ctx) ->
    crypto:hash_final(Ctx).
-else.
md5(Bin) ->
    crypto:md5(Bin).

-ifdef(TEST).
esha(Bin) ->
    crypto:sha(Bin).
-endif.

esha_init() ->
    crypto:sha_init().

esha_update(Ctx, Bin) ->
    crypto:sha_update(Ctx, Bin).

esha_final(Ctx) ->
    crypto:sha_final(Ctx).
-endif.