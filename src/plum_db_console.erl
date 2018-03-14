-module(plum_db_console).
-include("plum_db.hrl").

-export([members/1]).





%% =============================================================================
%% API
%% =============================================================================



members([]) ->
    {ok, Members} = plum_db_peer_service:members(),
    print_members(Members).




%% =============================================================================
%% PRIVATE
%% =============================================================================



print_members(Members) ->
    _ = io:format("~29..=s Cluster Membership ~30..=s~n", ["",""]),
    _ = io:format("Connected Nodes:~n~n", []),
    _ = [io:format("~p~n", [Node]) || Node <- Members],
    _ = io:format("~79..=s~n", [""]),
    ok.
