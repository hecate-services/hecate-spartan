# 012 — What survives: the substrate after the kernel dies

**Status:** direction note. Not an experiment — the synthesis that turns the signed
negative (011) into a deliberate next heading instead of drift. It answers the log's
founding question, "what is Spartan actually a substrate *for*," now that the
falsification has removed one wrong answer.

## ELI5

We spent this program testing one idea: a mind that gets better over time by
*re-injecting* its own remembered examples into how it thinks. It failed, for a deep
reason — remembered examples go stale, and re-learning from what's in front of you
beats replaying the past. But notice *what kept winning* while inject lost: plain
*looking things up* — keeping memory OUTSIDE the thinker and consulting it fresh,
never baking it in. That is the whole design of a public knowledge commons: news,
science, questions, all kept outside, queried when needed, never fine-tuned into a
frozen brain. So the thing that died points straight at the thing to build.

## What died, precisely

The evolvability branch (note 002) and its portable numerical kernel (004): memory as
canonical exemplars *replayed into* the engine's own learning, so a sovereign kernel
"improves over time" on a swappable engine. 011 falsified it — restoration loses to
restart under drift, even with a perfect recognizer. The language-bound faculties
(narrative self-authorship) were already conceded LLM-only in 004. So the
"engine-agnostic self that persists and improves via injected memory" is gone on both
legs: the portable leg is falsified, the language leg never ported.

## What actually won (and we under-read it)

Across every run, the mechanisms ranked, for numerical non-stationary prediction:

> **forget-and-relearn (engine+reset) > external retrieval (k-NN) > inject-into-engine.**

The two winners share one property the loser lacks: **they never mutate the engine
with the past.** Reset throws stale weights away; retrieval keeps the past in an
*external store queried at use* and leaves the engine alone. Inject is the only one
that writes history into the working machinery — and it is the one that died. The
lesson is not "memory is useless"; arm E (pure external retrieval) was the strong
control the whole program had to beat. The lesson is **where memory lives**: outside
and queried, never inside and baked.

## The reframe for the public substrate

This is not a detour away from the substrate pivot (news/science/ask); it is its
architecture, stated sharply:

1. **Memory is external, queried at use, freshness-aware — never injected.** That is
   RAG over a content-addressed mesh commons, not fine-tuning-on-history, not a
   continuity kernel, not weight-inject. The staleness mechanism that killed inject is
   inherited by *anything* that bakes the past into the engine; a queried store
   sidesteps it by construction (it can always return the *current* item).
2. **The differentiator is the commons, not a kernel.** Value comes from a public,
   federated, non-extractive corpus (sovereign sources, content-addressed, our
   European stance) plus query-time synthesis — not from a mind that mysteriously
   improves. There is no sovereign-improving-kernel to sell; there is a sovereign
   *commons* to steward.
3. **"Society of minds" stays suspect until it aggregates (001).** N chatting LLMs
   average to the RLHF mode. If a collective is to beat one model, the aggregation
   must be structural — selection/curation/retrieval over the commons — not more
   conversation. The commons IS the aggregation substrate; the minds query it, they
   do not replace it.

## The one honest positive to carry forward

Detection + forgetting beats lookup on a competent engine. Generalised: **a substrate
should adapt fast to the present and consult the past externally, not carry the past
inside its reasoning.** That is a design principle for hecate-news / hecate-rag, and
it is the only load-bearing thing the kernel program leaves behind — besides the
harness itself, which remains, ready to falsify the *next* claim before we believe it.

## Next heading

Away from the evolvable kernel (moot), toward the queried commons: get hecate-news
producing into the mesh, retrieval (hecate-rag) reading it fresh, and — before any
new "the substrate does X" claim is believed — a pre-registered kill threshold and a
Fable round, because that discipline is the other thing that worked.
