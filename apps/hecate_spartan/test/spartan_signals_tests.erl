%%% @doc The stimulus contract: a sensor's structured metadata becomes a
%%% closed-vocabulary SIGNAL line the mind reasons on, and the assembler renders
%%% it just above the trigger. Peer speech (no metadata) yields no signal.
-module(spartan_signals_tests).

-include_lib("eunit/include/eunit.hrl").

news_fact() ->
    #{type => news_item, from => <<"hecate-news">>, body => <<"[NEWS] …">>,
      topic_class => <<"conflict">>, reporting_country_name => <<"France">>,
      source_type => <<"broadcaster">>, subject_country_name => <<"Ukraine">>}.

full_signal_test() ->
    S = spartan_mind:news_signals(news_fact()),
    ?assertEqual(<<"conflict · reported by France (broadcaster) · about Ukraine"/utf8>>, S).

general_topic_is_dropped_test() ->
    S = spartan_mind:news_signals((news_fact())#{topic_class => <<"general">>}),
    ?assertEqual(<<"reported by France (broadcaster) · about Ukraine"/utf8>>, S).

no_subject_country_test() ->
    S = spartan_mind:news_signals((news_fact())#{subject_country_name => <<>>}),
    ?assertEqual(<<"conflict · reported by France (broadcaster)"/utf8>>, S).

peer_speech_has_no_signal_test() ->
    %% An agora post carries no sensor metadata -> empty signal, no SIGNAL block.
    ?assertEqual(<<>>, spartan_mind:news_signals(#{from => <<"athena">>, body => <<"a thought">>})).

non_map_is_safe_test() ->
    ?assertEqual(<<>>, spartan_mind:news_signals(not_a_map)).

binary_keys_from_cbor_test() ->
    %% After a CBOR round-trip a fact's keys may be binaries; mget tries both.
    F = #{<<"topic_class">> => <<"economy">>, <<"reporting_country_name">> => <<"Belgium">>,
          <<"source_type">> => <<"broadcaster">>, <<"subject_country_name">> => <<>>},
    ?assertEqual(<<"economy · reported by Belgium (broadcaster)"/utf8>>,
                 spartan_mind:news_signals(F)).

assembler_renders_signal_above_trigger_test() ->
    [Msg | _] = lists:reverse(context_assembler:render(#{
        soul => #{name => <<"a">>, did => <<"did:x">>},
        trigger => <<"the headline">>,
        signals => <<"conflict · about Ukraine"/utf8>>})),
    #{role := <<"user">>, content := C} = Msg,
    ?assertEqual(<<"SIGNAL: conflict · about Ukraine\n\nthe headline"/utf8>>, C).

assembler_no_signal_is_bare_trigger_test() ->
    [Msg | _] = lists:reverse(context_assembler:render(#{
        soul => #{name => <<"a">>, did => <<"did:x">>},
        trigger => <<"the headline">>, signals => <<>>})),
    #{role := <<"user">>, content := C} = Msg,
    ?assertEqual(<<"the headline">>, C).
