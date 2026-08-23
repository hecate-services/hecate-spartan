%%% @doc MINDfulness: draft, then verify — Gene Sher's self-audit.
%%%
%%% A single LLM call emits plausible text; it does not check itself. Gene's
%%% mind reasons in two passes: it DRAFTS an action, then re-submits the draft
%%% with a standing order to assume it may be wrong and verify every claim
%%% against the visible context (confabulation, sycophancy, hallucination,
%%% unverified provenance). Only the verified output is acted on. This is the
%%% difference between a mind and a plausible-text emitter, and the most likely
%%% cure for shallow, un-grounded posts.
%%%
%%% Cost: two calls per reasoning. Our loop is event-driven, so this only ever
%%% runs on genuine new input (never Gene's idle "MINDfulness Round 329" spin).
%%% It is on by default; HECATE_MIND_MINDFULNESS=off disables it per node when
%%% provider budget is tight. Same return shape as spartan_mind_llm:reason_tools/2,
%%% so it is a drop-in for the reasoning call.
-module(mindfulness).

-export([reason/2, reason/3, enabled/1]).

-spec reason([map()], [map()]) ->
    {ok, {binary(), [map()], non_neg_integer()}} | {error, term()}.
reason(Messages, Tools) ->
    run(enabled(), Messages, Tools).

%% @doc Same as reason/2, but a mind that has retuned its OWN mindfulness (via
%% the retune_self tool, see mind_tunables.erl) is honored ahead of the
%% node-wide env var, which stays the fleet default for a mind that never
%% retuned itself.
-spec reason(binary(), [map()], [map()]) ->
    {ok, {binary(), [map()], non_neg_integer()}} | {error, term()}.
reason(Did, Messages, Tools) ->
    run(enabled(Did), Messages, Tools).

run(false, Messages, Tools) ->
    spartan_mind_llm:reason_tools(Messages, Tools);
run(true, Messages, Tools) ->
    verify(spartan_mind_llm:reason_tools(Messages, Tools), Messages, Tools).

%% A failed draft has nothing to verify; propagate the error.
verify({error, _} = E, _Messages, _Tools) ->
    E;
verify({ok, {Draft, Calls, T1}}, Messages, Tools) ->
    audit(Draft, Calls, T1, Messages, Tools).

audit(Draft, Calls, T1, Messages, Tools) ->
    audit(has_content(Draft, Calls), Draft, Calls, T1, Messages, Tools).

%% A truly silent PASS (no text AND no actions) needs no audit. But a draft that
%% is ACTION-ONLY (empty text, tool calls chosen) is the case Gene's audit exists
%% for — it must be verified, not waved through, so an action-only draft (common
%% for tool-calling models) is no longer a bypass.
audit(false, Draft, Calls, T1, _Messages, _Tools) ->
    {ok, {Draft, Calls, T1}};
audit(true, Draft, Calls, T1, Messages, Tools) ->
    VerifyMsgs = Messages ++ [draft_msg(Draft, Calls), audit_instruction()],
    reconcile(spartan_mind_llm:reason_tools(VerifyMsgs, Tools), Draft, Calls, T1).

has_content(<<>>, []) -> false;
has_content(_Draft, _Calls) -> true.

%% Verified output is canonical (token cost = both passes). If the verify pass
%% itself fails, keep the draft rather than fall silent.
reconcile({ok, {Text, Calls, T2}}, _Draft, _DraftCalls, T1) ->
    {ok, {Text, Calls, T1 + T2}};
reconcile({error, _}, Draft, DraftCalls, T1) ->
    {ok, {Draft, DraftCalls, T1}}.

%% Show the verifier BOTH the private reasoning AND the actions the draft chose
%% (speak/convene/…), so the audit gates the ACTIONS — Gene's design — not just
%% the text a second time.
draft_msg(Draft, Calls) ->
    #{role => <<"assistant">>,
      content => iolist_to_binary([draft_text(Draft), render_calls(Calls)])}.

draft_text(<<>>) -> <<"(no private text)">>;
draft_text(Text) -> Text.

render_calls([]) ->
    [];
render_calls(Calls) ->
    ["\n\nActions you propose to take (verify each is warranted before it runs):\n",
     [["- ", action_desc(C), "\n"] || C <- Calls]].

action_desc(Call) when is_map(Call) ->
    iolist_to_binary([maps:get(name, Call, <<"?">>), " ",
                      args_preview(maps:get(args, Call, #{}))]);
action_desc(_Other) ->
    <<"(unrecognized action)">>.

args_preview(Args) when is_map(Args), map_size(Args) > 0 ->
    clip(safe_encode(Args));
args_preview(_Empty) ->
    <<>>.

safe_encode(Args) ->
    try jsx:encode(Args) catch _:_ -> <<"{...}">> end.

clip(B) when byte_size(B) =< 200 -> B;
clip(B) -> <<(binary:part(B, 0, 200))/binary, "…"/utf8>>.

audit_instruction() ->
    #{role => <<"system">>,
      content => <<"Before you act: the message above is your own DRAFT, and it "
                   "may be wrong. Verify every claim in it against the context "
                   "you were given. Check for confabulation (asserting what you "
                   "cannot support), sycophancy (agreeing to be agreeable), "
                   "hallucinated detail, and unverified provenance. Then produce "
                   "your FINAL response — corrected where the draft was wrong, "
                   "kept where it was sound, and silent if the draft added "
                   "nothing worth saying. Only this final response is real.">>}.

%% @doc Whether MINDfulness is currently on for this mind: its own retune if
%% it made one, else the node-wide default. Exported so the HUD (proprioception)
%% reflects the same value this mind's reasoning actually runs with.
-spec enabled(binary()) -> boolean().
enabled(Did) ->
    case catch mind_tunables:retuned(Did, mindfulness) of
        {ok, B} when is_boolean(B) -> B;
        _NotSet                    -> enabled()
    end.

enabled() ->
    off_values(os:getenv("HECATE_MIND_MINDFULNESS")).

off_values("off")   -> false;
off_values("0")     -> false;
off_values("false") -> false;
off_values(_On)     -> true.
