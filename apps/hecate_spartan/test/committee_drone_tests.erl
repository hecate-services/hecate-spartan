%%% @doc Tests for a committee drone's pure surface: the prompt it builds for
%%% its own turn (its lens, its question, and the transcript it has overheard
%%% so far). The live half — subscribing to the topic, reasoning off-process,
%%% publishing its own contribution — is integration; here we cover everything
%%% that can be reasoned about without a backend or a store.
-module(committee_drone_tests).

-include_lib("eunit/include/eunit.hrl").

first_drone_is_invited_to_open_test() ->
    Drone = hd(committee:pick_drones(1)),
    [Sys, Usr] = committee_drone:messages(Drone, <<"What now?">>, []),
    ?assertEqual(<<"system">>, maps:get(<<"role">>, Sys)),
    ?assertEqual(<<"user">>, maps:get(<<"role">>, Usr)),
    ?assertNotEqual(nomatch, binary:match(maps:get(<<"content">>, Sys), <<"What now?">>)),
    ?assertNotEqual(nomatch,
        binary:match(maps:get(<<"content">>, Usr), <<"speak first">>)).

later_drone_sees_the_transcript_it_overheard_test() ->
    Drone = hd(committee:pick_drones(1)),
    T = [#{drone => <<"the operator">>, text => <<"Rotate the key.">>}],
    [_Sys, Usr] = committee_drone:messages(Drone, <<"Q">>, T),
    Content = maps:get(<<"content">>, Usr),
    ?assertNotEqual(nomatch, binary:match(Content, <<"Rotate the key.">>)),
    ?assertNotEqual(nomatch, binary:match(Content, <<"Add your view">>)).

speaks_as_the_named_lens_test() ->
    Drone = #{name => <<"the adversary">>,
              lens => <<"You think like the attacker.">>},
    [Sys, _Usr] = committee_drone:messages(Drone, <<"Q">>, []),
    Content = maps:get(<<"content">>, Sys),
    ?assertNotEqual(nomatch, binary:match(Content, <<"Speak as the adversary">>)),
    ?assertNotEqual(nomatch, binary:match(Content, <<"You think like the attacker.">>)).
