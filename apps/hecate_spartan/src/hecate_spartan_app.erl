%%% @doc hecate_spartan OTP application entry.
%%%
%%% One call. hecate_om:boot/1 registers capabilities and the /health
%%% probe, then calls the service's start/1. Store-free: the service
%%% exports data_dir/0 but not store_id/0, so no reckon-db store is wired.
-module(hecate_spartan_app).
-behaviour(application).

-export([start/2, stop/1]).

start(_StartType, _StartArgs) ->
    hecate_om:boot(hecate_spartan_service).

stop(_State) ->
    ok.
