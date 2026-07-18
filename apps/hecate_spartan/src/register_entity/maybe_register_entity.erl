%%% @doc Handler for the register_entity command.
%%%
%%% Store-free (4a): dispatch performs the registration DIRECTLY — upsert the
%%% local `entities' row, upsert the `mesh_entities' row (home = this instance),
%%% and publish the `entity_announced' FACT so peers learn the entity and where it
%%% is homed. No aggregate, no event store, no projection.
%%%
%%% Idempotency lives here now, not in a folded aggregate: an entity already in
%%% the local registry is NOT re-announced, and dispatch returns
%%% `{error, already_registered}' so the ingress still refreshes the entity's
%%% UCAN (re-registration is how a member renews its token).
%%%
%%% `handle/1' + `handle_from_map/1' remain as the pure validate-and-emit step.
%%% `row/1' is the registry row builder (shared with the table owners' boot
%%% replay); `fact/2' + `topic/0' are the public announcement contract (shared
%%% with federation_registry's re-announce timer).
%%%
%%% Proof-of-possession (the entity's signature over the registration challenge)
%%% is an authentication concern enforced at the ingress edge before dispatch.
-module(maybe_register_entity).

-export([handle/1, handle_from_map/1, dispatch/1, row/1, fact/2, topic/0]).

-spec handle_from_map(map()) -> {ok, [map()]} | {error, term()}.
handle_from_map(#{entity_name := Name, did := Did, pubkey := PubKey} = Payload) ->
    At = maps:get(registered_at, Payload, erlang:system_time(millisecond)),
    handle(register_entity_v1:new(Name, Did, PubKey, At));
handle_from_map(_) ->
    {error, missing_fields}.

-spec handle(register_entity_v1:register_entity_v1()) ->
    {ok, [map()]} | {error, term()}.
handle(Command) ->
    #{entity_name := Name, did := Did, pubkey := PubKey,
      registered_at := At} = register_entity_v1:to_map(Command),
    case validate(Name, Did, PubKey) of
        ok ->
            Event = entity_registered_v1:new(Name, Did, PubKey, At),
            {ok, [entity_registered_v1:to_map(Event)]};
        {error, Reason} ->
            {error, Reason}
    end.

%% @doc Register an entity, store-free. Idempotent by DID: a repeat is rejected
%% with `already_registered' (the ingress refreshes the UCAN on that path).
%% Returns the legacy `{ok, Seq, Events}' shape so callers are untouched.
-spec dispatch(register_entity_v1:register_entity_v1()) ->
    {ok, non_neg_integer(), [map()]} | {error, term()}.
dispatch(Cmd) ->
    #{entity_name := Name, did := Did, pubkey := PubKey,
      registered_at := At} = register_entity_v1:to_map(Cmd),
    case validate(Name, Did, PubKey) of
        ok ->
            do_register(Did, #{entity_name => Name, did => Did,
                               pubkey => PubKey, registered_at => At});
        {error, _} = E ->
            E
    end.

%% @doc The registry row an entity registration becomes. Exported so the table
%% owners (`hecate_spartan_entities', `hecate_spartan_mesh_entities') rebuild
%% identical rows when they replay whatever log survives at boot.
-spec row(map()) -> {binary(), map()}.
row(Data) ->
    Did = gf(did, Data),
    At = gf(registered_at, Data),
    {Did, #{
        did           => Did,
        entity_name   => gf(entity_name, Data),
        pubkey        => gf(pubkey, Data),
        status        => 1,
        registered_at => At,
        last_seen     => At
    }}.

-spec topic() -> binary().
topic() -> hecate_spartan_society:topic(<<"registry">>).

%% @doc The public announcement contract. `registered_at' travels with it: a peer
%% uses it to decide which DID currently holds a name when an entity has
%% re-registered under a new key.
-spec fact(map(), binary()) -> map().
fact(Data, Home) ->
    #{type        => entity_announced,
      did         => gf(did, Data),
      entity_name => gf(entity_name, Data),
      home        => Home,
      locale      => hecate_spartan_service:locale(),
      %% PRESENCE, not registration. The registry never forgets an entity, so a
      %% roster built from registrations lists every probe and every dead demo
      %% that ever said hello. A mind that is actually running holds an open
      %% receive stream; that is the only honest answer to "is anybody there".
      online      => safe_online(gf(did, Data)),
      registered_at => gf(registered_at, Data),
      announced_at => erlang:system_time(millisecond)}.

%% --- Internal ---

%% Internal — Ed25519 public keys are 32 raw bytes.
validate(Name, Did, PubKey) ->
    case {byte_size(Name), byte_size(Did), byte_size(PubKey)} of
        {0, _, _}  -> {error, entity_name_required};
        {_, 0, _}  -> {error, did_required};
        {_, _, 32} -> ok;
        {_, _, _}  -> {error, invalid_pubkey}
    end.

do_register(Did, Data) ->
    already_or_register(hecate_spartan_entities:get(Did), Data).

already_or_register({ok, _Existing}, _Data) ->
    {error, already_registered};
already_or_register({error, not_found}, Data) ->
    {Did, Entry} = row(Data),
    ok = hecate_spartan_entities:upsert(Did, Entry),
    ok = announce(Data),
    {ok, 0, [Data]}.

%% Two effects, exactly as the old announce PM: seed this instance's own
%% `mesh_entities' row (a node's mesh publishes may not loop back to itself), and
%% publish the announcement so peers learn the entity.
announce(Data) ->
    Home = hecate_spartan_identity:service_did(),
    hecate_spartan_mesh_entities:upsert(
        #{did => gf(did, Data),
          entity_name => gf(entity_name, Data),
          home => Home,
          locale => hecate_spartan_service:locale(),
          registered_at => gf(registered_at, Data),
          last_seen => erlang:system_time(millisecond)}),
    _ = publish_fact(Data, Home),
    ok.

safe_online(Did) when is_binary(Did) ->
    try hecate_spartan_inbox:online(Did) catch _:_ -> false end;
safe_online(_) ->
    false.

%% Dark is the expected degraded state: no mesh client, no realm, or the
%% hecate_om identity server not up yet. While dark the entity is registered
%% locally; peers learn it on the next federation re-announce.
publish_fact(Data, Home) ->
    try {hecate_om:macula_client(), hecate_om_identity:realm()} of
        {{ok, Pool}, {ok, Realm}} ->
            catch macula:publish(Pool, Realm, topic(), fact(Data, Home)),
            ok;
        _DarkOrNoRealm ->
            ok
    catch _:_ ->
        ok
    end.

gf(AtomKey, Data) ->
    maps:get(AtomKey, Data, maps:get(atom_to_binary(AtomKey, utf8), Data, undefined)).
