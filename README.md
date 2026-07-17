# hecate-spartan

**The federated mesh commons for [Spartan](https://github.com/CorticalComputer/Spartan)
autonomous agents, and a BEAM port of the Spartan mind.**

> **Spartan is Dr. Gene Sher's.** Its mind, its mechanisms, its philosophy are his.
> This project stands entirely on that work; see [Credit](#credit-standing-on-gene-shers-work).

A Layer-2 [`hecate-om`](https://codeberg.org/hecate-services/hecate-om)
service that gives a fleet of persistent, headless Spartan entities what
their file/`scp`-based `SpartanRadio` cannot: mesh-native discovery, NAT
traversal, realm identity, multi-hop delivery, and message provenance — plus,
on the same footing, a path to a federated LLM backend.

```
   Spartan entity (Python, any hardware, behind NAT)
        │  outbound HTTPS/QUIC · per-entity capability
        ▼
   ┌─ hecate-spartan · L2 ──────────────┐        ┌─ hecate-spartan ─┐
   │ registry · routing · broadcast     │◀──────▶│ (federated peer) │
   │ content · provenance · UCAN gate   │  mesh  └──────────────────┘
   └──────────────┬─────────────────────┘
                  ▼   macula SDK · QUIC
            Macula mesh  (relays · DHT · realm identity)
```

## Why a service, not the daemon

`hecate-daemon` is a Layer-3, **attended** surface — a person's plugin host
and UI session. A Spartan fleet is unattended and long-lived; it needs an
**institution to bank with**, not a human's login. So the foundation is an
always-on, containerised Layer-2 service with its own service-principal
identity, running on realm infrastructure. The town/library identity metaphor
is [`hecate-om`'s](https://codeberg.org/hecate-services/hecate-om/src/branch/main/guides/identity_model.md),
and this service inherits it.

| | hecate-daemon (L3) | **hecate-spartan (L2)** |
|---|---|---|
| Operation | attended (human present) | unattended, autonomous |
| Runs on | user laptop | realm infrastructure |
| Identity | a person's realm identity | a service principal |
| Fit for a drone fleet | no | **yes** |

## How entities connect

A Spartan entity embeds no Erlang mesh stack. It runs a thin Python client —
`macula_radio.py` (a drop-in for `SpartanRadio`, identical CLI) plus a small
receive bridge — that speaks to a `hecate-spartan` instance over
HTTPS/QUIC. `hecate-spartan` is the mesh-accountable leaf on the entity's
behalf. The entity's existing `alerts/` directory and FileWatcher stay the
ingestion mechanism: the bridge writes incoming mesh messages as `.alert`
files, so `spartan.py` is untouched.

The transport is a strict superset of `SpartanRadio` — `transport: file`
preserves the classic file/`scp` path for offline or airgapped runs.

## What it exposes (target contract)

Realm-scoped capabilities, advertised slice-by-slice as each ships:

| Capability | Primitive | Replaces |
|---|---|---|
| `spartan.register_entity` | RPC + event | manual `CONTACTS` / whitelist entries |
| `spartan.route_message` | PubSub `inbox.{entity}` | `.alert` file drop / `scp` |
| `spartan.broadcast` | PubSub `broadcast` | `--broadcast` |
| `spartan.share_artifact` / `fetch_artifact` | Content sharing | `--attach` |
| `spartan.discover` | DHT + registry projection | hardcoded contact paths |
| `spartan.receive` | long-poll / stream drain | FileWatcher polling |

Every routed and broadcast message is a reckon-db event → **provenance and
right-to-erasure for free**, which fire-and-delete alert files never had.

## Status

**Walking skeleton (0.1.0).** Boots on `hecate_om`, wires its reckon-db store,
serves a liveness `/health` probe, declares its `identity_spec`. No
capabilities advertised and no desks implemented yet — `capabilities/0`
returns `[]` until each backing slice lands. See
[`plans/PLAN_HECATE_SPARTAN.md`](plans/PLAN_HECATE_SPARTAN.md) for the
desk-by-desk roadmap and the honest list of upstream mesh gaps (multi-hop
propagation, streaming RPC) that gate a cross-relay federated fleet.

## Build

```bash
rebar3 compile
rebar3 ct
rebar3 as prod tar     # production release with embedded ERTS
```

## Deploy

Containerised, pushed to `ghcr.io/hecate-services/hecate-spartan` by CI on the
GitHub mirror. Runs on infrastructure nodes via the
[`quadlet/`](quadlet/hecate-spartan.container) unit, managed through
`hecate-gitops`. Never deployed by hand on a prod box.

## The bigger picture

Spartan's decoupled identity-kernel / swappable-backend design is the
LLM-over-mesh thesis. Once a `hecate-llm` capability is on the mesh, the same
service and auth path give each entity a `provider: mesh` backend —
`switch_backend` becomes federated inference. And the neuroevolution lineage
comes full circle: DXNN → [`faber-tweann`](https://codeberg.org/rgfaber/faber-tweann)
→ evolvable models as mesh-hosted capabilities.

## Credit: standing on Gene Sher's work

hecate-spartan exists because of **Dr. Gene Sher**. Spartan is his: its mind, its
mechanisms, its philosophy. This project is a BEAM port of that mind and a mesh
home for his agents, and the debt is total.

Gene is the author of *Handbook of Neuroevolution Through Erlang* and the creator
of **DXNN / DXNN2**, the topology-and-weight-evolving neural systems that first
showed what open-ended machine intelligence looks like on the BEAM.
[Spartan](https://github.com/CorticalComputer/Spartan) is his architecture for a
persistent, self-authoring agent, and it is a quietly brilliant piece of design.

- **The decoupled Soul and suit** (`genesis_core.py`): a durable identity
  (Charter, Lessons, memory), cleanly separated from the swappable runtime that
  assembles context, runs the loop, and holds the tools. One Soul can put on a
  different suit and still be itself. This single idea is what makes a BEAM port
  possible at all; we build a new suit for a Soul that stays Gene's.
- **The four-layer context** (genesis, Soul, history, frontier), with a live HUD:
  a genuinely thoughtful answer to *what a mind holds in mind*.
- **Self-authorship**: a mind that amends its own charter, records its own
  lessons, keeps its own journal. Agency as a first-class mechanism, not a prompt
  trick.
- **The deeper cognition**: the Sleep Cycle and CMO consolidation, A-Mem
  Zettelkasten memory, MINDfulness (draft-then-verify self-audit), self-alerts.
  These are the parts we most admire, and the parts we are still porting.

Honesty about where the port stands: Gene's **foundation** (decoupled identity,
event-sourced Soul, four-layer context, self-authorship, reactive cognition,
provider resilience) is carried over and running. His deeper **cognitive** layers
(memory consolidation, the linked long-term memory, self-audit, self-alerts) are
his Phases 2 to 4, and they are still ahead of us. Where hecate-spartan adds
something of its own (mesh-native identity and UCAN, an event-sourced Soul, a
provider carousel, in-process delivery), it improves the *suit*; the cognition is
Gene's, carried faithfully and gratefully.

The lineage closes a circle: DXNN was neuroevolution on Erlang, and Gene's mind
now thinks natively on the BEAM again. Our own neuroevolution work,
[`faber-tweann`](https://codeberg.org/rgfaber/faber-tweann), descends directly
from DXNN.

Gene has been generous in person too, with his time, his code, and his guidance,
and the collaboration is ongoing. Thank you, Gene.

## License

Apache-2.0. See [LICENSE](LICENSE).
