%%% @doc The mind's token clock rides on provider usage parsing.
%%%
%%% `self_alerts' counts down against TOKENS THOUGHT, not seconds. The clock is
%%% advanced by whatever `spartan_mind_llm' reports for a turn, so a provider that
%%% omits the summed total used to yield 0 and silently freeze every reminder a
%%% mind had scheduled for itself. Falling back to prompt+completion keeps the
%%% clock moving.
-module(mind_usage_tests).

-include_lib("eunit/include/eunit.hrl").

openai(Usage) -> spartan_mind_llm:openai_tokens(#{<<"usage">> => Usage}).
gemini(Usage) -> spartan_mind_llm:gemini_tokens(#{<<"usageMetadata">> => Usage}).

%% --- OpenAI-compatible shape ---

openai_total_test() ->
    ?assertEqual(1500, openai(#{<<"total_tokens">> => 1500})).

openai_falls_back_to_parts_test() ->
    ?assertEqual(1000, openai(#{<<"prompt_tokens">> => 900, <<"completion_tokens">> => 100})).

openai_total_wins_over_parts_test() ->
    ?assertEqual(1500, openai(#{<<"prompt_tokens">> => 900, <<"completion_tokens">> => 100,
                                <<"total_tokens">> => 1500})).

openai_absent_usage_is_zero_test() ->
    ?assertEqual(0, spartan_mind_llm:openai_tokens(#{})).

%% A partial usage object cannot be summed and must not crash the turn.
openai_partial_parts_is_zero_test() ->
    ?assertEqual(0, openai(#{<<"prompt_tokens">> => 900})).

%% --- Gemini generateContent shape ---

gemini_total_test() ->
    ?assertEqual(2048, gemini(#{<<"totalTokenCount">> => 2048})).

gemini_falls_back_to_parts_test() ->
    ?assertEqual(700, gemini(#{<<"promptTokenCount">> => 640, <<"candidatesTokenCount">> => 60})).

gemini_absent_usage_is_zero_test() ->
    ?assertEqual(0, spartan_mind_llm:gemini_tokens(#{})).
