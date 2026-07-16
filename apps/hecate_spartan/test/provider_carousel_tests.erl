%%% @doc Tests for the provider pool a mind carousels across. The schedule
%%% building and HTTP live off-box; here we cover how the pool is read from the
%%% environment and rendered for the HUD, which is the part config gets wrong.
-module(provider_carousel_tests).

-include_lib("eunit/include/eunit.hrl").

providers_env_wins_test() ->
    with_env("HECATE_MIND_PROVIDERS", "mistral,cerebras,gemini", fun() ->
        ?assertEqual(<<"mistral,cerebras,gemini">>, spartan_mind_llm:provider_labels())
    end).

providers_env_trims_and_drops_blanks_test() ->
    with_env("HECATE_MIND_PROVIDERS", " melious , , groq ", fun() ->
        ?assertEqual(<<"melious,groq">>, spartan_mind_llm:provider_labels())
    end).

single_backend_is_a_pool_of_one_test() ->
    with_unset("HECATE_MIND_PROVIDERS", fun() ->
        with_env("HECATE_MIND_BACKEND", "cerebras", fun() ->
            ?assertEqual(<<"cerebras">>, spartan_mind_llm:provider_labels())
        end)
    end).

defaults_to_melious_test() ->
    with_unset("HECATE_MIND_PROVIDERS", fun() ->
        with_unset("HECATE_MIND_BACKEND", fun() ->
            ?assertEqual(<<"melious">>, spartan_mind_llm:provider_labels())
        end)
    end).

%% --- env fixtures (restore whatever was there) ---

with_env(Var, Value, Fun) ->
    Prev = os:getenv(Var),
    os:putenv(Var, Value),
    try Fun() after restore(Var, Prev) end.

with_unset(Var, Fun) ->
    Prev = os:getenv(Var),
    os:unsetenv(Var),
    try Fun() after restore(Var, Prev) end.

restore(Var, false) -> os:unsetenv(Var);
restore(Var, Value) -> os:putenv(Var, Value).
