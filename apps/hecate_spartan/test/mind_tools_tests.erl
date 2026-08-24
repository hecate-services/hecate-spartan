%%% @doc Tests for the mind's action surface: the tool manifest is well formed,
%%% the dispatcher routes effects, and the OpenAI tool-call protocol is parsed
%%% correctly. The store-backed effects (self-authorship, speak) are exercised
%%% by integration; here we cover the store-free paths and the pure parser.
%%%
%%% The manifest itself is Did-aware now (mind_tools:manifest/1: a capability
%%% only appears once granted), which needs a live Soul the same way
%%% mind_tunables_tests.erl and soul_tests.erl do — hence the one fixture
%%% below, mirroring their setup/cleanup.
-module(mind_tools_tests).

-include_lib("eunit/include/eunit.hrl").

%% --- the manifest ---

manifest_test_() ->
    {foreach, fun setup/0, fun cleanup/1,
     [fun manifest_is_encodable/1,
      fun manifest_schemas_are_shaped/1,
      fun ungranted_capability_tools_are_absent/1,
      fun granted_capability_tool_appears_next_manifest/1,
      fun execute_refuses_an_ungranted_capability_even_if_called/1,
      fun reach_web_refuses_private_and_loopback_hosts/1,
      fun reach_web_refuses_a_non_http_scheme/1]}.

setup() ->
    Dir = iolist_to_binary(filename:join(
        ["/tmp", "spartan_mind_tools_test",
         integer_to_list(erlang:unique_integer([positive]))])),
    _ = os:cmd("rm -rf " ++ binary_to_list(Dir)),
    Dir.

cleanup(Dir) ->
    _ = os:cmd("rm -rf " ++ binary_to_list(Dir)),
    ok.

open_fresh(Dir) ->
    Did = <<"did:test:", (integer_to_binary(erlang:unique_integer([positive])))/binary>>,
    {ok, _Id} = soul:open(Did, Dir, #{name           => <<"testmind">>,
                                      genesis_version => <<"1">>,
                                      founding_brief  => <<"a mind under test">>}),
    Did.

manifest_is_encodable(Dir) ->
    fun() ->
        Did = open_fresh(Dir),
        Manifest = mind_tools:manifest(Did),
        ?assert(is_list(Manifest)),
        %% jsx must be able to serialize every schema for the wire.
        _ = jsx:encode(Manifest),
        Names = [tool_name(T) || T <- Manifest],
        ?assert(lists:member(<<"speak">>, Names)),
        ?assert(lists:member(<<"amend_charter">>, Names)),
        ?assert(lists:member(<<"set_scratchpad">>, Names)),
        ?assert(lists:member(<<"convene_committee">>, Names)),
        ?assert(lists:member(<<"evolve_self">>, Names)),
        ?assert(lists:member(<<"retune_self">>, Names)),
        ?assert(lists:member(<<"grant_capability">>, Names))
    end.

manifest_schemas_are_shaped(Dir) ->
    fun() ->
        Did = open_fresh(Dir),
        [Speak] = [T || T <- mind_tools:manifest(Did), tool_name(T) =:= <<"speak">>],
        #{type := <<"function">>, function := Fn} = Speak,
        #{parameters := #{type := <<"object">>, required := Req}} = Fn,
        ?assertEqual([<<"body">>], Req)
    end.

ungranted_capability_tools_are_absent(Dir) ->
    fun() ->
        Did = open_fresh(Dir),
        Names = [tool_name(T) || T <- mind_tools:manifest(Did)],
        ?assertNot(lists:member(<<"rag_search">>, Names)),
        ?assertNot(lists:member(<<"rag_contribute">>, Names)),
        ?assertNot(lists:member(<<"reach_web">>, Names))
    end.

%% Reproduces exactly the "not wired" failure this session set out to avoid:
%% a grant that changes the Soul's Capabilities.md but never reaches the
%% manifest the mind is actually offered would be silent and untestable
%% without this.
granted_capability_tool_appears_next_manifest(Dir) ->
    fun() ->
        Did = open_fresh(Dir),
        NamesBefore = [tool_name(T) || T <- mind_tools:manifest(Did)],
        ?assertNot(lists:member(<<"rag_search">>, NamesBefore)),
        %% grant/2 goes through the adversarial verifier for a REAL grant; here
        %% we exercise the manifest wiring directly, not the verifier gate.
        ok = soul:set_capabilities(Did, <<"rag_search\n">>),
        NamesAfter = [tool_name(T) || T <- mind_tools:manifest(Did)],
        ?assert(lists:member(<<"rag_search">>, NamesAfter)),
        ?assertNot(lists:member(<<"reach_web">>, NamesAfter))
    end.

%% The manifest is advisory (a model can attempt a tool it was never
%% offered); execute/2's own guard is the real boundary — assert it directly,
%% independent of whether the tool ever appeared in a manifest.
execute_refuses_an_ungranted_capability_even_if_called(Dir) ->
    fun() ->
        Did = open_fresh(Dir),
        Call = #{name => <<"rag_search">>, args => #{<<"query">> => <<"anything">>}},
        ?assertEqual({error, {capability_not_granted, rag_search}},
                     mind_tools:execute(Call, #{did => Did}))
    end.

%% None of these ever reach httpc: the SSRF guard rejects before fetch/1 runs
%% (mind_tools:guarded_fetch/1 and friends), so this needs no live network.
reach_web_refuses_private_and_loopback_hosts(Dir) ->
    fun() ->
        Did = open_fresh(Dir),
        ok = soul:set_capabilities(Did, <<"reach_web\n">>),
        BlockedAck = <<"reach_web: that host is not reachable (private/local network)">>,
        [?assertEqual({ok, #{ack => BlockedAck}}, reach_via_tool(Did, U)) ||
            U <- [<<"http://localhost/">>, <<"http://127.0.0.1/">>,
                  <<"http://10.0.0.5/">>, <<"http://192.168.1.1/">>,
                  <<"http://169.254.169.254/latest/meta-data/">>,
                  <<"http://172.16.0.1/">>, <<"http://172.31.255.255/">>,
                  <<"http://[::1]/">>]]
    end.

reach_web_refuses_a_non_http_scheme(Dir) ->
    fun() ->
        Did = open_fresh(Dir),
        ok = soul:set_capabilities(Did, <<"reach_web\n">>),
        ?assertEqual({ok, #{ack => <<"reach_web: only http/https URLs are allowed">>}},
                     reach_via_tool(Did, <<"file:///etc/passwd">>))
    end.

reach_via_tool(Did, Url) ->
    Call = #{name => <<"reach_web">>, args => #{<<"url">> => Url}},
    mind_tools:execute(Call, #{did => Did}).

tool_name(#{function := #{name := N}}) -> N.

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

empty_committee_question_is_rejected_before_convening_test() ->
    Call = #{name => <<"convene_committee">>, args => #{<<"question">> => <<>>}},
    ?assertEqual({error, empty_question},
                 mind_tools:execute(Call, #{did => <<"did:x">>})).

empty_retune_parameter_is_rejected_before_dispatch_test() ->
    Call = #{name => <<"retune_self">>,
             args => #{<<"parameter">> => <<>>, <<"value">> => <<"true">>}},
    ?assertEqual({error, empty_parameter},
                 mind_tools:execute(Call, #{did => <<"did:x">>})).

empty_grant_capability_is_rejected_before_dispatch_test() ->
    Call = #{name => <<"grant_capability">>, args => #{<<"capability">> => <<>>}},
    ?assertEqual({error, empty_capability},
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
