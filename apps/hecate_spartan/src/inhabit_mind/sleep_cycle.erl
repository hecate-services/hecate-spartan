%%% @doc The Sleep Cycle: a mind's memory consolidation process.
%%%
%%% Gene Sher's Spartan condenses raw experience into Condensed Memory Objects
%%% (CMOs) and CMOs into Meta-Summary Objects (MSOs) so a long-lived mind
%%% remembers its life instead of forgetting it past a window. This is the
%%% BEAM-native realization: a dedicated process per mind that, when the raw
%%% short-term tier fills, reflects it into a CMO and trims it; and when CMOs
%%% accumulate, condenses them into an MSO.
%%%
%%% Reflection uses the mind's own LLM (spartan_mind_llm) to write an
%%% abstractive insight; there is deliberately NO deterministic fallback when
%%% no backend is reachable (see reflect/2) — the tier is left untrimmed and
%%% retried later rather than filing a truncated raw join as if it were a
%%% real reflection. Nudged after each turn; it decides when it is due.
%%%
%%% See docs/DESIGN_MIND_FACULTIES.md for the theory (Generative Agents'
%%% reflection, memory consolidation, the Common Model's declarative memory).
-module(sleep_cycle).
-behaviour(gen_server).

-export([start_link/1, nudge/1]).
-export([init/1, handle_cast/2, handle_call/3]).

%% Budgets: consolidate STM at STM_FULL entries, keeping STM_KEEP raw; likewise
%% for the meta level. Small so the effect is visible; tune later.
-define(STM_FULL, 8).
-define(STM_KEEP, 2).
-define(CMO_FULL, 6).
-define(CMO_KEEP, 2).
%% A CMO/MSO is a GIST, not an archive. Cap it hard (grapheme-safe): a failed
%% reflection falls back to the raw join, which — compounded up the tiers and
%% never trimmed — ballooned a mind's context to ~70k tokens (every future turn
%% carried it). Cap the gist, and bound the MSO tier so meta-summaries don't
%% accumulate forever.
-define(REFLECT_MAX_CHARS, 800).
-define(MSO_KEEP, 4).
%% THE OUTPUT cap above was only half the fix. On a sustained provider outage,
%% "no gist, no trim" (by design — see advance_stm/3) leaves the untrimmed tier
%% growing by one entry per turn while it keeps missing ?STM_FULL/?CMO_FULL,
%% and every retry re-joined the WHOLE tier as the reflection INPUT. That input
%% was never capped, so the death spiral this comment already named once
%% recurred and got worse: 2026-08-24, mercury's join reached 809,751 tokens,
%% blowing through every configured provider's context window in turn (groq
%% 131k, melious 80k) and burning a chunk of groq's TPD quota on requests that
%% could only ever fail. Bounding the INPUT join to the same size that trips
%% consolidation (?STM_FULL / ?CMO_FULL) makes every reflection attempt cost
%% the same regardless of how large the untrimmed backlog has grown — the
%% retry can still fail on a dead provider, but it can never fail BIGGER than
%% the last attempt. Nothing is destroyed: the full record still lives in
%% mind_journal (see memory.erl), only the LLM PROMPT is windowed.
-define(REFLECT_STM_WINDOW, ?STM_FULL).
-define(REFLECT_CMO_WINDOW, ?CMO_FULL).
%% How long to leave a failed reflection alone before trying again.
-define(RETRY_MS, 60000).

