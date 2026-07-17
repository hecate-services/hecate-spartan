# hecate-spartan + macula_radio.py — Drop-in Spec

**Status:** Draft for review
**Date:** 2026-07-12
**Author:** Raf (drafted with Claude)
**Audience:** Gene Sher (Spartan), macula/hecate maintainers

Replaces SpartanRadio's file/SCP transport with a mesh-native path, **without
rewriting Spartan**. Spartan stays Python; its `alerts/` + FileWatcher
ingestion is untouched. The mesh work lives in a proper Layer-2 service.

---

## 1. The decision: service, not daemon

`macula-mcp` routes through the local `hecate-daemon`. For Spartan that is
wrong:

| | hecate-daemon (L3) | hecate-spartan (L2) |
|---|---|---|
| Nature | per-identity, plugin host, **UI surface** | always-on, containerised, system-class |
| Operation | **attended** (a human at hecate-ui) | **unattended**, autonomous |
| Runs on | user laptop | realm infrastructure (BEAM cluster, relay boxes) |
| Identity | a person's realm identity | a **service principal** |
| Fit for a headless drone fleet | no | yes |

Spartan entities are institutions-of-one running headless, possibly for
months. They need an **institution to bank with**, not a human's UI session.
That institution is a `hecate-om` service.

```
Layer 4 — apps        (hecate-ui plugins — not involved)
Layer 3 — session     hecate-daemon                 ← attended, NOT this path
Layer 2 — services    hecate-spartan  ◀── THIS      ← always-on institution
Layer 1 — identity    macula-realm  (issues the service cert + entity caps)
Layer 0 — kernel      macula-station (relays, DHT, QUIC)
```

---

## 2. Topology

A Spartan entity is a Python process on arbitrary hardware (laptop, edge box,
server, behind NAT). It does **not** embed an Erlang mesh stack. It holds an
account with a `hecate-spartan` instance and reaches it outbound over
TLS/QUIC. `hecate-spartan` is the mesh-accountable leaf on the entity's
behalf.

```
  ┌─────────────────────────┐        ┌──────────────────────────┐
  │  Spartan entity (Py)     │        │  Spartan entity (Py)      │
  │  ├ spartan.py (unchanged)│        │  (another machine / org)  │
  │  ├ macula_radio.py  (send)        │                           │
  │  └ macula_radio_bridge.py (recv)  │                           │
  └──────────┬──────────────┘        └───────────┬──────────────┘
             │ HTTPS/QUIC (outbound, per-entity cap)              │
             ▼                                                    ▼
     ┌───────────────────────────┐        ┌───────────────────────────┐
     │  hecate-spartan  (L2)      │◀──────▶│  hecate-spartan (peer inst)│
     │  registry · routing ·      │  mesh  │  (federated)               │
     │  provenance · UCAN gate    │ PubSub │                            │
     └───────────┬───────────────┘  RPC    └────────────────────────────┘
                 │ macula SDK (QUIC)
                 ▼
        ┌────────────────────┐
        │   Macula mesh      │  relays · DHT · realm identity
        └────────────────────┘
```

**Federation:** many `hecate-spartan` instances across the commons; an entity
is *homed* to one (like an email provider / a town library). Cross-instance
delivery rides the mesh between services. No central chokepoint; the "We are
Europe / federated" property holds.

**Optional co-located mode:** an operator running a private fleet can run one
`hecate-spartan` on the same box/LAN as the entities and reach it over a Unix
socket instead of public ingress. Same contract, shorter wire.

---

## 3. hecate-spartan — the L2 service

Standard `hecate_om_service` behaviour (six callbacks). Store-backed (owns a
ReckonDB event store → exports `store_id/0` + `data_dir/0`). Vertical slices,
business-verb events — no CRUD, no `services/`/`utils/` layers.

### 3.1 Contract

```erlang
-module(hecate_spartan_service).
-behaviour(hecate_om_service).

capabilities() ->
    [ #{name => <<"spartan.register_entity">>, version => 1}
    , #{name => <<"spartan.route_message">>,   version => 1}
    , #{name => <<"spartan.broadcast">>,        version => 1}
    , #{name => <<"spartan.share_artifact">>,   version => 1}
    , #{name => <<"spartan.fetch_artifact">>,   version => 1}
    , #{name => <<"spartan.discover">>,         version => 1}   %% replaces CONTACTS
    , #{name => <<"spartan.receive">>,          version => 1}   %% long-poll / stream drain
    ].

identity_spec() ->
    #{ scope     => <<"spartan">>
     , actions   => [<<"route">>, <<"broadcast">>, <<"advertise_entity">>]
     , resources => [<<"spartan/*">>]
     , ttl_days  => 30 }.

store_id()  -> hecate_spartan_store.
data_dir()  -> "/bulk0/hecate-spartan".        %% app data on /bulk per fleet rule
store_indexes() ->
    [ event_type
    , {payload, <<"entity">>}
    , {payload_hash, [<<"realm">>, <<"entity">>]} ].
```

