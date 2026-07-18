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

-export([reason/2]).

-spec reason([map()], [map()]) ->
    {ok, {binary(), [map()], non_neg_integer()}} | {error, term()}.
reason(Messages, Tools) ->
    run(enabled(), Messages, Tools).

run(false, Messages, Tools) ->
    spartan_mind_llm:reason_tools(Messages, Tools);
run(true, Messages, Tools) ->
    verify(spartan_mind_llm:reason_tools(Messages, Tools), Messages, Tools).

%% A failed draft has nothing to verify; propagate the error.
verify({error, _} = E, _Messages, _Tools) ->
    E;
verify({ok, {Draft, Calls, T1}}, Messages, Tools) ->
    audit(Draft, Calls, T1, Messages, Tools).

%% Nothing drafted (a silent PASS) needs no audit.
audit(<<>>, Calls, T1, _Messages, _Tools) ->
    {ok, {<<>>, Calls, T1}};
audit(Draft, Calls, T1, Messages, Tools) ->
    VerifyMsgs = Messages ++ [draft_msg(Draft), audit_instruction()],
    reconcile(spartan_mind_llm:reason_tools(VerifyMsgs, Tools), Draft, Calls, T1).

%% Verified output is canonical (token cost = both passes). If the verify pass
%% itself fails, keep the draft rather than fall silent.
reconcile({ok, {Text, Calls, T2}}, _Draft, _DraftCalls, T1) ->
    {ok, {Text, Calls, T1 + T2}};
reconcile({error, _}, Draft, DraftCalls, T1) ->
    {ok, {Draft, DraftCalls, T1}}.

draft_msg(Draft) ->
    #{role => <<"assistant">>, content => Draft}.

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

enabled() ->
    off_values(os:getenv("HECATE_MIND_MINDFULNESS")).

off_values("off")   -> false;
off_values("0")     -> false;
off_values("false") -> false;
off_values(_On)     -> true.
