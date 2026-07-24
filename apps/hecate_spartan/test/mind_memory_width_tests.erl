%%% @doc DEFECT 10: a mixed-width memory store silently returns arbitrary recalls.
%%%
%%% The mind is mesh-first for embeddings and falls back to a local HTTP embedder
%%% PER CALL, so one store can legitimately hold vectors from two models of two
%%% different widths (the mesh service serves 384-dim fastembed; a local fallback
%%% model need not).
%%%
%%% `cosine/2' answers 0.0 on a width mismatch. Without a comparability filter a
%%% mismatched query therefore scores EVERY memory 0.0, and `topn/2' hands back an
%%% arbitrary K as though they were the nearest. The mind is told its most
%%% relevant memories are whichever ones sorted first, and nothing says so.
%%%
%%% This fires exactly when the fallback is doing its job, which is why it matters
%%% more than it looks.
-module(mind_memory_width_tests).

-include_lib("eunit/include/eunit.hrl").

entry(Id, Width) ->
    #{id => Id, text => Id, tokens => [Id],
      vec => lists:duplicate(Width, 0.1), links => [], evolved => false}.

%% --- the guard itself ---

same_width_is_comparable_test() ->
    Store = [entry(<<"a">>, 384), entry(<<"b">>, 384)],
    ?assertEqual(2, length(mind_memory:comparable(lists:duplicate(384, 0.2), Store))).

different_width_is_excluded_test() ->
    Store = [entry(<<"a">>, 384), entry(<<"b">>, 384)],
    ?assertEqual([], mind_memory:comparable(lists:duplicate(1024, 0.2), Store)).

%% The realistic case: the mesh embedder served most of the store, then went down
%% and a different model served the rest. Only the matching half may be compared.
mixed_width_store_keeps_only_the_matching_half_test() ->
    Store = [entry(<<"mesh1">>, 384), entry(<<"fallback1">>, 1024),
             entry(<<"mesh2">>, 384), entry(<<"fallback2">>, 1024)],
    Kept = mind_memory:comparable(lists:duplicate(384, 0.2), Store),
    ?assertEqual([<<"mesh1">>, <<"mesh2">>], [maps:get(id, E) || E <- Kept]).

%% An empty comparable set is the signal that makes `semantic/5' degrade to
%% lexical, which is a real answer, rather than to cosine-zero, which is not.
no_comparable_vectors_yields_empty_test() ->
    ?assertEqual([], mind_memory:comparable([0.1, 0.2], [entry(<<"a">>, 384)])).

empty_store_is_empty_test() ->
    ?assertEqual([], mind_memory:comparable(lists:duplicate(384, 0.2), [])).