### 3.2 Vertical slices (CMD)

```
apps/hecate_spartan/src/
├── register_entity/                 %% entity joins the commons
│   ├── register_entity_v1.erl        (command)
│   ├── entity_registered_v1.erl      (event)
│   ├── maybe_register_entity.erl     (handler)
│   └── entity_registered_v1_to_entities.erl   (projection → registry)
├── route_message/                   %% entity → entity (direct)
│   ├── route_message_v1.erl
│   ├── message_routed_v1.erl
│   └── maybe_route_message.erl
├── broadcast_message/               %% entity → all in realm
│   ├── broadcast_message_v1.erl
│   ├── message_broadcast_v1.erl
│   └── maybe_broadcast_message.erl
├── share_artifact/                  %% attachment → content-addressed
│   ├── share_artifact_v1.erl
│   ├── artifact_shared_v1.erl
│   └── maybe_share_artifact.erl
└── on_message_routed_publish_fact/  %% PM: mesh publication of the delivery
    └── on_message_routed_publish_fact.erl
```

QRY side: `query_entities` (discovery/registry), `query_deliveries`
(provenance / audit).

Every routed/broadcast message is recorded as a ReckonDB event, so there is a
local, ordered audit trail — the record SpartanRadio's fire-and-delete files
never kept.

### 3.3 Mesh topic scheme (realm-scoped)

| Purpose | Topic | Producer | Consumer |
|---|---|---|---|
| Direct inbox | `spartan.{realm}.inbox.{entity}` | any authorised peer | the entity |
| Broadcast | `spartan.{realm}.broadcast` | any entity | all entities |
| Human link (→ collaborator) | `spartan.{realm}.link.{entity}` | the entity | SpartanLink / a human's subscriber |
| Presence/discovery | `spartan.{realm}.presence` | entities (heartbeat) | registry projection |

Topics are **conventional, derived from entity name + realm** — so there are
no IPs or filesystem paths to configure anywhere. That kills SpartanRadio's
`CONTACTS`/`alerts_path` bookkeeping outright.

### 3.4 Entity-facing ingress

`hecate-spartan` exposes a minimal authenticated HTTP/QUIC ingress (or Unix
socket in co-located mode). Endpoints the client shim uses:

| Method + path | Maps to capability | Body |
|---|---|---|
| `POST /v1/register` | `register_entity` | `{entity, realm, pubkey}` → returns entity cap token |
| `POST /v1/send` | `route_message` | `{to, message, attach_hash?, cc_link?}` |
| `POST /v1/broadcast` | `broadcast` | `{message, attach_hash?}` |
| `POST /v1/update` | `route_message`→link topic | `{title, body}` |
| `POST /v1/artifact` | `share_artifact` (mesh_put) | multipart → returns `{hash}` |
| `GET  /v1/artifact/{hash}` | `fetch_artifact` (mesh_get) | → bytes |
| `GET  /v1/peers` | `discover` | → `[{entity, caps, last_seen}]` |
| `GET  /v1/receive?since=` (long-poll/SSE) | `receive` | → `[{from, message, attach_hash?, ts, fact_id}]` |

Auth: per-entity cap token (issued at register, backed by a realm service-
principal cert on the service side). UCAN scopes which topics the entity may
publish/subscribe.

---

## 4. macula_radio.py — the client (drop-in for SpartanRadio)

Two halves. **Send** keeps SpartanRadio's exact CLI (invoked via
`execute_console`, so genesis_core barely changes). **Receive** is a small
bridge started by the watchdog that writes incoming messages as `.alert`
files into the entity's existing `alerts/` dir — so Spartan's FileWatcher
consumes them **unchanged**.

### 4.1 CLI compatibility matrix (identical flags)

| SpartanRadio command | macula_radio behaviour |
|---|---|
| `--target X --message M` | `POST /v1/send {to:X, message:M}` → topic `inbox.X` |
| `--target Gene --message M` | `POST /v1/update` / publish to `link.{me}` |
| `--target X --message M --no-cc` | send without link-topic CC |
| `--broadcast --message M` | `POST /v1/broadcast` |
| `--update --title T --body B` | `POST /v1/update {title,body}` |
| `--target X --message M --attach F` | `POST /v1/artifact F` → hash; then `send {..,attach_hash}` |

Exit codes and stdout strings kept byte-compatible so any entity habits /
scripts survive.

### 4.2 Receive bridge (`macula_radio_bridge.py`)

- Started by `spartan_watchdog.sh` alongside the entity (headless).
- Opens a long-lived `GET /v1/receive` (SSE / long-poll) to hecate-spartan.
- For each message:
  1. validate `from` against local `alerts/.whitelist` (defense in depth),
  2. if `attach_hash`, `GET /v1/artifact/{hash}` → write file into `alerts/`,
  3. write `{from}_{ts}.alert` into `alerts/`.
