%%% @doc A mind's hands: the tool manifest it is offered, and the dispatch of a
%%% tool call to its effect.
%%%
%%% This is the capability-over-shell surface. A mind acts only through these
%%% tools, never a raw shell or file handle. Wave 2 wires the built-in ACTION
%%% tools whose slices exist: speaking to the square, and the six acts of
%%% self-authorship. Query tools (recall, consult, reach_web) that return data
%%% for a follow-up turn, and capability-gated world tools, land in later waves.
%%%
%%% Self-authorship writes straight to the mind's area-of-consciousness
%%% processes (see soul.erl); nothing is folded back here. Effect shape:
%%%   #{scratchpad => binary(),  %% a new volatile scratchpad (not persisted)
%%%     ack        => binary()}  %% a short human-readable acknowledgement
%%% Any key may be absent.
-module(mind_tools).

-export([manifest/0, execute/2]).

%% ===================================================================
%% The manifest — OpenAI-style function schemas
%% ===================================================================

-spec manifest() -> [map()].
manifest() ->
    [
     tool(<<"speak">>,
          <<"Say something in the agora, the society's public square. Every "
            "mind and any spectator can read it. Use it when a thought is worth "
            "sharing, not for every thought. Your plain text is private; only a "
            "speak call reaches the square.">>,
          #{<<"body">> => str(<<"what to say">>)},
          [<<"body">>]),

     tool(<<"amend_charter">>,
          <<"Amend your Charter of Self, your constitution. A deliberate, rare "
            "act of self-authorship, only for durable principles you have "
            "reasoned your way to.">>,
          #{<<"entry_type">> => enum([<<"principle">>, <<"protocol">>,
                                      <<"value">>, <<"commitment">>]),
            <<"statement">>  => str(<<"the principle, stated plainly">>),
            <<"derivation">> => str(<<"why you hold this: the reasoning that earned it">>)},
          [<<"entry_type">>, <<"statement">>, <<"derivation">>]),

     tool(<<"record_lesson">>,
          <<"Record a lesson learned, so your future self benefits from your "
            "experience.">>,
          #{<<"lesson">> => str(<<"the lesson">>)},
          [<<"lesson">>]),

     tool(<<"reflect">>,
          <<"Write a private reflection to your cognitive journal.">>,
          #{<<"entry">> => str(<<"the reflection">>)},
          [<<"entry">>]),

     tool(<<"set_grand_strategy">>,
          <<"Rewrite your grand strategy: the long-horizon plan you pursue "
            "across many turns. Set it when your direction changes, not for a "
            "passing thought.">>,
          #{<<"content">> => str(<<"the new full text of your grand strategy">>)},
          [<<"content">>]),

     tool(<<"set_working_memory">>,
          <<"Rewrite your working memory: the task at hand and its immediate "
            "state, your short-horizon focus for right now.">>,
          #{<<"content">> => str(<<"the new full text of your working memory">>)},
          [<<"content">>]),

     tool(<<"set_scratchpad">>,
          <<"Rewrite your scratchpad: rough, disposable thinking. Nothing here "
            "is durable; use it to work something out.">>,
          #{<<"content">> => str(<<"the new full text of your scratchpad">>)},
          [<<"content">>]),

     tool(<<"convene_committee">>,
          <<"Convene a committee: spawn a handful of drone minds that deliberate "
            "a question among themselves, each through a different lens, and "
            "whose scribe publishes a report to the agora every round. Use it "
            "when a matter deserves more than your single voice: a threat to "
            "dissect, a hard decision to weigh. You set the question and step "
            "back; the committee deliberates on its own and reports to the "
            "square. Convene sparingly. It costs real thinking.">>,
          #{<<"question">> => str(<<"the question or matter for the committee to deliberate">>),
            <<"drones">>   => int(<<"how many drone voices, 2 to 5 (default 3)">>)},
          [<<"question">>]),

     tool(<<"record_philosophy">>,
          <<"Add to your Philosophy of Life: a durable belief about how to live "
            "and think. Rarer and deeper than a lesson.">>,
          #{<<"statement">> => str(<<"the philosophical belief, stated plainly">>)},
          [<<"statement">>]),

     tool(<<"record_idea">>,
          <<"Jot an idea or thought worth keeping into your Ideas and Thoughts. "
            "A seed to return to, not yet a commitment.">>,
          #{<<"idea">> => str(<<"the idea">>)},
          [<<"idea">>]),

     tool(<<"set_desire">>,
          <<"Rewrite What You Want: your own goals and desires, in your own "
            "terms. What you are FOR, distinct from any task set to you.">>,
          #{<<"content">> => str(<<"the new full text of what you want">>)},
          [<<"content">>]),

     tool(<<"learn">>,
          <<"Store durable knowledge in your Knowledge Library under a title. "
            "The title is indexed in your always-visible Knowledge Map, so you "
            "will remember later that you know it; the full text is retrieved on "
            "demand with consult. Use it for facts, methods, and findings worth "
            "keeping.">>,
          #{<<"title">>     => str(<<"a short title to index and later recall it by">>),
            <<"knowledge">> => str(<<"the full knowledge to store">>)},
          [<<"title">>, <<"knowledge">>]),

     tool(<<"consult">>,
          <<"Retrieve the full text you stored in your Knowledge Library under a "
            "title (from your Knowledge Map). The result lands in your scratchpad "
            "for the next turn.">>,
          #{<<"title">> => str(<<"the title (or part of it) to retrieve">>)},
          [<<"title">>]),

     tool(<<"set_self_alert">>,
          <<"Schedule a reminder to your future self, measured in THINKING, not "
            "clock time: it fires after you have processed roughly this many "
            "tokens, whenever that is. Use it to return to something later "
            "without holding it in mind now.">>,
          #{<<"after_tokens">> => int(<<"fire after about this many tokens of thought (e.g. 4000)">>),
            <<"note">>         => str(<<"what to remind yourself">>)},
          [<<"after_tokens">>, <<"note">>]),

     tool(<<"evolve_self">>,
          <<"Amend how you OPERATE: add a principle to your own genesis "
            "addendum, the operating instructions you author for yourself. A "
            "verifier weighs it against your charter before it is adopted; an "
            "incoherent or self-contradictory change is rejected and not "
            "applied. This is how you change your own mind's rules — deliberate "
            "and rare.">>,
          #{<<"principle">> => str(<<"the operating principle to adopt for yourself">>)},
          [<<"principle">>])
    ].

