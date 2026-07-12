%%% @doc Tests for service identity + UCAN issuance.
-module(hecate_spartan_identity_tests).
-include_lib("eunit/include/eunit.hrl").

identity_test_() ->
    {setup, fun setup/0, fun cleanup/1,
     fun(_) ->
         [ did_is_stable()
         , mint_and_verify_roundtrip()
         , caps_are_realm_scoped()
         , entity_sig_roundtrip()
         , rejects_forged_signature()
         ]
     end}.

setup() ->
    Dir = filename:join(["/tmp",
                         "hecate_spartan_test_" ++ integer_to_list(erlang:unique_integer([positive]))]),
    ok = filelib:ensure_dir(filename:join(Dir, "x")),
    application:set_env(hecate_spartan, data_dir, Dir),
    {ok, Pid} = hecate_spartan_identity:start_link(),
    #{pid => Pid, dir => Dir}.

cleanup(#{pid := Pid, dir := Dir}) ->
    gen_server:stop(Pid),
    os:cmd("rm -rf " ++ Dir),
    ok.

did_is_stable() ->
    Did = hecate_spartan_identity:service_did(),
    ?_assertMatch(<<"did:macula:spartan:", _/binary>>, Did).

mint_and_verify_roundtrip() ->
    Realm = <<"io.macula.spartans">>,
    EntityDid = <<"did:key:entity-alpha">>,
    {ok, Token} = hecate_spartan_identity:mint_entity_ucan(EntityDid, Realm),
    {ok, Payload} = hecate_spartan_identity:verify_ucan(Token),
    Issuer = maps:get(<<"iss">>, Payload, maps:get(iss, Payload, undefined)),
    Audience = maps:get(<<"aud">>, Payload, maps:get(aud, Payload, undefined)),
    [ ?_assert(is_binary(Token))
    , ?_assertEqual(hecate_spartan_identity:service_did(), Issuer)
    , ?_assertEqual(EntityDid, Audience) ].

caps_are_realm_scoped() ->
    Caps = hecate_spartan_identity:entity_caps(<<"io.macula.spartans">>,
                                               <<"did:key:e1">>),
    Withs = [maps:get(with, C) || C <- Caps],
    Recv = <<"spartan/io.macula.spartans/inbox/did:key:e1">>,
    [ ?_assertEqual(4, length(Caps))
    , ?_assert(lists:member(Recv, Withs)) ].

entity_sig_roundtrip() ->
    {ok, {Pub, Priv}} = macula_crypto_nif:generate_keypair(),
    Msg = hecate_spartan_identity:registration_challenge(<<"did:key:e1">>,
                                                          <<"1720000000">>),
    {ok, Sig} = macula_crypto_nif:sign(Msg, Priv),
    ?_assert(hecate_spartan_identity:verify_entity_sig(Msg, Sig, Pub)).

rejects_forged_signature() ->
    {ok, {Pub, _Priv}} = macula_crypto_nif:generate_keypair(),
    {ok, {_P2, Attacker}} = macula_crypto_nif:generate_keypair(),
    Msg = hecate_spartan_identity:registration_challenge(<<"did:key:e1">>,
                                                          <<"1720000000">>),
    {ok, ForgedSig} = macula_crypto_nif:sign(Msg, Attacker),
    ?_assertNot(hecate_spartan_identity:verify_entity_sig(Msg, ForgedSig, Pub)).
