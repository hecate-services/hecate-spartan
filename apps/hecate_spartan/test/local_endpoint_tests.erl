%%% @doc The `local' provider: M1's pinned measurement endpoint.
%%%
%%% Insight 014 needs an endpoint that is the OPPOSITE of the production carousel:
%%% one model, one version, no rotation, and no rate limit, so a retry loop cannot
%%% pollute the cost ledger and a wall-clock figure means something because the
%%% machine is fixed.
-module(local_endpoint_tests).

-include_lib("eunit/include/eunit.hrl").

cfg() -> spartan_mind_llm:provider_config("local").

with_env(Vars, Fun) ->
    Old = [{K, os:getenv(K)} || {K, _} <- Vars],
    [os:putenv(K, V) || {K, V} <- Vars],
    try Fun() after [restore(K, V) || {K, V} <- Old] end.

restore(K, false) -> os:unsetenv(K);
restore(K, V)     -> os:putenv(K, V).

resolves_test() ->
    ?assertMatch(#{fmt := openai, label := "local"}, cfg()).

%% A local serve ignores the bearer, so the carousel must not drop it as
%% unconfigured for want of a key.
is_keyless_test() ->
    ?assertMatch(#{keyless := true}, cfg()).

%% THE load-bearing detail. `colibri' caps max_tokens at 160, which would truncate
%% M1's JSON extraction into parse failures the referee counts as arm noise. The
%% measurement endpoint deliberately declares NO cap, so the caller's own applies.
declares_no_max_tokens_test() ->
    ?assertNot(maps:is_key(max_tokens, cfg())).

%% CPU inference is slow; a short fast-provider timeout would abort real answers.
has_patient_timeout_test() ->
    ?assert(maps:get(timeout, cfg()) >= 120000).

%% The default names an explicit version, never a moving `latest' tag: a pin that
%% drifts is not a pin.
default_model_is_version_pinned_test() ->
    with_env([{"HECATE_LOCAL_MODEL", ""}], fun() ->
        Model = maps:get(model, cfg()),
        ?assertNotEqual(nomatch, binary:match(Model, <<":">>)),
        ?assertEqual(nomatch, binary:match(Model, <<"latest">>))
    end).

endpoint_is_env_driven_test() ->
    with_env([{"HECATE_LOCAL_URL", "http://msi00.lab:11434/v1/chat/completions"},
              {"HECATE_LOCAL_MODEL", "pinned-model:v1"}], fun() ->
        ?assertMatch(#{url := "http://msi00.lab:11434/v1/chat/completions",
                       model := <<"pinned-model:v1">>}, cfg())
    end).
