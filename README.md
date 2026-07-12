# hecate-spartan

**The federated mesh commons for [Spartan](https://github.com/CorticalComputer/Spartan)
autonomous agents.**

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

## License

Apache-2.0. See [LICENSE](LICENSE).
