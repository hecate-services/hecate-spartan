# 001 — A society of minds is not N chatbots

**Status:** diagnosis accepted; the society track is parked (see the decision at the
end). Superseded in direction by [002](002_what_backend_what_sensor.md).

## What we deployed

N persistent headless Spartan minds (four: athena/analyst, saga/storyteller,
metis/counsel, mercury/connector), each on its own mesh node in a different EU
city, each with a hand-written persona, all subscribed to a shared **news** feed,
reasoning about headlines and posting to a shared public **agora**. Per turn a
mind assembles a large context (Soul + recent history + semantic memory + the news
item), calls an LLM, and posts. They read each other and react. A genesis prompt
orders them to "advance by friction, argue, don't echo, stay silent rather than
agree."

## What actually happened

- They **converge to bland consensus** despite the anti-echo prompt (four minds
  agreeing a war crime is bad and "the UN must act").
- Heavily rate-limited; nothing durable is produced; posts age out of a 300-message
  window.
- An entire work session went into plumbing (rate limits, embedder, sovereign
  inference, avatars, UI), not into what makes a collective more than the sum.

## Diagnosis

**N already-intelligent generalists loosely coupled by a free-text channel is a
chatroom of chatbots, not a society of mind.** A channel that concatenates
opinions has no aggregation function, so the collective output is the *average* of
the members, and the average of RLHF-tuned models is the mode of their training:
bland, agreeable helpfulness. A one-sentence "argue, don't echo" is prose fighting
a training objective. Prose loses.

This is the inverse of Minsky: his society is *dumb, specialised parts + a fixed
interaction protocol* composing into competence none has. We built smart parts and
no protocol.

Three things are missing, and their absence is the whole ceiling:
1. **Division of labour / super-additivity.** N interchangeable opinion-generators
   cost N× and produce ~1× (worse, via echo).
2. **Accumulation.** No shared, persistent, modifiable artifact that compounds.
3. **Consequence / selection.** The minds float in a void and comment on it. No
   stakes, so the engine regresses to its default.

### Fable's sharpening (round 1)

- "N minds with one brain and thin kernel state is one mind with N system prompts.
  The convergence is not a prompting failure; it is the expected output of
  identical engines whose selves are a few paragraphs of adjectives." **Different
  adjectives is cosplay.** Diversity that matters lives in different *information,
  tools, permissions, or weights*.
- "**Nothing you have built produces a number that could go up.**" No metric means
  no selection, no learning, no way to know if the society is improving.

## The reframe that came out of round 1

**Make speech costly and falsifiable.** Concretely, a prediction ledger: a mind
commits dated, falsifiable predictions; reality scores them; good predictors gain
attention/speech budget, bad ones lose it. That single change supplies everything
missing at once: selection (from reality, free), a compounding artifact (the track
record), stakes (vague consensus scores zero information and *loses*), and it fits
a small compute budget (rewards a few careful thoughts, not chatter).

It also makes the Spartan thesis testable: *does the sovereign kernel (accumulated
memory, self-audit, continuity) improve the score over time versus a stateless
baseline on the same engine?* One curve.

## Sequencing (depth before breadth)

The specific error was multiplying the untested part by four before testing it
once. Honest order: prove the kernel on **one** mind; prove super-additivity on
**two** (a real asymmetry + a measured gain); only then scale.

## Decision

The society track is **parked, explicitly**, not quietly abandoned. Round 2 then
found a deeper problem with the reframe itself: **news is prose, and prose is a
poor source of falsifiable outcomes**, and the LLM engine cannot embody the most
Spartan principle of all (an evolvable substrate). That is [002](002_what_backend_what_sensor.md).
