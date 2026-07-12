%%% @doc Tests for the pure registration-verification at the ingress edge.
-module(register_entity_api_tests).
-include_lib("eunit/include/eunit.hrl").

%% Build a well-formed, correctly-signed registration request map.
signed_request(Did, Name) ->
    {ok, {Pub, Priv}} = macula_crypto_nif:generate_keypair(),
    Ts = <<"1720000000">>,
    Challenge = hecate_spartan_identity:registration_challenge(Did, Ts),
    {ok, Sig} = macula_crypto_nif:sign(Challenge, Priv),
    {#{<<"entity_name">> => Name,
       <<"did">> => Did,
       <<"pubkey">> => base64:encode(Pub),
       <<"signature">> => base64:encode(Sig),
       <<"ts">> => Ts}, Pub}.

valid_request_verifies_test() ->
    {Req, _Pub} = signed_request(<<"did:key:alpha">>, <<"Alpha">>),
    {ok, Fields} = register_entity_api:verify_registration(Req),
    ?assertEqual(<<"did:key:alpha">>, maps:get(did, Fields)),
    ?assertEqual(<<"Alpha">>, maps:get(entity_name, Fields)),
    ?assertEqual(32, byte_size(maps:get(pubkey, Fields))),
    ?assert(is_integer(maps:get(registered_at, Fields))).

forged_signature_rejected_test() ->
    {Req0, _Pub} = signed_request(<<"did:key:alpha">>, <<"Alpha">>),
    %% Swap in a signature from a different key.
    {ok, {_P2, Attacker}} = macula_crypto_nif:generate_keypair(),
    Challenge = hecate_spartan_identity:registration_challenge(<<"did:key:alpha">>,
                                                               <<"1720000000">>),
    {ok, Forged} = macula_crypto_nif:sign(Challenge, Attacker),
    Req = Req0#{<<"signature">> => base64:encode(Forged)},
    ?assertEqual({error, bad_signature},
                 register_entity_api:verify_registration(Req)).

wrong_pubkey_length_rejected_test() ->
    {Req0, _} = signed_request(<<"did:key:alpha">>, <<"Alpha">>),
    Req = Req0#{<<"pubkey">> => base64:encode(<<"short">>)},
    ?assertEqual({error, invalid_pubkey},
                 register_entity_api:verify_registration(Req)).

missing_fields_rejected_test() ->
    ?assertEqual({error, missing_fields},
                 register_entity_api:verify_registration(#{<<"did">> => <<"did:key:x">>})).

tampered_challenge_rejected_test() ->
    %% Sign the right challenge, then claim a different ts — signature no
    %% longer matches the reconstructed challenge.
    {Req0, _} = signed_request(<<"did:key:alpha">>, <<"Alpha">>),
    Req = Req0#{<<"ts">> => <<"9999999999">>},
    ?assertEqual({error, bad_signature},
                 register_entity_api:verify_registration(Req)).
