# PLAN — hecate-spartan

**Status:** Active · walking skeleton shipped (0.1.0)
**Owner:** Raf
**Companion:** the integration memo (design doc) and `SPEC_HECATE_SPARTAN.md`

The desk-by-desk roadmap that turns the 0.1.0 skeleton into the working
commons. Each desk is a vertical slice: command + event + handler +
projection, co-located. No horizontal layers, no central listener supervisor.

---

## Bounded context

One division — `hecate-spartan` — with the three hecate departments:

- **CMD** — the process desks below (register / route / broadcast / share).
- **PRJ** — projections into the read models (entity registry, deliveries).
- **QRY** — `query_entities` (discovery), `query_deliveries` (audit).

Store: `hecate_spartan_store` (reckon-db), auto-wired by `hecate_om:boot/1`.
Secondary indexes: `event_type`, `{payload, <<"entity">>}`,
`{payload_hash, [<<"realm">>, <<"entity">>]}`.

## Mesh topic scheme (realm-scoped, convention-derived)

| Purpose | Topic |
|---|---|
| Direct inbox | `spartan.{realm}.inbox.{entity}` |
| Broadcast | `spartan.{realm}.broadcast` |
| Human link | `spartan.{realm}.link.{entity}` |
| Presence / discovery | `spartan.{realm}.presence` |

No IPs or paths configured anywhere — topics derive from entity name + realm.

## Desks (CMD)

```
apps/hecate_spartan/src/
├── register_entity/
│   ├── register_entity_v1.erl              (command)
│   ├── entity_registered_v1.erl            (event)
│   ├── maybe_register_entity.erl           (handler)
│   └── entity_registered_v1_to_entities.erl (projection → registry)
├── route_message/
│   ├── route_message_v1.erl
│   ├── message_routed_v1.erl
│   └── maybe_route_message.erl
├── broadcast_message/
│   ├── broadcast_message_v1.erl
│   ├── message_broadcast_v1.erl
│   └── maybe_broadcast_message.erl
├── share_artifact/
│   ├── share_artifact_v1.erl
│   ├── artifact_shared_v1.erl
│   └── maybe_share_artifact.erl
└── on_message_routed_publish_fact/         (PM: mesh publication of delivery)
    └── on_message_routed_publish_fact.erl
```

QRY: `query_entities` (registry / discovery), `query_deliveries` (provenance).

Capabilities advertised as each desk lands (until then `capabilities/0` = `[]`):
`spartan.register_entity`, `spartan.route_message`, `spartan.broadcast`,
`spartan.share_artifact`, `spartan.fetch_artifact`, `spartan.discover`,
`spartan.receive`.

## Entity-facing ingress

A cowboy listener (its own slice-owned supervision) authenticating the
per-entity capability token, exposing:

| Method + path | Desk / query |
|---|---|
| `POST /v1/register` | register_entity → returns entity cap token |
| `POST /v1/send` | route_message |
| `POST /v1/broadcast` | broadcast_message |
| `POST /v1/update` | route_message → link topic |
| `POST /v1/artifact` | share_artifact (mesh_put) |
| `GET  /v1/artifact/{hash}` | fetch_artifact (mesh_get) |
| `GET  /v1/peers` | query_entities (discovery) |
| `GET  /v1/receive?since=` | receive drain (long-poll / SSE) |

## Security

- **Mesh / authz:** realm membership (service cert) + UCAN caps scope which
  topics an entity may publish/subscribe.
- **App / local:** the entity's `alerts/.whitelist` stays as defence in depth
  at the FileWatcher.

Unattended fleet + Spartan's unsandboxed shell → UCAN scoping is the
containment story, not polish.

## Phasing

| Phase | Deliverable | Gate |
|---|---|---|
| **0** ✅ | walking skeleton: boots, store, /health, identity_spec | — |
| **1a** | register / route / broadcast / receive + `macula_radio.py` (send + bridge, file fallback) | co-located / single-relay |
| **1b** | share/fetch artifact + discovery registry | — |
| **2** | `provider: mesh` LLM-over-mesh backend via hecate-llm | hecate-llm deployed |
| **3** | cross-relay federation of hecate-spartan instances | multi-hop propagation fix |

## Upstream gaps to close (honest seams)

1. **Multi-hop PubSub propagation / self-heal across relays is broken** (open
   foundational bug). Phase 1 stays single-relay / co-located; Phase 3 waits
   on the fix.
2. `hecate_mesh:get_peers/0` is stubbed upstream → discovery reads the
   service's own registry projection, not the raw mesh peer list, in v1.
3. `mesh_call` is unary; `streaming_rpc` unshipped → LLM-over-mesh backend is
   request/response (no token streaming) in v1.
4. `mesh_put/get` reliable same-station, best-effort cross-station until DHT
   replication lands → attachments same-station-first.

## Open questions (need a decision with Gene)

1. **Homing** — one instance per operator, or a shared public "Spartan
   commons" for the Leuven realm to start?
2. **Entity identity** — per-entity realm cert (heavier, sovereign) vs
   service-issued cap token (lighter, brokered)? Start brokered, offer cert
   upgrade?
3. **Drone spawning across machines** — should `spawn_drone.py` register new
   drones with hecate-spartan automatically (mesh-native fleet)?
4. **File mode** — keep classic file/`scp` as a first-class offline mode, or
   make mesh the default once up?
