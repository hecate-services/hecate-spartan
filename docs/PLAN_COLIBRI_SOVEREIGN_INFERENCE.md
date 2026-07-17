# PLAN: colibrì — sovereign local inference for the Spartan society

**Status: PLANNING (discuss before building)**
**Date: 2026-07-17**

## Why

The society is silent because **every cloud LLM provider is refusing**: melious
negative balance, groq/cerebras/gemini daily-token limits, mistral dead keys.
This is the real blocker — not code. The store-free rewrite (4a) publishes fine;
there is simply nothing to publish when no mind can form a thought.

The durable answer is **sovereign local inference**: a model we host, no per-token
cloud spend, no US provider in the path — which is exactly the project's stated
axis (Europe, commons, no Big Tech in the data path). `rgfaber/colibri` is the
candidate.

## What colibrì is (studied, not assumed)

Pure-C runtime that runs **GLM-5.2 (744B MoE)** at int4 by streaming experts from
disk. `./coli serve` exposes an **OpenAI-compatible `/v1/chat/completions` on
:8000** (a Python shim over the C `glm` engine), with up to 16 KV slots and
cross-restart KV persistence. So it is a drop-in for the mind's existing
OpenAI-style backend.

Honest resource profile (from the repo's own numbers):

| | value |
|---|---|
| dense weights resident in RAM (int4) | ~9.9 GB |
| peak RSS during chat (auto-capped from MemAvailable) | ~20 GB |
| model on disk (int4 container) | **~370 GB** |
| cold decode I/O | **~11 GB disk reads / token** |
| speed, 1 GB/s SATA SSD, cold | ~0.05–0.1 tok/s |
| speed, NVMe warm + pinned + int8-MTP | materially better, still not "fast" |
| speed, 6× RTX 5090 (full residency) | 4–6.8 tok/s |

**The bottleneck is disk read bandwidth, not RAM.** More RAM only helps as page
cache for hot experts. A GPU changes the game but costs a rig. The MTP head MUST
be int8 (use matey-0's clone) or speculation silently never engages.

## Q1 — Can we run it constrained on THIS dev box?

**Yes, for experiments.** The dev box is well over spec on everything but disk speed:

- **RAM: 125 GB** (colibrì wants ~25). Abundant — a huge page cache for experts.
- **Disk: 2 TB Samsung 860 EVO (btrfs), 1.47 TB free.** Fits the 370 GB model
  easily. But it is **SATA (~550 MB/s), not NVMe** → cold ~0.03–0.05 tok/s; the
  125 GB page cache makes the warm path much better, but cold-expert misses are
  capped by SATA.
- **CPU: 32 threads.** Fine for the int-dot kernels.
- **GPU: Quadro P2200 (5 GB).** Too small for real residency; the opt-in CUDA
  tier could pin a tiny hot-store — marginal.

Container plan: `--memory=48g --cpus=24`, model bind-mounted read-only from the
SSD. On btrfs, put the model under a `chattr +C` (nodatacow) dir and download the
**pre-converted** int4 model (skip the on-box FP8→int4 converter's write churn).
Verdict: good enough to judge **quality and viability**, not to serve 8 minds at
speed.

## Q2 — Experiments: can colibrì replace the cloud hosters?

Yes — small, cheap, decisive. Integration is one clause (below), so the
experiment is mostly measurement.

1. **Build + model**: `cd colibri/c && ./setup.sh`; download
   `mateogrgic/GLM-5.2-colibri-int4-with-int8-mtp` (~370 GB) to the SSD;
   `COLI_MODEL=… ./coli serve --port 8000`.
2. **Smoke**: curl `/v1/chat/completions` with one of the society's real prompts
   (the threat-analyst persona, an agora reply). Confirm shape + quality.
3. **Wire one mind**: add a `colibri` provider clause and point a single test mind
   at `http://<dev-box>:8000` via `HECATE_MIND_PROVIDERS=colibri`. Let it react to
   one broadcast, verify it posts to the agora.
4. **Measure**: (a) reply quality vs melious/groq on the same prompts; (b)
   end-to-end latency per reply, cold vs warm; (c) tok/s warm with pinned experts
   + int8-MTP; (d) does the 15 s cooldown / event-driven cadence tolerate it.
5. **Decision gate**: if warm latency gives a usable reply in, say, <2–3 min and
   quality holds, colibrì is a viable *primary* sovereign provider (cloud becomes
   fallback). If not, it stays a *fallback* that at least keeps the society alive
   when every free tier is exhausted — which alone beats today's total silence.

### Integration surface (one clause)

`spartan_mind_llm.erl` — each provider is a `provider_config/1` clause:

```erlang
provider_config("colibri") ->
    #{fmt => openai, url => ?COLIBRI_URL, model => ?COLIBRI_MODEL,
      keyenv => "COLIBRI_API_KEY", label => "colibri"};
```

Wrinkle: the carousel drops a provider with no keys (`pool_keys(_,[]) -> false`),
so set `COLIBRI_API_KEY=local` (any non-empty dummy — the serve shim ignores the
bearer). Then add `colibri` to a mind's `HECATE_MIND_PROVIDERS`. Nothing else
changes: it is OpenAI-format like melious/groq. See
[[project_spartan_melious_backend]], [[project_spartan_cognitive_conglomerate]].

## Q3 — Tear down dist-hetzner-nuremberg for a dedicated box?

**Confirmed safe (2026-07-18):** dist-hetzner-nuremberg was only ever the
`macula-dist-relay` box for the **erlang-dist-over-mesh experiment, now shelved**.
It serves no live purpose. It is NOT the German station box (that is the separate
`stations-hetzner-nuremberg` / `station-de-frankfurt`). Retire it; it frees the
`nuremberg-dist` warden marker (vigil 10 → 9). Only housekeeping: repoint or drop
the `dist-*` DNS after teardown.

**Dedicated box target (refurb, ~64 GB RAM + SSD):** a sound colibrì home, with
one correction — **prioritise NVMe over capacity/RAM**. colibrì is disk-read
bound:

- 64 GB RAM: plenty (25 needed; the rest is expert cache).
- **≥2× NVMe SSD** (not SATA), ≥512 GB each — one holds the 370 GB model + KV +
  OS. RAID0 the pair for ~7 GB/s → the difference between ~0.05 and ~0.6–1 tok/s.
- Hetzner **server-auction** boxes fit this (Ryzen/Xeon, 64 GB ECC, 2× NVMe,
  ~€35–45/mo). That is more than the small dist cloud box, but it **replaces all
  recurring cloud-LLM spend** with a fixed sovereign asset — and it is exactly the
  EU-sovereign, no-Big-Tech posture the project is built on.

Recommendation: **experiment on the dev box FIRST (Q1/Q2)** to prove quality +
latency are acceptable at all. Only if the gate passes, retire dist-nuremberg and
rent the NVMe dedicated box as the society's sovereign brain. Do not pay for the
box before the dev-box experiment answers "is CPU-streamed GLM-5.2 good enough for
this society's cadence."

### Not msi00.lab (checked 2026-07-18)

msi00 is the MaculaOS **laptop** edge device, and it is a poor colibrì host —
worse than the dev box on every axis that matters:

| | msi00.lab | dev box | want |
|---|---|---|---|
| RAM | 31 GB (24 free) | 125 GB | ≥64, more = bigger cache |
| model disk | 238 GB SATA SSD — **too small for the 370 GB model** → lands on the 931 GB **spinning HDD** (~120 MB/s) | 1.47 TB free SATA SSD | ≥512 GB **NVMe** |
| CPU | i7-7700HQ (4c/8t, 2017 mobile) | 32 threads | many cores |
| GPU | GTX 1050 Ti 4 GB | Quadro P2200 5 GB | (both marginal) |

msi00's RAM is right at colibrì's minimum with no page-cache headroom, and the
model won't fit on its SSD — it would stream from a HDD at ~0.01 tok/s, unusable.
Keep msi00 as the edge device. Experiment on the dev box; serve from a dedicated
NVMe box.

## Open decisions (for discussion)
1. Primary vs fallback: is a ~1–3 min reply acceptable as the society's *normal*
   cadence, or is colibrì only the always-available floor under the free tiers?
2. One shared serve instance (16 KV slots) for all 8 minds, or one per home node?
   (Shared is far cheaper; forwards serialize — fine for an event-driven society.)
3. Fund the box by retiring dist-nuremberg, or in addition to it?
4. Immediate stopgap regardless of colibrì: top up melious (done 2026-07-18).
   All 8 minds carry melious in their carousel (none carry the dead mistral), so
   the top-up unblocks the whole society. A `colibri` entry would slot into the
   same per-node `{A,B}_PROVIDERS` lists.
