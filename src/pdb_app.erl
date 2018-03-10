%% -----------------------------------------------------------------------------
%% @doc
%%
%% <pre><code>
%%                         +------------------+
%%                         |                  |
%%                         |     pdb_sup      |
%%                         |                  |
%%                         +------------------+
%%                                   |
%%           +-----------------------+
%%           |                       |
%%           v                       v
%% +------------------+    +------------------+
%% |                  |    |                  |
%% |   pdb_manager    |    |  pdb_store_sup   |
%% |                  |    |                  |
%% +------------------+    +------------------+
%%                                   |
%%                       +-----------+-----------+
%%                       |                       |
%%                       v                       v
%%             +------------------+    +------------------+
%%             |    pdb_store_    |    |    pdb_store_    |
%%             | partition_sup_1  |    | partition_sup_n  |
%%             |                  |    |                  |
%%             +------------------+    +------------------+
%%                       |
%%           +-----------+-----------+----------------------+
%%           |                       |                      |
%%           v                       v                      v
%% +------------------+    +------------------+   +------------------+
%% |                  |    |                  |   |                  |
%% |pdb_store_worker_1|    |pdb_store_server_1|   |  pdb_hashtree_1  |
%% |                  |    |                  |   |                  |
%% +------------------+    +------------------+   +------------------+
%%                                   |
%%                                   v
%%                         + - - - - - - - - -
%%                                            |
%%                         |     eleveldb
%%                                            |
%%                         + - - - - - - - - -
%% </code></pre>
%%
%% @end
%% -----------------------------------------------------------------------------
-module(pdb_app).
-behaviour(application).

-export([start/2]).
-export([stop/1]).



%% =============================================================================
%% API
%% =============================================================================


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
start(_StartType, _StartArgs) ->
    pdb_sup:start_link().


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
stop(_State) ->
    ok.


