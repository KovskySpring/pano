-module(pano_ffi).

-export([halt/1]).

%% Stop the runtime with an exit status, flushing pending output first.
halt(Status) ->
    erlang:halt(Status).
