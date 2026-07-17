%%% @doc Tests for the mind's embed transport selector. The mesh path needs a
%%% live realm so it can't be unit-tested; here we cover mode selection, the http
%%% path (against the stub embedder), and that mesh mode degrades to {error, _}
%%% rather than crashing when no mesh is up.
-module(spartan_embed_tests).

-include_lib("eunit/include/eunit.hrl").

embed_test_() ->
    {setup,
     fun() -> {ok, _} = application:ensure_all_started(hecate_embed), ok end,
     fun(_) -> os:unsetenv("HECATE_EMBED_MODE") end,
     [
      fun http_mode_returns_a_vector/0,
      fun mesh_mode_degrades_without_mesh/0,
      fun mesh_result_parsing/0,
      fun bad_input_guarded/0
     ]}.

http_mode_returns_a_vector() ->
    with_mode("http", fun() ->
        {ok, V} = spartan_embed:passage(<<"block the attacker">>),
        ?assert(is_list(V)),
        ?assert(length(V) > 0),
        {ok, Q} = spartan_embed:query(<<"block the attacker">>),
        ?assert(is_list(Q))
    end).

mesh_mode_degrades_without_mesh() ->
    with_mode("mesh", fun() ->
        %% No macula client / realm in the test VM: must return an error, not
        %% crash, so a mind just recalls nothing that turn.
        ?assertMatch({error, _}, spartan_embed:query(<<"anything">>)),
        ?assertMatch({error, _}, spartan_embed:passage(<<"anything">>))
    end).

mesh_result_parsing() ->
    %% The seam that silently breaks if the embedder's reply shape or CBOR key
    %% encoding changes. A macula:call yields {ok, #{vector => [...]}} with the
    %% key as an atom or a binary depending on the CBOR round-trip; both must
    %% parse. Anything else degrades to {error, _} so a mind recalls nothing.
    ?assertEqual({ok, [1.0, 2.0]},
                 spartan_embed:interpret({ok, #{vector => [1.0, 2.0]}})),
    ?assertEqual({ok, [3.0]},
                 spartan_embed:interpret({ok, #{<<"vector">> => [3.0]}})),
    ?assertMatch({error, _}, spartan_embed:interpret({ok, #{}})),
    ?assertMatch({error, _}, spartan_embed:interpret({ok, #{vector => not_a_list}})),
    ?assertMatch({error, _}, spartan_embed:interpret({ok, <<"not a map">>})),
    ?assertMatch({error, _}, spartan_embed:interpret({error, timeout})),
    ?assertMatch({error, _}, spartan_embed:interpret({'EXIT', boom})).

bad_input_guarded() ->
    %% Non-binary input has no clause; the guard means it fails fast rather than
    %% embedding garbage. mind_memory only ever passes binaries.
    ?assertError(function_clause, spartan_embed:query(not_a_binary)).

with_mode(Mode, Fun) ->
    Prev = os:getenv("HECATE_EMBED_MODE"),
    os:putenv("HECATE_EMBED_MODE", Mode),
    try Fun() after restore(Prev) end.

restore(false) -> os:unsetenv("HECATE_EMBED_MODE");
restore(Value) -> os:putenv("HECATE_EMBED_MODE", Value).
