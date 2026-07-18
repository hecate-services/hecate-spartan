%%% @doc Federation registry subscriber.
%%%
%%% Subscribes to `spartan/registry' on the mesh and upserts every peer's
%%% `entity_announced' FACT into `mesh_entities', so this instance learns the
%%% whole federation's entities (and where each is homed). Re-subscribes on
%%% teardown; re-announces this instance's locally-homed entities on a timer so
%%% presence self-heals across churn. Degrades safely while the mesh is dark.
-module(federation_registry).
-behaviour(gen_server).

-export([start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-define(RESUB_MS,      5_000).
-define(REANNOUNCE_MS, 60_000).

-record(st, {subref :: reference() | undefined}).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

init([]) ->
    self() ! subscribe,
    erlang:send_after(?REANNOUNCE_MS, self(), reannounce),
    {ok, #st{subref = undefined}}.

handle_call(_Req, _From, St) -> {reply, {error, unknown_call}, St}.
handle_cast(_Msg, St)        -> {noreply, St}.

handle_info(subscribe, St) ->
    {noreply, do_subscribe(St)};
handle_info({macula_event, _Ref, _Topic, Payload, _Meta}, St) ->
    _ = on_announcement(Payload),
    {noreply, St};
handle_info({macula_event_gone, _Ref, _Reason}, St) ->
    self() ! subscribe,
    {noreply, St#st{subref = undefined}};
handle_info(reannounce, St) ->
    _ = reannounce_local(),
    erlang:send_after(?REANNOUNCE_MS, self(), reannounce),
    {noreply, St};
handle_info(_Info, St) ->
    {noreply, St}.

terminate(_Reason, _St) -> ok.

%% --- Internal ---

do_subscribe(St) ->
    subscribe_with(hecate_om:macula_client(), hecate_om_identity:realm(), St).

subscribe_with({ok, Pool}, {ok, Realm}, St) ->
    on_sub(catch macula:subscribe(Pool, Realm, hecate_spartan_society:topic(<<"registry">>), self()), St);
subscribe_with(_Client, _Realm, St) ->
    retry_subscribe(St).

%% Announce immediately on a fresh subscription, don't wait out the timer: a node
%% that just restarted has to tell the federation its entities are still here, or
%% peers keep routing to a home they think is empty.
on_sub({ok, Ref}, St) ->
    _ = reannounce_local(),
    St#st{subref = Ref};
on_sub(_Other, St) ->
    retry_subscribe(St).

retry_subscribe(St) ->
    erlang:send_after(?RESUB_MS, self(), subscribe),
    St#st{subref = undefined}.

on_announcement(F) when is_map(F) ->
    case mget(type, F) of
        Type when Type =:= <<"entity_announced">>; Type =:= entity_announced ->
            upsert_from_fact(mget(did, F), F);
        _ ->
            ok
    end;
on_announcement(_) ->
    ok.

upsert_from_fact(Did, F) when is_binary(Did) ->
    hecate_spartan_mesh_entities:upsert(
        #{did => Did,
          entity_name => mget(entity_name, F),
          home => mget(home, F),
          locale => mget(locale, F),
          online => mget(online, F) =:= true,
          registered_at => reg_at(mget(registered_at, F)),
          last_seen => erlang:system_time(millisecond)});
upsert_from_fact(_Did, _F) ->
    ok.

%% Peers running an older build announce without registered_at; treat them as
%% the oldest possible claim so a dated announcement never unseats a live one.
reg_at(At) when is_integer(At) -> At;
reg_at(_)                      -> 0.

%% Re-publish announcements for this instance's locally-homed entities so peers'
%% registries self-heal after churn.
reannounce_local() ->
    Home = safe_service_did(),
    case Home of
        undefined -> ok;
        _ -> [announce(Home, E) || E <- hecate_spartan_entities:all()], ok
    end.

announce(Home, Entry) ->
    Data = #{did => maps:get(did, Entry, undefined),
             entity_name => maps:get(entity_name, Entry, undefined),
             registered_at => maps:get(registered_at, Entry, 0)},
    case {hecate_om:macula_client(), hecate_om_identity:realm()} of
        {{ok, Pool}, {ok, Realm}} ->
            catch macula:publish(Pool, Realm, hecate_spartan_society:topic(<<"registry">>),
                                 maybe_register_entity:fact(Data, Home)),
            ok;
        _ ->
            ok
    end.

safe_service_did() ->
    try hecate_spartan_identity:service_did() catch _:_ -> undefined end.

mget(AtomKey, Map) ->
    maps:get(AtomKey, Map, maps:get(atom_to_binary(AtomKey, utf8), Map, undefined)).
