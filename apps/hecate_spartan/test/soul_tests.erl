%%% @doc Tests for the Soul spine: the fold reconstructs a self from its event
%%% stream, the aggregate guards birth, and the assembled context is driven by
%%% the founding brief. These are pure (no live store): they prove the
%%% decoupled-identity logic that the full kill-and-restart integration test
%%% exercises end to end.
-module(soul_tests).

-include_lib("eunit/include/eunit.hrl").

did() -> <<"did:macula:spartan:ABCDEF">>.

%% An event stream as read_all would return it: flat maps with an atom
%% event_type key (the envelope) plus the business fields.
born_event() ->
    mind_born_v1:to_map(mind_born_v1:new(
        #{did => did(), name => <<"athena">>, pubkey => <<0:256>>,
          founding_brief => <<"You watch the mesh for threats.">>,
          genesis_version => <<"1">>})).

charter_event(Stmt) ->
    charter_amended_v1:to_map(charter_amended_v1:new(
        #{did => did(), entry_type => <<"principle">>, statement => Stmt,
          derivation => <<"reasoned">>})).

fold(Events) ->
    Folded = lists:foldl(fun(E, Acc) -> soul_state:apply_event(Acc, E) end,
                         soul_state:new(<<>>), Events),
    soul_state:to_map(Folded).

%% --- the fold reconstructs a self ---

replay_reconstructs_identity_test() ->
    Soul = fold([born_event()]),
    ?assertEqual(<<"athena">>, maps:get(name, Soul)),
    ?assertEqual(did(), maps:get(did, Soul)),
    ?assertEqual(<<"You watch the mesh for threats.">>,
                 maps:get(founding_brief, Soul)),
    ?assert(maps:get(status, Soul) band 1 =/= 0).

%% The proof: an amendment made in one life is present after replay in the next.
amendment_survives_replay_test() ->
    Stream = [born_event(), charter_event(<<"Speak plainly.">>)],
    Soul = fold(Stream),
    [Entry] = maps:get(charter, Soul),
    ?assertEqual(<<"Speak plainly.">>, maps:get(statement, Entry)).

accretion_is_ordered_test() ->
    Stream = [born_event(),
              charter_event(<<"first">>),
              charter_event(<<"second">>)],
    Soul = fold(Stream),
    Stmts = [maps:get(statement, E) || E <- maps:get(charter, Soul)],
    ?assertEqual([<<"first">>, <<"second">>], Stmts).

%% --- the aggregate guards birth ---

birth_is_idempotent_test() ->
    Fresh = soul_state:new(<<>>),
    BearCmd = #{command_type => <<"bear_mind">>, did => did(),
                name => <<"athena">>, pubkey => <<0:256>>,
                founding_brief => <<"brief">>, genesis_version => <<"1">>},
    ?assertMatch({ok, [_]}, soul_aggregate:execute(Fresh, BearCmd)),
    Born = soul_state:apply_event(Fresh, born_event()),
    ?assertEqual({error, already_born}, soul_aggregate:execute(Born, BearCmd)).

%% --- the stream id is reckon-db shaped ---

stream_id_shape_test() ->
    Id = soul_aggregate:stream_id(did()),
    ?assertMatch({match, _}, re:run(Id, "^soul-[a-f0-9]{32}$")).

%% --- the founding brief drives the assembled context ---

context_carries_the_brief_test() ->
    Soul = fold([born_event(), charter_event(<<"Speak plainly.">>)]),
    Msgs = context_assembler:render(
             #{soul => Soul, trigger => <<"hello">>,
               chronicle => [], scratchpad => <<>>, memories => [],
               hud => <<"[HUD] turn=0">>}),
    Blob = iolist_to_binary([maps:get(content, M) || M <- Msgs]),
    ?assert(contains(Blob, <<"You watch the mesh for threats.">>)),
    ?assert(contains(Blob, <<"Speak plainly.">>)),
    ?assert(contains(Blob, <<"hello">>)),
    %% last message is the trigger, as a user turn
    Last = lists:last(Msgs),
    ?assertEqual(<<"user">>, maps:get(role, Last)).

contains(Hay, Needle) -> binary:match(Hay, Needle) =/= nomatch.
