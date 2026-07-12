%%% @doc Cowboy listeners for hecate-spartan.
%%%
%%% Two listeners:
%%%   - the entity-facing API on `ingress_port' (public — entities reach it
%%%     outbound over the network),
%%%   - `/health' on `health_port', loopback only, for the container
%%%     HEALTHCHECK. hecate_om ships the handler but starts no listener, so we
%%%     wire it here.
-module(hecate_spartan_ingress).
-behaviour(gen_server).

-export([start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-define(API_LISTENER, hecate_spartan_api).
-define(HEALTH_LISTENER, hecate_spartan_health).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

init([]) ->
    process_flag(trap_exit, true),
    ApiPort = env(ingress_port, 8471),
    HealthPort = env(health_port, 8470),
    {ok, _} = cowboy:start_clear(?API_LISTENER,
                                 [{port, ApiPort}],
                                 #{env => #{dispatch => api_dispatch()}}),
    {ok, _} = cowboy:start_clear(?HEALTH_LISTENER,
                                 [{ip, {127, 0, 0, 1}}, {port, HealthPort}],
                                 #{env => #{dispatch => health_dispatch()}}),
    logger:info("hecate_spartan ingress up: API :~p, health 127.0.0.1:~p",
                [ApiPort, HealthPort]),
    {ok, #{}}.

handle_call(_Req, _From, S) -> {reply, ok, S}.
handle_cast(_Msg, S)        -> {noreply, S}.
handle_info(_Info, S)       -> {noreply, S}.

terminate(_Reason, _S) ->
    _ = cowboy:stop_listener(?API_LISTENER),
    _ = cowboy:stop_listener(?HEALTH_LISTENER),
    ok.

%% --- routes ---

api_dispatch() ->
    cowboy_router:compile([
        {'_', [
            {"/v1/register", register_entity_api, []},
            {"/v1/send",     route_message_api,   []},
            {"/v1/receive",  receive_api,         []}
        ]}
    ]).

health_dispatch() ->
    cowboy_router:compile([
        {'_', [
            {"/health", hecate_om_health_handler, []}
        ]}
    ]).

env(Key, Default) ->
    application:get_env(hecate_spartan, Key, Default).