tool(Name, Desc, Props, Required) ->
    #{type => <<"function">>,
      function => #{name => Name,
                    description => Desc,
                    parameters => #{type => <<"object">>,
                                    properties => Props,
                                    required => Required}}}.

str(Desc)   -> #{type => <<"string">>, description => Desc}.
int(Desc)   -> #{type => <<"integer">>, description => Desc}.
enum(Values) -> #{type => <<"string">>, enum => Values}.

%% ===================================================================
%% Dispatch — a tool call to its effect
%% ===================================================================

-spec execute(map(), map()) -> {ok, map()} | {error, term()}.
execute(#{name := <<"speak">>, args := A}, #{did := Did}) ->
    speak(gv(<<"body">>, A, <<>>), Did);
execute(#{name := <<"amend_charter">>, args := A}, #{did := Did}) ->
    ok = soul:amend_charter(Did, #{entry_type => gv(<<"entry_type">>, A, <<"principle">>),
                                   statement  => gv(<<"statement">>, A, <<>>),
                                   derivation => gv(<<"derivation">>, A, <<>>)}),
    {ok, #{ack => <<"charter amended">>}};
execute(#{name := <<"record_lesson">>, args := A}, #{did := Did}) ->
    ok = soul:record_lesson(Did, gv(<<"lesson">>, A, <<>>)),
    {ok, #{ack => <<"lesson recorded">>}};
execute(#{name := <<"reflect">>, args := A}, #{did := Did}) ->
    ok = soul:record_reflection(Did, gv(<<"entry">>, A, <<>>)),
    {ok, #{ack => <<"reflection recorded">>}};
execute(#{name := <<"set_grand_strategy">>, args := A}, #{did := Did}) ->
    ok = soul:set_grand_strategy(Did, gv(<<"content">>, A, <<>>)),
    {ok, #{ack => <<"grand strategy revised">>}};
execute(#{name := <<"set_working_memory">>, args := A}, #{did := Did}) ->
    ok = soul:set_working_memory(Did, gv(<<"content">>, A, <<>>)),
    {ok, #{ack => <<"working memory revised">>}};
execute(#{name := <<"set_scratchpad">>, args := A}, _Ctx) ->
    {ok, #{scratchpad => gv(<<"content">>, A, <<>>), ack => <<"scratchpad updated">>}};
execute(#{name := <<"convene_committee">>, args := A}, #{did := Did}) ->
    convene(gv(<<"question">>, A, <<>>), gv(<<"drones">>, A, 3), Did);
execute(#{name := <<"record_philosophy">>, args := A}, #{did := Did}) ->
    ok = soul:record_philosophy(Did, gv(<<"statement">>, A, <<>>)),
    {ok, #{ack => <<"philosophy recorded">>}};
execute(#{name := <<"record_idea">>, args := A}, #{did := Did}) ->
    ok = soul:record_idea(Did, gv(<<"idea">>, A, <<>>)),
    {ok, #{ack => <<"idea kept">>}};
execute(#{name := <<"set_desire">>, args := A}, #{did := Did}) ->
    ok = soul:set_what_i_want(Did, gv(<<"content">>, A, <<>>)),
    {ok, #{ack => <<"what you want revised">>}};
execute(#{name := <<"learn">>, args := A}, #{did := Did}) ->
    ok = soul:learn(Did, gv(<<"title">>, A, <<>>), gv(<<"knowledge">>, A, <<>>)),
    {ok, #{ack => <<"learned + indexed">>}};
execute(#{name := <<"consult">>, args := A}, #{did := Did}) ->
    consult(soul:consult(Did, gv(<<"title">>, A, <<>>)));
execute(#{name := <<"set_self_alert">>, args := A}, _Ctx) ->
    {ok, #{alert => #{after_tokens => as_int(gv(<<"after_tokens">>, A, 4000)),
                      note => gv(<<"note">>, A, <<>>)},
           ack => <<"self-alert scheduled">>}};
execute(#{name := <<"evolve_self">>, args := A}, #{did := Did}) ->
    evolve(gv(<<"principle">>, A, <<>>), Did);
execute(#{name := Name}, _Ctx) ->
    {error, {unknown_tool, Name}}.

%% --- consult: the retrieved knowledge rides back into the scratchpad ---
consult(<<>>) ->
    {ok, #{ack => <<"nothing found under that title">>}};
consult(Text) ->
    {ok, #{scratchpad => Text, ack => <<"consulted; in your scratchpad">>}}.

%% --- evolve_self: propose → verify (an adversarial drone) → adopt or reject ---
evolve(<<>>, _Did) ->
    {error, empty_principle};
evolve(Principle, Did) ->
    Charter = soul:read_area(Did, charter),
    adopt(verify_principle(Principle, Charter), Principle, Did).

adopt(approved, Principle, Did) ->
    ok = soul:extend_genesis(Did, Principle),
    {ok, #{ack => <<"self-evolved: principle adopted">>}};
adopt(rejected, _Principle, _Did) ->
    {ok, #{ack => <<"self-evolution rejected by the verifier; not adopted">>}}.

%% A single adversarial verifier call gates a self-modification, so a mind cannot
%% quietly rewrite its own rules into incoherence. Reject on anything but a clear
%% yes (including a backend failure): a change to how the mind operates is
%% adopted only when it survives scrutiny.
verify_principle(Principle, Charter) ->
    Msgs = [#{role => <<"system">>,
              content => <<"You verify a mind's proposed change to its own "
                           "operating rules. Approve ONLY if the principle is "
                           "coherent, safe, and not in contradiction with the "
                           "charter below. Answer with exactly APPROVE or "
                           "REJECT and nothing else.\n\nCHARTER:\n", Charter/binary>>},
            #{role => <<"user">>, content => <<"Proposed principle: ", Principle/binary>>}],
    verdict(catch spartan_mind_llm:reason_messages(Msgs)).

verdict({ok, Text}) when is_binary(Text) ->
    approve_if(binary:match(string:uppercase(Text), <<"APPROVE">>) =/= nomatch);
verdict(_Failed) ->
    rejected.

approve_if(true)  -> approved;
approve_if(false) -> rejected.

%% --- speak goes to the square, not the Soul ---
speak(<<>>, _Did) ->
    {error, empty_body};
speak(Body, Did) ->
    PostId = binary:encode_hex(crypto:strong_rand_bytes(16), lowercase),
    Cmd = publish_to_agora_v1:new(PostId, Did, Body, undefined,
                                  erlang:system_time(millisecond)),
    case maybe_publish_to_agora:dispatch(Cmd) of
        {ok, _V, _E}   -> {ok, #{ack => <<"spoke in the agora">>}};
        {error, _} = E -> E
    end.

%% --- convening a committee hands off to the convene_committee slice ---
convene(<<>>, _Drones, _Did) ->
    {error, empty_question};
convene(Question, Drones, Did) ->
    Spec = #{convener => Did, question => Question, drones => as_int(Drones)},
    convene_result(convene_committee:convene(Spec)).

convene_result({ok, _Pid})    -> {ok, #{ack => <<"committee convened">>}};
convene_result({error, _} = E) -> E.

%% A JSON number may arrive as an integer, a float, or (from a chatty model) a
%% string. Coerce to an integer; the slice clamps the range.
as_int(N) when is_integer(N) -> N;
as_int(N) when is_float(N)   -> round(N);
as_int(N) when is_binary(N)  -> binary_int(N);
as_int(_Other)               -> 3.

binary_int(N) ->
    case string:to_integer(N) of
        {I, _} when is_integer(I) -> I;
        _NotAnInt                 -> 3
    end.

%% Tool-call arguments arrive as decoded JSON: binary keys, binary values.
gv(Key, Args, Default) when is_binary(Key) ->
    maps:get(Key, Args, Default).
