

# Module plum_db_app #
* [Description](#description)
* [Function Index](#index)
* [Function Details](#functions)

```
                          +------------------+
                          |                  |
                          |   plum_db_sup    |
                          |                  |
                          +------------------+
                                    |
            +-----------------------+-----------------------+
            |                       |                       |
            v                       v                       v
  +------------------+    +------------------+    +------------------+
  |                  |    |     plum_db_     |    |                  |
  |     plum_db      |    |  partitions_sup  |    |  plum_db_events  |
  |                  |    |                  |    |                  |
  +------------------+    +------------------+    +------------------+
                                    |
                        +-----------+-----------+
                        |                       |
                        v                       v
              +------------------+    +------------------+
              |plum_db_partition_|    |plum_db_partition_|
              |      1_sup       |    |      n_sup       |
              |                  |    |                  |
              +------------------+    +------------------+
                        |
            +-----------+-----------+----------------------+
            |                       |                      |
            v                       v                      v
  +------------------+    +------------------+   +------------------+
  |plum_db_partition_|    |plum_db_partition_|   |plum_db_partition_|
  |     1_worker     |    |     1_server     |   |    1_hashtree    |
  |                  |    |                  |   |                  |
  +------------------+    +------------------+   +------------------+
                                    |                      |
                                    v                      v
                          + - - - - - - - - -    + - - - - - - - - -
                                             |                      |
                          |     eleveldb         |     eleveldb
                                             |                      |
                          + - - - - - - - - -    + - - - - - - - - -
```
.

__Behaviours:__ [`application`](application.md).

<a name="index"></a>

## Function Index ##


<table width="100%" border="1" cellspacing="0" cellpadding="2" summary="function index"><tr><td valign="top"><a href="#prep_stop-1">prep_stop/1</a></td><td></td></tr><tr><td valign="top"><a href="#start-2">start/2</a></td><td></td></tr><tr><td valign="top"><a href="#start_phase-3">start_phase/3</a></td><td>Application behaviour callback.</td></tr><tr><td valign="top"><a href="#stop-1">stop/1</a></td><td></td></tr></table>


<a name="functions"></a>

## Function Details ##

<a name="prep_stop-1"></a>

### prep_stop/1 ###

`prep_stop(State) -> any()`

<a name="start-2"></a>

### start/2 ###

`start(StartType, StartArgs) -> any()`

<a name="start_phase-3"></a>

### start_phase/3 ###

`start_phase(X1, X2, X3) -> any()`

Application behaviour callback

<a name="stop-1"></a>

### stop/1 ###

`stop(State) -> any()`

