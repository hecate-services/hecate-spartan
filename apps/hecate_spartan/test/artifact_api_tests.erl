%%% @doc Tests for artifact content-id decoding (pure).
-module(artifact_api_tests).
-include_lib("eunit/include/eunit.hrl").

valid_mcid_roundtrips_test() ->
    MCID = <<1, 16#55, 0:256>>,      %% 34-byte macula content id
    Hex = binary:encode_hex(MCID, lowercase),
    ?assertEqual({ok, MCID}, artifact_api:decode_mcid(Hex)).

rejects_wrong_prefix_test() ->
    Bad = binary:encode_hex(<<2, 2, 0:256>>, lowercase),
    ?assertEqual(error, artifact_api:decode_mcid(Bad)).

rejects_non_hex_test() ->
    ?assertEqual(error, artifact_api:decode_mcid(<<"not-hex!">>)).

rejects_undefined_test() ->
    ?assertEqual(error, artifact_api:decode_mcid(undefined)).
