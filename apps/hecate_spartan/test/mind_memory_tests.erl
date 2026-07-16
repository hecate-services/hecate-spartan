%%% @doc Tests for a mind's long-term memory PLUMBING: open, store, recall,
%%% seed, and graceful degradation. Run against the deterministic stub embedder
%%% (no ONNX, no download), so these assert mechanics, not semantic quality —
%%% the semantic behaviour of the real fastembed backend is validated separately
%%% (cos(related) > cos(unrelated)). Here we prove the wiring: memories land in
%%% the index, recall returns stored texts, capped at K, and never crashes.
-module(mind_memory_tests).

-include_lib("eunit/include/eunit.hrl").

-define(CORPUS, [<<"block the attacker IP range at the perimeter">>,
                 <<"rotate the leaked credential immediately">>,
                 <<"audit the ansible service accounts">>,
                 <<"the cat slept in the afternoon sun">>]).

memory_test_() ->
    {setup,
     fun() ->
         {ok, _} = application:ensure_all_started(hecate_embed),
         {ok, _} = application:ensure_all_started(hecate_vector),
         ok
     end,
     fun(_) -> ok end,
     [
      fun stores_and_grows/0,
      fun recall_returns_stored_texts/0,
      fun recall_is_capped_and_deterministic/0,
      fun recall_on_empty_is_safe/0,
      fun bad_input_never_crashes/0
     ]}.

stores_and_grows() ->
    {ok, M0} = mind_memory:open(<<"did:test:grow">>),
    ?assertEqual(0, mind_memory:size(M0)),
    M1 = mind_memory:remember(M0, <<"a memory">>),
    ?assertEqual(1, mind_memory:size(M1)),
    M2 = mind_memory:seed(M1, ?CORPUS),
    ?assertEqual(1 + length(?CORPUS), mind_memory:size(M2)).

recall_returns_stored_texts() ->
    {ok, M0} = mind_memory:open(<<"did:test:recall">>),
    M1 = mind_memory:seed(M0, ?CORPUS),
    Hits = mind_memory:recall(M1, <<"block the attacker IP range at the perimeter">>, 3),
    ?assert(Hits =/= []),
    ?assert(lists:all(fun(H) -> lists:member(H, ?CORPUS) end, Hits)).

recall_is_capped_and_deterministic() ->
    {ok, M0} = mind_memory:open(<<"did:test:cap">>),
    M1 = mind_memory:seed(M0, ?CORPUS),
    Hits = mind_memory:recall(M1, <<"rotate the leaked credential immediately">>, 2),
    ?assert(length(Hits) =< 2),
    ?assertEqual(Hits, mind_memory:recall(M1, <<"rotate the leaked credential immediately">>, 2)).

recall_on_empty_is_safe() ->
    {ok, M0} = mind_memory:open(<<"did:test:empty">>),
    ?assertEqual([], mind_memory:recall(M0, <<"anything">>, 5)).

bad_input_never_crashes() ->
    {ok, M0} = mind_memory:open(<<"did:test:bad">>),
    ?assertEqual(M0, mind_memory:remember(M0, <<>>)),
    ?assertEqual([], mind_memory:recall(M0, <<>>, 3)).
