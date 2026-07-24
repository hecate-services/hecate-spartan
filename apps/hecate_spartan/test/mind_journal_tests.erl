%%% @doc Tests for the mind's append-only journal, and for the two properties it
%%% exists to give the Soul: a recoverable history of self-authorship acts, and a
%%% hand-editable document that nothing ever regenerates.
-module(mind_journal_tests).

-include_lib("eunit/include/eunit.hrl").

journal_test_() ->
    {foreach,
     fun setup/0,
     fun cleanup/1,
     [fun appends_are_readable_in_order/1,
      fun kinds_filter/1,
      fun texts_extracts_payload_text/1,
      fun a_torn_tail_does_not_lose_earlier_records/1,
      fun no_journal_degrades_rather_than_crashes/1,
      fun soul_keeps_a_prior_version/1,
      fun a_hand_edit_survives/1]}.

setup() ->
    Dir = iolist_to_binary(filename:join(
        ["/tmp", "spartan_journal_test",
         integer_to_list(erlang:unique_integer([positive]))])),
    _ = os:cmd("rm -rf " ++ binary_to_list(Dir)),
    Dir.

cleanup(Dir) ->
    _ = os:cmd("rm -rf " ++ binary_to_list(Dir)),
    ok.

did() ->
    <<"did:test:", (integer_to_binary(erlang:unique_integer([positive])))/binary>>.

fresh(Dir) ->
    Did = did(),
    ok = mind_journal:open(Did, Dir),
    Did.

%% --- the log itself ---

appends_are_readable_in_order(Dir) ->
    fun() ->
        Did = fresh(Dir),
        ok = mind_journal:append(Did, experience_observed_v1, #{text => <<"first">>}),
        ok = mind_journal:append(Did, experience_observed_v1, #{text => <<"second">>}),
        ok = mind_journal:append(Did, gist_formed_v1, #{tier => cmo, text => <<"a gist">>}),
        Records = mind_journal:records(Did),
        ?assertEqual(3, length(Records)),
        ?assertEqual([experience_observed_v1, experience_observed_v1, gist_formed_v1],
                     [maps:get(kind, R) || R <- Records]),
        ?assertEqual(<<"first">>, maps:get(text, maps:get(payload, hd(Records))))
    end.

kinds_filter(Dir) ->
    fun() ->
        Did = fresh(Dir),
        ok = mind_journal:append(Did, experience_observed_v1, #{text => <<"lived">>}),
        ok = mind_journal:append(Did, stimulus_declined_v1, #{reason => busy}),
        ?assertEqual(1, length(mind_journal:records(Did, [stimulus_declined_v1]))),
        ?assertEqual(2, length(mind_journal:records(Did, [experience_observed_v1,
                                                          stimulus_declined_v1])))
    end.

%% A record with no text (a decline carries only a reason) must not surface as an
%% empty string in the recovered history.
texts_extracts_payload_text(Dir) ->
    fun() ->
        Did = fresh(Dir),
        ok = mind_journal:append(Did, experience_observed_v1, #{text => <<"a">>}),
        ok = mind_journal:append(Did, stimulus_declined_v1, #{reason => cooldown}),
        ok = mind_journal:append(Did, experience_observed_v1, #{text => <<"b">>}),
        ?assertEqual([<<"a">>, <<"b">>],
                     mind_journal:texts(Did, [experience_observed_v1, stimulus_declined_v1]))
    end.

%% A crash mid-append leaves a short final frame. Everything before it is intact,
%% and the partial record simply never happened.
a_torn_tail_does_not_lose_earlier_records(Dir) ->
    fun() ->
        Did = fresh(Dir),
        [ok = mind_journal:append(Did, experience_observed_v1,
                                  #{text => <<"kept ", (integer_to_binary(I))/binary>>})
         || I <- lists:seq(1, 5)],
        Path = mind_journal:path(Dir, Did),
        {ok, Bin} = file:read_file(Path),
        %% lop off the last 7 bytes: the final frame is now short
        ok = file:write_file(Path, binary:part(Bin, 0, byte_size(Bin) - 7)),
        Records = mind_journal:from_disk(Path),
        ?assertEqual(4, length(Records)),
        ?assertEqual(<<"kept 1">>, maps:get(text, maps:get(payload, hd(Records))))
    end.

%% A throwaway mind (or a unit test) runs without a journal. Callers degrade.
no_journal_degrades_rather_than_crashes(_Dir) ->
    fun() ->
        Did = did(),
        ?assertEqual({error, no_journal},
                     mind_journal:append(Did, experience_observed_v1, #{text => <<"x">>})),
        ?assertEqual([], mind_journal:records(Did))
    end.

%% --- defect 7: the Soul gains a history without losing its document ---

soul_keeps_a_prior_version(Dir) ->
    fun() ->
        Did = did(),
        {ok, _} = soul:open(Did, Dir, birth()),
        ok = soul:set_grand_strategy(Did, <<"win slowly, by being useful">>),
        ok = soul:set_grand_strategy(Did, <<"">>),
        %% the document is authoritative, and it has indeed been emptied
        ?assertEqual(<<>>, soul:read_area(Did, grand_strategy)),
        %% but the act that wrote the earlier text is recoverable, by a HUMAN
        ?assert(lists:member(<<"win slowly, by being useful">>,
                             soul:prior(Did, grand_strategy)))
    end.

%% The document is never regenerated from the journal, so an edit made outside the
%% mind survives. This is the property that forbids a drift detector: a hand-edit
%% and a crash-window gap are indistinguishable, so nothing may reconcile them.
a_hand_edit_survives(Dir) ->
    fun() ->
        Did = did(),
        {ok, _} = soul:open(Did, Dir, birth()),
        ok = soul:set_grand_strategy(Did, <<"authored by the mind">>),
        Path = filename:join(soul:dir(Dir, Did), <<"GrandStrategy.md">>),
        ok = file:write_file(Path, <<"edited by a human">>),
        %% Restart just this area, so it reloads from disk. The journal still
        %% holds "authored by the mind"; nothing applies it over the document.
        Name = soul:area_name(Did, grand_strategy),
        Old = whereis(Name),
        exit(Old, kill),
        ok = wait_until(fun() -> is_pid(whereis(Name)) andalso whereis(Name) =/= Old end, 200),
        ?assertEqual(<<"edited by a human">>, soul:read_area(Did, grand_strategy)),
        ?assert(lists:member(<<"authored by the mind">>, soul:prior(Did, grand_strategy)))
    end.

wait_until(_Pred, 0) -> timeout;
wait_until(Pred, N)  -> resolve(Pred(), Pred, N).

resolve(true, _Pred, _N) -> ok;
resolve(false, Pred, N)  -> timer:sleep(10), wait_until(Pred, N - 1).

birth() ->
    #{name => <<"tester">>, genesis_version => <<"test">>,
      founding_brief => <<"a mind for testing">>}.
