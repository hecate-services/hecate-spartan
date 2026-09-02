%%% @doc Tests for citizen_registration: the wire-contract byte layout
%%% (must match hecate-citizens' own citizen_ownership_proof:message/3
%%% independently -- there's no shared library between the two repos)
%%% and the dark-mesh degrade path (hecate_om isn't running under
%%% eunit, same as embedder.erl's own tests rely on).
-module(citizen_registration_tests).
-include_lib("eunit/include/eunit.hrl").

reregister_ms_default_test() ->
    application:unset_env(hecate_spartan, citizen_reregister_ms),
    ?assertEqual(300_000, citizen_registration:reregister_ms()).

reregister_ms_override_test() ->
    application:set_env(hecate_spartan, citizen_reregister_ms, 60_000),
    ?assertEqual(60_000, citizen_registration:reregister_ms()),
    application:unset_env(hecate_spartan, citizen_reregister_ms).

register_never_crashes_on_a_dark_mesh_test() ->
    {Pub, Priv} = crypto:generate_key(eddsa, ed25519),
    ?assertEqual(ok, citizen_registration:register(<<"test-mind">>, Priv, Pub)).

%% The actual cross-repo contract: a signature this module produces
%% must verify with the exact primitive hecate-citizens' own
%% citizen_ownership_proof:verify/3 uses (crypto:verify(eddsa, none,
%% Msg, Sig, [Pub, ed25519]) under macula_identity:verify/3), over the
%% exact byte layout its own message/3 builds: <<CitizenDid/binary,
%% Timestamp:64/big, Procedure/binary>>, CitizenDid the raw 32-byte
%% pubkey. Reconstructed here independently, not by calling back into
%% citizen_registration:message/2 -- that would only prove the module
%% agrees with itself, not with the other repo.
message_signature_verifies_against_the_citizens_side_layout_test() ->
    {Pub, Priv} = crypto:generate_key(eddsa, ed25519),
    Ts = 1_788_300_000_000,
    Procedure = <<"hecate_citizens.register_presence">>,
    ExpectedMsg = <<Pub/binary, Ts:64/big, Procedure/binary>>,
    ?assertEqual(ExpectedMsg, citizen_registration:message(Pub, Ts)),
    Sig = crypto:sign(eddsa, none, citizen_registration:message(Pub, Ts), [Priv, ed25519]),
    ?assert(crypto:verify(eddsa, none, ExpectedMsg, Sig, [Pub, ed25519])).

%% A signature bound to this procedure must not verify against a
%% different one -- the whole point of including Procedure in the
%% signed message (documented in both this module and
%% citizen_ownership_proof: a proof minted for register_presence can't
%% be replayed against any other gated capability).
message_is_bound_to_its_procedure_test() ->
    {Pub, Priv} = crypto:generate_key(eddsa, ed25519),
    Ts = 1_788_300_000_000,
    Sig = crypto:sign(eddsa, none, citizen_registration:message(Pub, Ts), [Priv, ed25519]),
    OtherProcedure = <<"some.other_procedure">>,
    OtherProcedureMsg = <<Pub/binary, Ts:64/big, OtherProcedure/binary>>,
    ?assertNot(crypto:verify(eddsa, none, OtherProcedureMsg, Sig, [Pub, ed25519])).
