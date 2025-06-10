%% =============================================================================
%%  plum_db_exchanges_sup.erl -
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

%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
-module(plum_db_exchanges_sup).
-behaviour(supervisor).

-define(CHILD(Id, Type, Args, Restart, Timeout), #{
    id => Id,
    start => {Id, start_link, Args},
    restart => Restart,
    shutdown => Timeout,
    type => Type,
    modules => [Id]
}).

%% API
-export([start_link/0]).
-export([start_exchange/2]).
-export([stop_exchange/1]).


%% SUPERVISOR CALLBACKS
-export([init/1]).



%% =============================================================================
%% API
%% =============================================================================



%% -----------------------------------------------------------------------------
%% @doc Starts a new exchange provided we would not reach the limit set by the
%% `aae_concurrency' config parameter.
%% If the limit is reached returns the error tuple `{error, concurrency_limit}'
%% @end
%% -----------------------------------------------------------------------------
-spec start_exchange(node(), list() | map()) ->
    supervisor:startchild_ret() | {error, Reason :: any()}.

start_exchange(Peer, Opts) ->
    case partisan:node() of
        Peer ->
            {error, this_node};
        _ ->
            Children = supervisor:count_children(?MODULE),
            {active, Count} = lists:keyfind(active, 1, Children),

            case plum_db_config:get(aae_concurrency) > Count of
                true ->
                    supervisor:start_child(?MODULE, [Peer, Opts]);
                false ->
                    {error, concurrency_limit}
            end
    end.


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
stop_exchange(Pid) when is_pid(Pid)->
    supervisor:terminate_child(?MODULE, Pid).


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
-spec start_link() -> {ok, pid()} | ignore | {error, term()}.

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).



%% =============================================================================
%% SUPERVISOR CALLBACKS
%% =============================================================================



init([]) ->
    Children = [
        ?CHILD(plum_db_exchange_statem, worker, [], temporary, 5000)
    ],
    Specs = {{simple_one_for_one, 2, 10}, Children},
    {ok, Specs}.




%% =============================================================================
%% PRIVATE
%% =============================================================================


