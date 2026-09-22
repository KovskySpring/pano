-module(pano_ffi).

-export([halt/1, stderr_is_terminal/0, terminal_columns/0]).

%% Stop the runtime with an exit status, flushing pending output first.
halt(Status) ->
  erlang:halt(Status).

stderr_is_terminal() ->
  try proplists:get_value(stderr, io:getopts(standard_io), false) of
    true ->
      true;
    _ ->
      false
  catch
    _:_ ->
      false
  end.

terminal_columns() ->
  try io:columns() of
    {ok, Columns} ->
      {ok, Columns};
    _ ->
      {error, nil}
  catch
    _:_ ->
      {error, nil}
  end.
