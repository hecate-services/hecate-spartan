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

%% colibrì is a first-class provider: OpenAI shape, endpoint from the env, and
%% keyless (the local serve ignores the bearer) so it never needs a credential.
colibri_is_env_driven_and_openai_test() ->
    with_env("COLIBRI_URL", "http://colibri.lab:8000/v1/chat/completions", fun() ->
        with_env("COLIBRI_MODEL", "glm-5.2", fun() ->
            Cfg = spartan_mind_llm:provider_config("colibri"),
            ?assertEqual(openai, maps:get(fmt, Cfg)),
            ?assertEqual(true, maps:get(keyless, Cfg)),
            ?assertEqual("http://colibri.lab:8000/v1/chat/completions", maps:get(url, Cfg)),
            ?assertEqual(<<"glm-5.2">>, maps:get(model, Cfg))
        end)
    end).

colibri_url_defaults_to_local_serve_test() ->
    with_unset("COLIBRI_URL", fun() ->
        ?assertEqual("http://127.0.0.1:8000/v1/chat/completions",
                     maps:get(url, spartan_mind_llm:provider_config("colibri")))
    end).

colibri_rides_the_carousel_test() ->
    with_env("HECATE_MIND_PROVIDERS", "colibri,melious", fun() ->
        ?assertEqual(<<"colibri,melious">>, spartan_mind_llm:provider_labels())
    end).

%% The melious model is env-driven so a reasoning model can be swapped for a
%% cheaper instruct one without a rebuild.
melious_model_env_overrides_test() ->
    with_env("MELIOUS_MODEL", "some-instruct-model", fun() ->
        ?assertEqual(<<"some-instruct-model">>,
                     maps:get(model, spartan_mind_llm:provider_config("melious")))
    end).

melious_model_defaults_when_unset_test() ->
    with_unset("MELIOUS_MODEL", fun() ->
        ?assertEqual(<<"qwen3.5-9b">>,
                     maps:get(model, spartan_mind_llm:provider_config("melious")))
    end).

%% nvidia and deepseek follow the exact same shape as every other OpenAI-fmt
%% provider (env-driven model, own keyenv) — covered together since neither
%% needs anything special (no keyless flag, no per-provider timeout).

nvidia_is_openai_and_env_driven_test() ->
    Cfg = spartan_mind_llm:provider_config("nvidia"),
    ?assertEqual(openai, maps:get(fmt, Cfg)),
    ?assertEqual("NVIDIA_API_KEYS", maps:get(keyenv, Cfg)),
    ?assertEqual("https://integrate.api.nvidia.com/v1/chat/completions", maps:get(url, Cfg)).

nvidia_model_env_overrides_test() ->
    with_env("NVIDIA_MODEL", "some/other-model", fun() ->
        ?assertEqual(<<"some/other-model">>,
                     maps:get(model, spartan_mind_llm:provider_config("nvidia")))
    end).

nvidia_model_defaults_when_unset_test() ->
    with_unset("NVIDIA_MODEL", fun() ->
        ?assertEqual(<<"meta/llama-3.3-70b-instruct">>,
                     maps:get(model, spartan_mind_llm:provider_config("nvidia")))
    end).

deepseek_is_openai_and_env_driven_test() ->
    Cfg = spartan_mind_llm:provider_config("deepseek"),
    ?assertEqual(openai, maps:get(fmt, Cfg)),
    ?assertEqual("DEEPSEEK_API_KEYS", maps:get(keyenv, Cfg)),
    ?assertEqual("https://api.deepseek.com/v1/chat/completions", maps:get(url, Cfg)).

deepseek_model_defaults_when_unset_test() ->
    with_unset("DEEPSEEK_MODEL", fun() ->
        ?assertEqual(<<"deepseek-chat">>,
                     maps:get(model, spartan_mind_llm:provider_config("deepseek")))
    end).

nvidia_and_deepseek_ride_the_carousel_test() ->
    with_env("HECATE_MIND_PROVIDERS", "nvidia,deepseek,melious", fun() ->
        ?assertEqual(<<"nvidia,deepseek,melious">>, spartan_mind_llm:provider_labels())
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
