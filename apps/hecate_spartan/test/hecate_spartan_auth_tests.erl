%%% @doc Tests for UCAN bearer authentication + capability checks.
-module(hecate_spartan_auth_tests).
-include_lib("eunit/include/eunit.hrl").

auth_roundtrip_test() ->
    Dir = "/tmp/hs_auth_" ++ integer_to_list(erlang:unique_integer([positive])),
    ok = filelib:ensure_dir(filename:join(Dir, "x")),
    application:set_env(hecate_spartan, data_dir, Dir),
    Pid = case hecate_spartan_identity:start_link() of
        {ok, P}                       -> P;
        {error, {already_started, P}} -> P
    end,

    {ok, Ucan} = hecate_spartan_identity:mint_entity_ucan(
                   <<"did:key:e1">>, <<"io.macula.spartans">>),

    {ok, Aud, Payload} = hecate_spartan_auth:authenticate_token(Ucan),
    ?assertEqual(<<"did:key:e1">>, Aud),
    ?assert(hecate_spartan_auth:has_cap(Payload, <<"msg/send">>)),
    ?assert(hecate_spartan_auth:has_cap(Payload, <<"msg/recv">>)),
    ?assertNot(hecate_spartan_auth:has_cap(Payload, <<"msg/nope">>)),

    ?assertEqual({error, invalid_ucan},
                 hecate_spartan_auth:authenticate_token(<<"not.a.ucan">>)),

    gen_server:stop(Pid),
    os:cmd("rm -rf " ++ Dir).
