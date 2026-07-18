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
    %% Exercise the lexical fallback path: disable the embedder so there is no
    %% mesh call and no network, and recall degrades to deterministic word
    %% overlap (the mechanics under test here; semantic quality is the real
    %% embedder's concern, validated separately).
    {setup,
     fun() -> application:set_env(hecate_spartan, embed_enabled, false) end,
     fun(_) -> application:unset_env(hecate_spartan, embed_enabled) end,
     [
      fun stores_and_grows/0,
      fun recall_returns_stored_texts/0,
      fun recall_is_capped_and_deterministic/0,
      fun recall_on_empty_is_safe/0,
      fun bad_input_never_crashes/0,
      fun persists_across_reopen/0,
      fun ephemeral_open_saves_nothing/0
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

%% Durability: seed, save, re-open a FRESH handle from the same dir — the store
%% loads whole from disk (no re-embed), size and recall survive the restart.
persists_across_reopen() ->
    Dir = tmp_dir(),
    Did = <<"did:test:persist">>,
    {ok, M0} = mind_memory:open(Did, Dir),
    M1 = mind_memory:seed(M0, ?CORPUS),
    ok = mind_memory:save(M1),
    {ok, M2} = mind_memory:open(Did, Dir),
    ?assertEqual(length(?CORPUS), mind_memory:size(M2)),
    ?assert(mind_memory:recall(M2, <<"rotate the leaked credential immediately">>, 2) =/= []).

%% An ephemeral store (open/1, no data dir) persists nothing and never crashes.
ephemeral_open_saves_nothing() ->
    {ok, M0} = mind_memory:open(<<"did:test:ephemeral">>),
    M1 = mind_memory:remember(M0, <<"a fleeting thought">>),
    ?assertEqual(ok, mind_memory:save(M1)).

tmp_dir() ->
    Rand = integer_to_binary(erlang:unique_integer([positive])),
    Dir = filename:join(["/tmp", <<"mind_memory_test_", Rand/binary>>]),
    iolist_to_binary(Dir).

%% --- A-Mem evolution (LLM-driven agentic linking) ---
%% evolve/2 uses only cosine (pure) + the caller's ReasonFun, no embedder, so
%% these build a mem() with hand-set vectors and a stub ReasonFun directly.

evolve_test_() ->
    [
     fun evolve_links_via_llm_choice/0,
     fun evolve_none_reply_links_nothing/0,
     fun evolve_backend_down_leaves_unevolved/0,
     fun evolve_marks_no_candidates/0,
     fun evolve_empty_is_safe/0
    ].

%% a≈b (cosine ~0.99), c orthogonal (below the candidate floor). Lowest id "a" is
%% evolved first; only b is a candidate; the stub links it; b gains a back-link.
evolve_links_via_llm_choice() ->
    Mem1 = mind_memory:evolve(mem3(), fun(_Msgs) -> {ok, <<"1">>} end),
    A = entry(<<"a">>, Mem1),
    B = entry(<<"b">>, Mem1),
    ?assertEqual(true, maps:get(evolved, A)),
    ?assertEqual([<<"b">>], maps:get(links, A)),
    ?assert(lists:member(<<"a">>, maps:get(links, B))).

evolve_none_reply_links_nothing() ->
    Mem1 = mind_memory:evolve(mem3(), fun(_Msgs) -> {ok, <<"NONE">>} end),
    A = entry(<<"a">>, Mem1),
    ?assertEqual(true, maps:get(evolved, A)),
    ?assertEqual([], maps:get(links, A)).

%% Backend down: the memory stays unevolved (retried next cadence), links intact.
evolve_backend_down_leaves_unevolved() ->
    Mem1 = mind_memory:evolve(mem3(), fun(_Msgs) -> error end),
    A = entry(<<"a">>, Mem1),
    ?assertEqual(false, maps:get(evolved, A)),
    ?assertEqual([], maps:get(links, A)).

%% A lone vectored memory has no candidates: marked evolved so it is not
%% reconsidered every cadence forever.
evolve_marks_no_candidates() ->
    Solo = #{did => <<"did:test:solo">>, dir => undefined,
             entries => #{<<"a">> => ventry(<<"a">>, <<"x">>, [1.0, 0.0])}},
    Mem1 = mind_memory:evolve(Solo, fun(_Msgs) -> {ok, <<"1">>} end),
    ?assertEqual(true, maps:get(evolved, entry(<<"a">>, Mem1))).

evolve_empty_is_safe() ->
    {ok, M0} = mind_memory:open(<<"did:test:evolve-empty">>),
    ?assertEqual(M0, mind_memory:evolve(M0, fun(_Msgs) -> {ok, <<"1">>} end)).

mem3() ->
    #{did => <<"did:test:evolve">>, dir => undefined,
      entries => #{<<"a">> => ventry(<<"a">>, <<"alpha">>, [1.0, 0.0]),
                   <<"b">> => ventry(<<"b">>, <<"beta">>,  [0.9, 0.1]),
                   <<"c">> => ventry(<<"c">>, <<"gamma">>, [0.0, 1.0])}}.

ventry(Id, Text, Vec) ->
    #{id => Id, text => Text, tokens => [], vec => Vec, links => [], evolved => false}.

entry(Id, #{entries := Es}) -> maps:get(Id, Es).
