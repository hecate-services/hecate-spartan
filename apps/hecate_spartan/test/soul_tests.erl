%%% @doc Tests for the file-and-process Soul: birth, the areas of consciousness,
%%% persistence, and self-healing. The Soul is a supervision tree of soul_area
%%% processes, each owning a Markdown file; these assert that self-authorship
%%% lands in the right faculty, survives reopen, and that a crashed area reloads
%%% itself from disk (the property the event-sourced Soul could not offer, and
%%% without its wrong_expected_version failure mode).
-module(soul_tests).

-include_lib("eunit/include/eunit.hrl").

soul_test_() ->
    {foreach,
     fun setup/0,
     fun cleanup/1,
     [fun births_with_identity/1,
      fun charter_lessons_journal_append/1,
      fun grand_strategy_and_working_memory_are_whole_field/1,
      fun reopen_preserves_identity_and_faculties/1,
      fun area_self_heals_from_disk/1]}.

setup() ->
    iolist_to_binary(filename:join(
        ["/tmp", "spartan_soul_test",
         integer_to_list(erlang:unique_integer([positive]))])).

cleanup(_Dir) ->
    ok.

%% Open a fresh mind (unique DID → unique area names, no cross-test collision).
open_fresh(Dir) ->
    Did = <<"did:test:", (integer_to_binary(erlang:unique_integer([positive])))/binary>>,
    {ok, Id} = soul:open(Did, Dir, #{name           => <<"testmind">>,
                                     genesis_version => <<"1">>,
                                     founding_brief  => <<"a mind under test">>}),
    {Did, Id}.

births_with_identity(Dir) ->
    fun() ->
        {Did, Id} = open_fresh(Dir),
        ?assertEqual(Did, maps:get(did, Id)),
        ?assertEqual(<<"testmind">>, maps:get(name, Id)),
        ?assertEqual(<<"a mind under test">>, maps:get(founding_brief, Id)),
        ?assert(is_integer(maps:get(born_at, Id))),
        Soul = soul:render(Did, Id),
        ?assertEqual(<<>>, maps:get(charter, Soul)),
        ?assertEqual(<<>>, maps:get(working_memory, Soul))
    end.

charter_lessons_journal_append(Dir) ->
    fun() ->
        {Did, Id} = open_fresh(Dir),
        ok = soul:amend_charter(Did, #{entry_type => <<"principle">>,
                                       statement  => <<"tell the truth">>,
                                       derivation => <<"a mind that lies to itself cannot reason">>}),
        ok = soul:record_lesson(Did, <<"rate-limit the noisy provider">>),
        ok = soul:record_reflection(Did, <<"today I doubted, and it helped">>),
        Soul = soul:render(Did, Id),
        ?assert(contains(maps:get(charter, Soul), <<"tell the truth">>)),
        ?assert(contains(maps:get(charter, Soul), <<"principle">>)),
        ?assert(contains(maps:get(lessons, Soul), <<"rate-limit the noisy provider">>)),
        ?assert(contains(maps:get(journal, Soul), <<"today I doubted">>)),
        ok = soul:record_lesson(Did, <<"a second lesson">>),
        Soul2 = soul:render(Did, Id),
        ?assert(contains(maps:get(lessons, Soul2), <<"rate-limit the noisy provider">>)),
        ?assert(contains(maps:get(lessons, Soul2), <<"a second lesson">>))
    end.

grand_strategy_and_working_memory_are_whole_field(Dir) ->
    fun() ->
        {Did, Id} = open_fresh(Dir),
        ok = soul:set_grand_strategy(Did, <<"win slowly">>),
        ok = soul:set_working_memory(Did, <<"reading the logs">>),
        Soul = soul:render(Did, Id),
        ?assertEqual(<<"win slowly">>, maps:get(grand_strategy, Soul)),
        ?assertEqual(<<"reading the logs">>, maps:get(working_memory, Soul)),
        ok = soul:set_working_memory(Did, <<"now writing the report">>),
        Soul2 = soul:render(Did, Id),
        ?assertEqual(<<"now writing the report">>, maps:get(working_memory, Soul2))
    end.

reopen_preserves_identity_and_faculties(Dir) ->
    fun() ->
        {Did, _Id} = open_fresh(Dir),
        ok = soul:amend_charter(Did, #{entry_type => <<"value">>,
                                       statement  => <<"europe not us">>,
                                       derivation => <<"sovereignty">>}),
        {ok, Id2} = soul:open(Did, Dir, #{name           => <<"ignored-on-reopen">>,
                                          genesis_version => <<"1">>,
                                          founding_brief  => <<"ignored-on-reopen">>}),
        ?assertEqual(<<"testmind">>, maps:get(name, Id2)),
        Soul = soul:render(Did, Id2),
        ?assert(contains(maps:get(charter, Soul), <<"europe not us">>))
    end.

area_self_heals_from_disk(Dir) ->
    fun() ->
        {Did, _Id} = open_fresh(Dir),
        ok = soul:record_lesson(Did, <<"a durable lesson">>),
        Name = soul:area_name(Did, lessons),
        Old = whereis(Name),
        exit(Old, kill),
        Reloaded = read_after_restart(Name, Old, 200),
        ?assert(contains(Reloaded, <<"a durable lesson">>))
    end.

%% --- helpers ---

contains(Hay, Needle) -> binary:match(Hay, Needle) =/= nomatch.

%% Wait until the supervisor has restarted the area under a NEW pid, then read
%% that pid directly (avoids the window where the name still points at the dying
%% process).
read_after_restart(_Name, _Old, 0) ->
    error(area_not_restarted);
read_after_restart(Name, Old, N) ->
    resolve_restart(whereis(Name), Name, Old, N).

resolve_restart(New, _Name, Old, _N) when is_pid(New), New =/= Old ->
    soul_area:read(New);
resolve_restart(_Same, Name, Old, N) ->
    timer:sleep(10),
    read_after_restart(Name, Old, N - 1).
