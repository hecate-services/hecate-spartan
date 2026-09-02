%%% @doc Announces a mind's identity to the shared, mesh-wide citizens
%%% directory (`hecate-citizens'), so it is addressable there the same
%%% way a human (via macula-passport) or a service is.
%%%
%%% Spartan's own entity registry (`maybe_register_entity') is a
%%% different, narrower thing: spartan's own local society, its own
%%% capability set (msg/agora/activity), federated only between spartan
%%% instances. `hecate-citizens' is the mesh-wide directory every
%%% service can query -- `hecate-mail' delegates work to a citizen_did
%%% it finds there, for instance. A mind is both: a spartan entity AND
%%% a citizen.
%%%
%%% `hecate_citizens.register_presence' is gated behind proof of DID
%%% possession (`citizen_ownership_proof' on that side): a signature
%%% over `{citizen_did, timestamp, procedure}', bound to this specific
%%% procedure so it can't be replayed against any other gated
%%% capability that service adds later. Only the mind itself, holding
%%% its own private key, can produce that proof -- nothing else in
%%% either codebase can register a mind as a citizen on its behalf.
%%% That's why this call is keyed off the mind's own live state
%%% (spartan_mind.erl calls in), not a passive listener reacting to
%%% `entity_announced': that fact carries no signature at all, and even
%%% if it did, it would be bound to `spartan.register_entity', not
%%% this procedure.
%%%
%%% `citizen_did' on the wire is the mind's raw 32-byte Ed25519 public
%%% key, hex-encoded -- not the `did:macula:spartan:...' string
%%% `spartan_mind:did/1' builds for spartan's own local use. hecate-
%%% citizens' own `citizen_read_model' keys directly on the raw pubkey,
%%% matching macula's own node_id convention.
%%%
%%% Citizenship here is presence, not identity: entries expire, so a
%%% mind re-announces on `?DEFAULT_REREGISTER_MS', roughly a 4x margin
%%% under hecate-citizens' own ~20-minute default TTL (the same
%%% republish-to-TTL ratio its own `register_presence_responder'
%%% documents) -- a mind that stops calling ages out on its own, no
%%% action needed either side.
-module(citizen_registration).

-export([register/3, reregister_ms/0]).
%% Exported for the cross-repo wire-contract test: this exact byte
%% layout must match hecate-citizens' own citizen_ownership_proof's
%% independently.
-export([message/2]).

-define(PROCEDURE, <<"hecate_citizens.register_presence">>).
-define(TIMEOUT_MS, 8000).
-define(DEFAULT_REREGISTER_MS, 300_000).
%% First cut: a mind can be asked to talk, today. A richer per-mind
%% offer list is a natural fit for L1/L2 self-modification later --
%% not invented here unbacked by any actual capability.
-define(OFFERS, [<<"conversation">>]).

-spec reregister_ms() -> pos_integer().
reregister_ms() ->
    application:get_env(hecate_spartan, citizen_reregister_ms, ?DEFAULT_REREGISTER_MS).

%% @doc Register (or refresh) a mind's presence in the citizens
%% directory. Always returns `ok' -- a dark mesh, a timeout, or a
%% rejected proof all degrade to a logged warning, never a crash; the
%% caller's own periodic re-registration is the retry.
%%
%% Guarded: the client/realm lookups themselves exit with `noproc' when
%% `hecate_om_identity' isn't running (e.g. under eunit) -- same gotcha
%% embedder.erl's own mesh path is guarded against, and the exact one
%% this module's own dark-mesh test caught before this try/catch was
%% added.
-spec register(Name :: binary(), Priv :: binary(), Pub :: binary()) -> ok.
register(Name, Priv, Pub) ->
    logged(mesh_register(Name, Priv, Pub)),
    ok.

mesh_register(Name, Priv, Pub) ->
    try call(hecate_om:macula_client(), hecate_om_identity:realm(), Name, Priv, Pub)
    catch _:_ -> dark
    end.

call({ok, Pool}, {ok, Realm}, Name, Priv, Pub) ->
    catch macula:call(Pool, Realm, ?PROCEDURE, payload(Name, Priv, Pub), ?TIMEOUT_MS);
call(_Client, _Realm, _Name, _Priv, _Pub) ->
    dark.

payload(Name, Priv, Pub) ->
    Ts = erlang:system_time(millisecond),
    Sig = crypto:sign(eddsa, none, message(Pub, Ts), [Priv, ed25519]),
    #{
        citizen_did => binary:encode_hex(Pub, lowercase),
        citizen_kind => <<"agent">>,
        display_name => Name,
        offers => ?OFFERS,
        proof => #{
            timestamp => Ts,
            signature => binary:encode_hex(Sig, lowercase)
        }
    }.

%% Must match hecate-citizens' own `citizen_ownership_proof:message/3'
%% byte for byte: the raw 32-byte pubkey, then the millisecond
%% timestamp as a big-endian 64-bit integer, then the procedure name --
%% bound to this specific capability so a proof can't be replayed
%% elsewhere.
message(Pub, Ts) ->
    <<Pub/binary, Ts:64/big, ?PROCEDURE/binary>>.

logged(dark) ->
    ok;
logged({ok, Reply}) when is_map(Reply) ->
    log_reply(gf(ok, Reply));
logged(Other) ->
    logger:warning("[citizen_registration] register_presence failed: ~p", [Other]).

log_reply(1) ->
    ok;
log_reply(_NotAccepted) ->
    logger:warning("[citizen_registration] register_presence rejected").

gf(Key, Map) ->
    maps:get(Key, Map, maps:get(atom_to_binary(Key, utf8), Map, undefined)).
