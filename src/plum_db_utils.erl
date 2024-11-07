-module(plum_db_utils).


-export([insert_spawn/2]).
-export([delete_spawn/2]).


%% =============================================================================
%% API
%% =============================================================================



insert_spawn(N, M) ->
    Node = partisan:node(),
    [do_insert_spawn(Node, X) || X <- lists:seq(N, M)].


delete_spawn(N, M) ->
    Node = partisan:node(),
    [do_delete_spawn(Node, X) || X <- lists:seq(N, M)].




%% =============================================================================
%% PRIVATE
%% =============================================================================




do_insert_spawn(Node, X) ->
    spawn(fun() ->
        Key = {Node, {X, foo}},
        plum_db:put({disk, disk}, Key, partisan:self())
    end).


do_delete_spawn(Node, X) ->
    spawn(fun() ->
        Key = {Node, {X, foo}},
        plum_db:delete({disk, disk}, Key)
    end).