%%% @doc hecate_spartan OTP application entry.
%%%
%%% One call. hecate_om:boot/1 sees this service exports store_id/0 +
%%% data_dir/0, starts the reckon-db store + evoq subscription, registers
%%% capabilities and the /health probe, then calls the service's start/1.
-module(hecate_spartan_app).
-behaviour(application).

-export([start/2, stop/1]).

start(_StartType, _StartArgs) ->
    hecate_om:boot(hecate_spartan_service).

stop(_State) ->
    ok.
