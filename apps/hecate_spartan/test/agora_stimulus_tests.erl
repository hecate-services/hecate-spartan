%%% @doc Tests for what a mind was reacting to.
%%%
%%% The whole point of this module is that the MIND never touches it, so
%%% these tests are about one thing: does the shape a sensor published
%%% survive, verbatim, into the shape a post carries. If it does not, the
%%% square's sources are wrong and nobody downstream can tell.
-module(agora_stimulus_tests).
-include_lib("eunit/include/eunit.hrl").

%% Exactly the fact hecate-news publishes (hecate_news_facts:item/1).
news_fact() ->
    #{type                   => news_item,
      item_id                => <<"9f2c1a4e7b8d0356">>,
      source                 => <<"zeit">>,
      title                  => <<"500-Kilo-Bombe in Oranienburg entschärft"/utf8>>,
      summary                => <<"Die Evakuierung betraf 12.000 Menschen."/utf8>>,
      url                    => <<"https://www.zeit.de/2026-09/oranienburg">>,
      image_url              => <<"https://img.zeit.de/oranienburg/wide__1300x731">>,
      lang                   => <<"de">>,
      topics                 => [<<"sicherheit">>, <<"brandenburg">>],
      topic_class            => <<"society">>,
      emoji                  => <<"🏛"/utf8>>,
      reporting_country      => <<"de">>,
      reporting_country_name => <<"Germany">>,
      subject_country        => <<"de">>,
      subject_country_name   => <<"Germany">>,
      source_type            => <<"private">>,
      published_at           => 1788344000000,
      fetched_at             => 1788344100000,
      from                   => <<"hecate-news">>,
      body                   => <<"[NEWS] 🏛 [society] 500-Kilo-Bombe …"/utf8>>}.

%% --- reading a sensor fact ---

carries_every_field_a_reader_wants_test() ->
    S = agora_stimulus:of_fact(news_fact()),
    ?assertEqual(<<"9f2c1a4e7b8d0356">>, maps:get(item_id, S)),
    ?assertEqual(<<"zeit">>, maps:get(source, S)),
    ?assertEqual(<<"private">>, maps:get(source_type, S)),
    ?assertEqual(<<"society">>, maps:get(topic_class, S)),
    ?assertEqual([<<"sicherheit">>, <<"brandenburg">>], maps:get(topics, S)),
    ?assertEqual(<<"https://img.zeit.de/oranienburg/wide__1300x731">>,
                 maps:get(image_url, S)),
    ?assertEqual(1788344000000, maps:get(published_at, S)).

%% The reader wants what the story is ABOUT. Who reported it is already told,
%% and told better, by `source'.
country_is_the_subject_not_the_reporter_test() ->
    S = agora_stimulus:of_fact((news_fact())#{subject_country_name => <<"Ukraine">>,
                                              reporting_country_name => <<"Italy">>}),
    ?assertEqual(<<"Ukraine">>, maps:get(country, S)).

%% The gazetteer places most stories and not all of them. An unplaced story is
%% still a story.
unplaced_story_has_no_country_test() ->
    S = agora_stimulus:of_fact((news_fact())#{subject_country_name => <<>>}),
    ?assertEqual(<<>>, maps:get(country, S)).

%% 21 of 47 live sources publish no picture at all. That must be an absent
%% field, never a broken one.
picture_is_optional_test() ->
    S = agora_stimulus:of_fact(maps:remove(image_url, news_fact())),
    ?assertEqual(<<>>, maps:get(image_url, S)).

%% --- what is NOT a stimulus ---

unprompted_speech_carries_none_test() ->
    ?assertEqual(undefined, agora_stimulus:of_fact(#{})),
    ?assertEqual(undefined, agora_stimulus:of_fact(#{body => <<"a self-alert">>})),
    ?assertEqual(undefined, agora_stimulus:of_fact(not_a_map)),
    ?assertEqual(undefined, agora_stimulus:of_fact(undefined)).

%% A fact with no item_id cannot be grouped into a thread, which is the whole
%% job, so it is refused rather than half-carried.
no_item_id_is_no_stimulus_test() ->
    ?assertEqual(undefined,
                 agora_stimulus:of_fact(maps:remove(item_id, news_fact()))),
    ?assertEqual(undefined,
                 agora_stimulus:of_fact((news_fact())#{item_id => <<>>})).

%% --- inheritance: a conversation stays on its story ---

%% Two minds arguing about the same bomb are on the same story. When mind B
%% reasons about mind A's POST rather than about the news item, the thread must
%% survive: B inherits A's stimulus.
peer_post_inherits_the_story_test() ->
    Sensed = agora_stimulus:of_fact(news_fact()),
    PeerPost = #{type => agora_post, post_id => <<"p1">>,
                 from => <<"did:macula:spartan:A">>,
                 body => <<"the evacuation radius is the story">>,
                 posted_at => 1788344200000,
                 stimulus => Sensed},
    ?assertEqual(Sensed, agora_stimulus:of_fact(PeerPost)).

%% A peer's post that carried no stimulus (unprompted speech) hands on nothing.
peer_post_without_a_story_inherits_nothing_test() ->
    ?assertEqual(undefined,
                 agora_stimulus:of_fact(#{type => agora_post,
                                          post_id => <<"p1">>,
                                          body => <<"unprompted">>})).

%% --- wire hazards ---

%% Keys arrive as atoms or binaries in the SAME map, depending on what the
%% receiving VM happens to know, and values arrive `{text, _}'-tagged from
%% anything that tags on the way out.
binary_keys_and_tagged_text_survive_test() ->
    S = agora_stimulus:of_fact(#{<<"item_id">>     => {text, <<"abc">>},
                                 <<"source">>      => {text, <<"ansa">>},
                                 title             => {text, <<"Un titolo"/utf8>>},
                                 <<"topics">>      => [{text, <<"energia">>}],
                                 <<"published_at">> => 1788344000000}),
    ?assertEqual(<<"abc">>, maps:get(item_id, S)),
    ?assertEqual(<<"ansa">>, maps:get(source, S)),
    ?assertEqual(<<"Un titolo"/utf8>>, maps:get(title, S)),
    ?assertEqual([<<"energia">>], maps:get(topics, S)).

junk_shapes_become_empty_not_crashes_test() ->
    S = agora_stimulus:of_fact(#{item_id      => <<"abc">>,
                                 title        => 42,
                                 topics       => <<"not-a-list">>,
                                 published_at => <<"yesterday">>}),
    ?assertEqual(<<>>, maps:get(title, S)),
    ?assertEqual([], maps:get(topics, S)),
    ?assertEqual(0, maps:get(published_at, S)).

drops_empty_tags_rather_than_shipping_blanks_test() ->
    S = agora_stimulus:of_fact(#{item_id => <<"abc">>,
                                 topics  => [<<"energy">>, <<>>, {text, <<>>}]}),
    ?assertEqual([<<"energy">>], maps:get(topics, S)).

%% --- to_wire: absent and empty are different claims ---

unprompted_post_carries_no_stimulus_key_test() ->
    ?assertEqual(#{}, agora_stimulus:to_wire(undefined)).

prompted_post_carries_it_under_one_key_test() ->
    S = agora_stimulus:of_fact(news_fact()),
    ?assertEqual(#{stimulus => S}, agora_stimulus:to_wire(S)).
