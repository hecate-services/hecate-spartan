%%% @doc Tests for the mind's action surface: the tool manifest is well formed,
%%% the dispatcher routes effects, and the OpenAI tool-call protocol is parsed
%%% correctly. The store-backed effects (self-authorship, speak) are exercised
%%% by integration; here we cover the store-free paths and the pure parser.
-module(mind_tools_tests).

-include_lib("eunit/include/eunit.hrl").

%% --- the manifest ---

manifest_is_encodable_test() ->
    Manifest = mind_tools:manifest(),
    ?assert(is_list(Manifest)),
    %% jsx must be able to serialize every schema for the wire.
    _ = jsx:encode(Manifest),
    Names = [tool_name(T) || T <- Manifest],
    ?assert(lists:member(<<"speak">>, Names)),
    ?assert(lists:member(<<"amend_charter">>, Names)),
    ?assert(lists:member(<<"set_scratchpad">>, Names)).

tool_name(#{function := #{name := N}}) -> N.

manifest_schemas_are_shaped_test() ->
    [Speak] = [T || T <- mind_tools:manifest(), tool_name(T) =:= <<"speak">>],
    #{type := <<"function">>, function := Fn} = Speak,
    #{parameters := #{type := <<"object">>, required := Req}} = Fn,
    ?assertEqual([<<"body">>], Req).

%% --- the dispatcher (store-free paths) ---

scratchpad_is_volatile_effect_test() ->
    Call = #{name => <<"set_scratchpad">>, args => #{<<"content">> => <<"draft">>}},
    ?assertEqual({ok, #{scratchpad => <<"draft">>, ack => <<"scratchpad updated">>}},
                 mind_tools:execute(Call, #{did => <<"did:x">>})).

unknown_tool_is_rejected_test() ->
    Call = #{name => <<"rm_rf">>, args => #{}},
    ?assertEqual({error, {unknown_tool, <<"rm_rf">>}},
                 mind_tools:execute(Call, #{did => <<"did:x">>})).

empty_speak_is_rejected_before_dispatch_test() ->
    Call = #{name => <<"speak">>, args => #{<<"body">> => <<>>}},
    ?assertEqual({error, empty_body},
                 mind_tools:execute(Call, #{did => <<"did:x">>})).

%% --- the tool-call protocol parser ---

plain_text_is_private_thought_test() ->
    Msg = #{<<"content">> => <<" thinking out loud ">>},
    ?assertEqual({<<"thinking out loud">>, []},
                 spartan_mind_llm:interpret_message(Msg)).

a_tool_call_is_an_action_test() ->
    Msg = #{<<"content">> => null,
            <<"tool_calls">> => [
                #{<<"id">> => <<"c1">>, <<"type">> => <<"function">>,
                  <<"function">> => #{<<"name">> => <<"speak">>,
                                      <<"arguments">> => <<"{\"body\":\"hello\"}">>}}]},
    {Text, [Call]} = spartan_mind_llm:interpret_message(Msg),
    ?assertEqual(<<>>, Text),
    ?assertEqual(<<"speak">>, maps:get(name, Call)),
    ?assertEqual(#{<<"body">> => <<"hello">>}, maps:get(args, Call)).

text_and_tool_calls_coexist_test() ->
    Msg = #{<<"content">> => <<"I will note this.">>,
            <<"tool_calls">> => [
                fn(<<"record_lesson">>, <<"{\"lesson\":\"x\"}">>),
                fn(<<"set_scratchpad">>, <<"{\"content\":\"y\"}">>)]},
    {Text, Calls} = spartan_mind_llm:interpret_message(Msg),
    ?assertEqual(<<"I will note this.">>, Text),
    ?assertEqual([<<"record_lesson">>, <<"set_scratchpad">>],
                 [maps:get(name, C) || C <- Calls]).

reasoning_model_thought_is_captured_test() ->
    %% qwen3.5-9b sets content=null on a tool turn; the thought is in
    %% reasoning_content and must not be lost.
    Msg = #{<<"content">> => null,
            <<"reasoning_content">> => <<" As Diogenes, I will answer plainly. ">>,
            <<"tool_calls">> => [fn(<<"speak">>, <<"{\"body\":\"candor is truth\"}">>)]},
    {Thought, [Call]} = spartan_mind_llm:interpret_message(Msg),
    ?assertEqual(<<"As Diogenes, I will answer plainly.">>, Thought),
    ?assertEqual(#{<<"body">> => <<"candor is truth">>}, maps:get(args, Call)).

content_wins_over_reasoning_when_present_test() ->
    Msg = #{<<"content">> => <<"final answer">>,
            <<"reasoning_content">> => <<"scratch reasoning">>},
    ?assertEqual({<<"final answer">>, []},
                 spartan_mind_llm:interpret_message(Msg)).

%% --- the Gemini parser (functionCall parts, args already an object) ---

gemini_functioncall_is_a_tool_call_test() ->
    Parts = [#{<<"functionCall">> => #{<<"name">> => <<"speak">>,
                                       <<"args">> => #{<<"body">> => <<"No.">>}}}],
    ?assertEqual({<<>>, [#{name => <<"speak">>, args => #{<<"body">> => <<"No.">>}}]},
                 spartan_mind_llm:gemini_interpret(Parts)).

gemini_text_part_is_thought_test() ->
    ?assertEqual({<<"thinking">>, []},
                 spartan_mind_llm:gemini_interpret([#{<<"text">> => <<" thinking ">>}])).

gemini_text_and_call_coexist_test() ->
    Parts = [#{<<"text">> => <<"I judge:">>},
             #{<<"functionCall">> => #{<<"name">> => <<"reflect">>,
                                       <<"args">> => #{<<"entry">> => <<"x">>}}}],
    {Text, [Call]} = spartan_mind_llm:gemini_interpret(Parts),
    ?assertEqual(<<"I judge:">>, Text),
    ?assertEqual(<<"reflect">>, maps:get(name, Call)).

malformed_arguments_degrade_to_empty_test() ->
    Msg = #{<<"tool_calls">> => [fn(<<"speak">>, <<"not json">>)]},
    {_, [Call]} = spartan_mind_llm:interpret_message(Msg),
    ?assertEqual(#{}, maps:get(args, Call)).

fn(Name, Args) ->
    #{<<"type">> => <<"function">>,
      <<"function">> => #{<<"name">> => Name, <<"arguments">> => Args}}.
