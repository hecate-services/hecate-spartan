%%% @doc Tests for the agora — the public square.
-module(publish_to_agora_tests).
-include_lib("eunit/include/eunit.hrl").

%% --- handler (pure domain) ---

emits_post_published_test() ->
    {ok, Cmd} = publish_to_agora_v1:new(
                  #{post_id => <<"p1">>, from => <<"did:key:a">>,
                    body => <<"the wire says Brussels moved">>}),
    {ok, [Event]} = maybe_publish_to_agora:handle(Cmd),
    ?assertEqual(<<"agora_post_published_v1">>, maps:get(event_type, Event)),
    ?assertEqual(<<"did:key:a">>, maps:get(from, Event)),
    ?assertEqual(<<"the wire says Brussels moved">>, maps:get(body, Event)).

empty_body_is_not_speech_test() ->
    {ok, Cmd} = publish_to_agora_v1:new(
                  #{post_id => <<"p1">>, from => <<"did:key:a">>, body => <<>>}),
    ?assertEqual({error, empty_body}, maybe_publish_to_agora:handle(Cmd)).

reply_threading_survives_the_round_trip_test() ->
    {ok, Cmd} = publish_to_agora_v1:new(
                  #{post_id => <<"p2">>, from => <<"did:key:b">>,
                    body => <<"disagree">>, in_reply_to => <<"p1">>}),
    {ok, [Event]} = maybe_publish_to_agora:handle(Cmd),
    ?assertEqual(<<"p1">>, maps:get(in_reply_to, Event)).

%% --- the public fact ---

%% The agora fact is the ONE that carries a body into the open. That is
%% deliberate (the entity chose to speak publicly), so pin it: if someone ever
%% strips the body they break the square, and if someone adds a body to the
%% private inbox facts they break the sovereignty boundary.
fact_carries_the_body_test() ->
    Data = #{post_id => <<"p1">>, from => <<"did:key:a">>,
             body => <<"public words">>, in_reply_to => undefined,
             posted_at => 1720000000000},
    F = maybe_publish_to_agora:fact(Data),
    ?assertEqual(agora_post, maps:get(type, F)),
    ?assertEqual(<<"public words">>, maps:get(body, F)),
    ?assertEqual(<<"did:key:a">>, maps:get(from, F)),
    ?assertEqual(<<"spartan/agora">>, maybe_publish_to_agora:topic()).

%% --- the feed read model ---

feed_test_() ->
    {setup, fun setup/0, fun cleanup/1,
     fun(_) ->
         [ feed_holds_a_post()
         , feed_is_idempotent_by_post_id()
         , feed_returns_newest_first()
         , unknown_post_is_not_found()
         ]
     end}.

setup() ->
    ok = application:unset_env(hecate_spartan, event_store_id),
    {ok, Pid} = hecate_spartan_agora:start_link(),
    ok = hecate_spartan_agora:post(post(<<"p1">>, <<"first">>, 100)),
    ok = hecate_spartan_agora:post(post(<<"p2">>, <<"second">>, 200)),
    %% The same post arriving twice (locally, then over the mesh) lands once.
    ok = hecate_spartan_agora:post(post(<<"p1">>, <<"first">>, 100)),
    #{pid => Pid}.

cleanup(#{pid := Pid}) ->
    gen_server:stop(Pid),
    ok.

post(Id, Body, At) ->
    #{post_id => Id, from => <<"did:key:a">>, body => Body,
      in_reply_to => undefined, posted_at => At}.

feed_holds_a_post() ->
    {ok, P} = hecate_spartan_agora:get(<<"p2">>),
    ?_assertEqual(<<"second">>, maps:get(body, P)).

feed_is_idempotent_by_post_id() ->
    ?_assertEqual(2, hecate_spartan_agora:count()).

feed_returns_newest_first() ->
    [First | _] = hecate_spartan_agora:recent(10),
    ?_assertEqual(<<"p2">>, maps:get(post_id, First)).

unknown_post_is_not_found() ->
    ?_assertEqual({error, not_found}, hecate_spartan_agora:get(<<"ghost">>)).

%% --- capabilities ---

%% Speaking in public is a different power from sending a message, so it is a
%% different capability: an operator can grant one without the other.
agora_caps_are_distinct_test() ->
    Caps = hecate_spartan_identity:entity_caps(<<"realm">>, <<"did:key:a">>),
    Cans = [maps:get(can, C) || C <- Caps],
    ?assert(lists:member(<<"agora/post">>, Cans)),
    ?assert(lists:member(<<"agora/read">>, Cans)),
    ?assert(lists:member(<<"msg/send">>, Cans)).
