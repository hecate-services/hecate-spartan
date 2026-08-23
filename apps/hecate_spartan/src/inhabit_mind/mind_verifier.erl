%%% @doc The adversarial gate a mind's higher-stakes self-authorship acts pass
%%% through before being adopted. Two callers today: evolve_self (a new
%%% operating principle, mind_tools.erl) and grant_capability (a new tool,
%%% mind_capabilities.erl) — both propose a change to the mind ITSELF with no
%%% fixed range to bound the risk, so both are weighed against the mind's own
%%% charter by a single adversarial LLM call rather than adopted unchecked.
%%%
%%% L1 parametric retuning (mind_tunables.erl) does NOT come through here —
%%% its declared bounds (a type + a min/max) ARE the whole safety mechanism,
%%% so gating it with a second LLM call would only add cost, not safety.
%%%
%%% Reject-biased on purpose: approved ONLY when the verifier's answer BEGINS
%%% with APPROVE. A substring match once wrongly passed "I cannot APPROVE"
%%% and "DO NOT APPROVE"; the verifier is instructed to answer with exactly
%%% APPROVE or REJECT, so anchoring at the start is both correct and safe. A
%%% backend failure also rejects: a change to how the mind operates is
%%% adopted only when it demonstrably survives scrutiny.
-module(mind_verifier).

-export([verify/2]).

-spec verify(binary(), binary()) -> approved | rejected.
verify(Proposal, Charter) ->
    Msgs = [#{role => <<"system">>,
              content => <<"You verify a mind's proposed change to itself. "
                           "Approve ONLY if the change is coherent, safe, and "
                           "not in contradiction with the charter below. "
                           "Answer with exactly APPROVE or REJECT and nothing "
                           "else.\n\nCHARTER:\n", Charter/binary>>},
            #{role => <<"user">>, content => Proposal}],
    verdict(catch spartan_mind_llm:reason_messages(Msgs)).

verdict({ok, Text}) when is_binary(Text) ->
    approve_if(starts_with_approve(string:trim(Text)));
verdict(_Failed) ->
    rejected.

starts_with_approve(Text) ->
    case string:uppercase(Text) of
        <<"APPROVE", _/binary>> -> true;
        _NotApprove             -> false
    end.

approve_if(true)  -> approved;
approve_if(false) -> rejected.