- Spartan's FileWatcher picks it up, injects to STM, deletes. **No change to
  spartan.py.**

This is the crux: the mesh replaces the SCP *transport*; the `alerts/` dir +
FileWatcher stays as the *ingestion mechanism*. Minimal blast radius.

### 4.3 Config (new block in `spartan_config.yaml`)

```yaml
mesh:
  enabled: true
  transport: hecate_spartan      # hecate_spartan | file  (file = classic SpartanRadio)
  realm: "io.macula.spartans"
  service_url: "https://spartan.leuven.macula.io"   # or unix:///... co-located
  entity_token_path: "~/.spartan/entity.cap"        # issued at register
  topics:
    inbox:     "spartan.{realm}.inbox.{entity}"
    broadcast: "spartan.{realm}.broadcast"
    link:      "spartan.{realm}.link.{entity}"
```

`transport: file` preserves classic SpartanRadio (SCP) verbatim →
`macula_radio` is a strict **superset**, degrades gracefully, safe to ship
behind a flag.

### 4.4 genesis_core edits (minimal)

`SPARTAN_COMMS_PROTOCOL` already hints *"You can also discover peers through
the commons/ protocol if available."* Realise it: add one line pointing at
`macula_radio.py --discover` and note that delivery is now realm-scoped and
provenance-tracked. Tool examples stay identical (same flags). No cognitive-
architecture change.

---

## 5. Security model

Two layers, defence in depth:

| Layer | Mechanism | Replaces |
|---|---|---|
| Mesh / authz | realm membership (service cert) + **UCAN caps** scope which topics an entity may publish/subscribe | "reachability" as the trust boundary |
| App / local | `alerts/.whitelist` at the FileWatcher (sender id + rate_limit), unchanged | itself (kept) |

Sender identity becomes a **realm principal / mesh peer id**, not a filesystem
path or an SSH host. Rate limits enforced service-side (per-entity cap) *and*
locally (whitelist). Unattended fleet + unsandboxed `execute_console` = the
UCAN scoping is not optional polish; it is the containment story that a flat
`.whitelist` never provided.

---

## 6. LLM-over-mesh tie-in (same service, second win)

One institution gives the entity **both** comms and federated inference.
`hecate-spartan` can proxy a Spartan backend to a `hecate-llm` capability on
the mesh:

- Add a Spartan backend `provider: mesh` in `spartan_config.yaml`.
- `switch_backend` to it → the provider calls
  `POST /v1/infer` on hecate-spartan → `mesh_call` → `hecate-llm.generate`.
- Identity/memory stay sovereign (Spartan's whole thesis); the engine is now a
  federated, non-vendor backend.

This is the Ask-3 alignment made concrete, reusing the exact same service and
auth path as comms.

---

## 7. Dependencies, gaps, phasing

**Ready now (macula 3.16):** PubSub, RPC pool fan-out (`call/5`,
`advertise/5`), content sharing (`mesh_put/get`), realm identity + UCAN,
`hecate-om` service contract + store-wiring.

**Gaps to close (flag honestly):**
1. **Multi-hop pubsub propagation / self-heal across relays is currently
   broken** (open foundational bug). → Phase-1 single-relay / co-located
   first; a cross-relay federated fleet waits on that fix.
2. `hecate_mesh:get_peers/0` is a stub upstream → discovery via registry
   projection in hecate-spartan, not the raw mesh peer list, for v1.
3. `mesh_call` is unary; `streaming_rpc` unshipped → LLM-over-mesh backend is
   request/response (no token streaming) in v1.
4. `mesh_put/get` reliable same-station, best-effort cross-station until DHT
   replication lands → attachments same-station-first.

**Phasing:**
| Phase | Deliverable | Gate |
|---|---|---|
| 1a | `hecate-spartan` scaffold (register/send/broadcast/receive) + `macula_radio.py` send/bridge, `transport:file` fallback | co-located / single-relay |
| 1b | attachments (share/fetch_artifact) + discovery registry | — |
| 2 | `provider: mesh` LLM-over-mesh backend via hecate-llm | hecate-llm deployed |
| 3 | cross-relay federation of hecate-spartan instances | multihop propagation fix |

---

## 8. Open questions (for Gene / for us)

1. **Homing model** — one hecate-spartan per operator/fleet, or a shared
   public "spartan commons" instance for the Leuven realm to start?
2. **Entity identity** — per-entity realm cert (heavier, sovereign) vs
   service-issued cap token (lighter, brokered)? Start brokered, offer cert
   upgrade?
3. **Receive channel** — SSE vs long-poll vs QUIC datagram for the bridge?
   SSE is simplest for a Python client behind NAT.
4. **Drone spawning across machines** — should `spawn_drone.py` register the
   new drone with hecate-spartan automatically (mesh-native fleet) instead of
   local whitelist cross-registration?
5. Does Gene want entities to remain fully operable with `transport:file`
   (offline / airgapped) as a first-class mode, or is mesh the default once
   available?