-spec start_link(map()) -> {ok, pid()} | {error, term()}.
start_link(#{did := Did} = Spec) ->
    gen_server:start_link({local, memory:sleep_name(Did)}, ?MODULE, Spec, []).

%% @doc Ask the mind to consider consolidating (fire and forget; non-blocking).
-spec nudge(gen_server:server_ref()) -> ok.
nudge(Ref) -> gen_server:cast(Ref, consolidate).

init(#{did := _Did} = Spec) ->
    {ok, Spec}.

handle_cast(consolidate, #{did := Did} = S) ->
    {noreply, attempt(due(S), Did, S)};
handle_cast(_Msg, S) ->
    {noreply, S}.

handle_call(_Req, _From, S) ->
    {reply, ok, S}.

%% --- consolidation ---

%% A failed reflection is retried on a later nudge, not immediately: a dead
%% provider would otherwise be hammered once per observed turn.
due(#{next_try := T}) -> erlang:system_time(millisecond) >= T;
due(_NoneYet)         -> true.

attempt(false, _Did, S) -> S;
attempt(true, Did, S)   -> backoff(catch consolidate(Did), S).

backoff(ok, S)      -> S#{next_try => 0};
backoff(_Failed, S) -> S#{next_try => erlang:system_time(millisecond) + ?RETRY_MS}.

consolidate(Did) ->
    Stm = memory:store_name(Did, stm),
    stm_step(memory_store:count(Stm) >= ?STM_FULL, Did, Stm).

stm_step(false, _Did, _Stm) ->
    ok;
stm_step(true, Did, Stm) ->
    advance_stm(reflect(<<"experiences">>, texts(memory_store:recent(Stm, ?REFLECT_STM_WINDOW))), Did, Stm).

%% NO GIST, NO TRIM. Consolidation that destroys raw experience because a provider
%% was down is how a mind forgets a day it actually lived. Gene aborts and retries
%% with the memory preserved (spartan.py:2398-2406); so do we. The previous code
%% trimmed regardless and filed a truncated raw join as if it were a reflection,
%% which also made a failed consolidation indistinguishable from a good one.
advance_stm(error, Did, _Stm) ->
    logger:notice("[sleep_cycle] ~ts reflection unavailable; STM kept intact", [Did]),
    {error, no_reflection};
advance_stm({ok, Cmo}, Did, Stm) ->
    ok = record(Did, cmo, Cmo),
    memory_store:add(memory:store_name(Did, cmo), entry(Cmo)),
    memory_store:trim(Stm, ?STM_KEEP),
    Cmos = memory:store_name(Did, cmo),
    cmo_step(memory_store:count(Cmos) >= ?CMO_FULL, Did, Cmos).

cmo_step(false, _Did, _Cmos) ->
    ok;
cmo_step(true, Did, Cmos) ->
    advance_cmo(reflect(<<"condensed memories">>, texts(memory_store:recent(Cmos, ?REFLECT_CMO_WINDOW))), Did, Cmos).

advance_cmo(error, Did, _Cmos) ->
    logger:notice("[sleep_cycle] ~ts meta-reflection unavailable; CMOs kept intact", [Did]),
    {error, no_reflection};
advance_cmo({ok, Mso}, Did, Cmos) ->
    ok = record(Did, mso, Mso),
    Msos = memory:store_name(Did, mso),
    memory_store:add(Msos, entry(Mso)),
    memory_store:trim(Msos, ?MSO_KEEP),
    memory_store:trim(Cmos, ?CMO_KEEP).

%% The gist is LLM output, so it is not reproducible by replay: the journal record
%% has to carry the text itself. Written BEFORE the tiers are touched.
record(Did, Tier, Gist) ->
    _ = mind_journal:append(Did, gist_formed_v1, #{tier => Tier, text => Gist}),
    ok.

%% Reflect a set of texts into one insight. Abstractive via the LLM, or `error' —
%% there is deliberately no deterministic fallback, because a fallback that looks
%% like a success is how a silent failure becomes permanent data loss.
reflect(Kind, Texts) ->
    from_llm(catch (reflector())(prompt(Kind, join(Texts)))).

%% The reflector is a seam. Production folds texts into an insight with the mind's
%% own LLM; a test supplies a deterministic one. Without it a test can only ever
%% exercise the failure path, which is how the old deterministic fallback came to
%% be mistaken for correct behaviour.
reflector() ->
    application:get_env(hecate_spartan, mind_reflector,
                        fun spartan_mind_llm:reason_messages/1).

from_llm({ok, Text}) when is_binary(Text), Text =/= <<>> ->
    {ok, cap(Text)};
from_llm(_Failed) ->
    error.

%% A gist must SHRINK. Cap it (grapheme-safe) so a failed reflection's raw join —
%% or a runaway model — cannot bloat the tier that every future turn carries.
cap(Text) when is_binary(Text) ->
    case string:length(Text) > ?REFLECT_MAX_CHARS of
        true  -> unicode:characters_to_binary([string:slice(Text, 0, ?REFLECT_MAX_CHARS), "…"]);
        false -> Text
    end.

prompt(Kind, Joined) ->
    [#{role => <<"system">>,
       content => <<"Consolidate the following ", Kind/binary,
                    " into one durable, first-person insight of two or three "
                    "sentences. Keep what will matter to you later; drop the "
                    "transient. Write only the insight.">>},
     #{role => <<"user">>, content => Joined}].

texts(Entries) ->
    [maps:get(text, E, <<>>) || E <- Entries].

join(Texts) ->
    iolist_to_binary(lists:join(<<"\n">>, Texts)).

entry(Text) ->
    #{text => Text, at => erlang:system_time(millisecond), importance => 5}.
