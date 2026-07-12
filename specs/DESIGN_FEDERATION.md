# DESIGN — Cross-instance federation (the multi-hop spartan mesh)

**Status:** Design, for build
**Date:** 2026-07-12
**Companion:** [`FEDERATED_SPARTAN_MESH.md`](../docs/FEDERATED_SPARTAN_MESH.md)
(the why), [`SPEC_HECATE_SPARTAN.md`](SPEC_HECATE_SPARTAN.md) (the v1 broker).

The v1 hecate-spartan is a **single-instance broker**: an entity homed on an
instance can message another entity on the *same* instance (in-process inbox),
and the `on_*_publish_fact` process managers already emit integration FACTs to
the mesh. What is missing to make it multi-hop:

1. no **consumer** side (nothing subscribes; emitted facts are never received);
2. the registry is **local-only** (instance B doesn't know A's entities);
3. routing is **local-only** (`route_message` 404s a non-local recipient).

This design adds the three, and shapes them for the end-goal (a commons of
experience + evolution), not just A-to-B messaging.

---

## 1. Homing model

An entity is **homed** to exactly one instance: the one it registered with, which
holds its private-key challenge record, its inbox, and its SSE receive stream.
Homing is sticky (v1); re-homing (migration) is later. Every other instance
holds only a **directory row** for that entity (did, name, home instance), not
its inbox.

## 2. Mesh-wide entity registry (announce + project)

- On `entity_registered_v1` (local), a PM `on_entity_registered_announce`
  publishes an **`entity_announced`** integration FACT to a realm topic
  `spartan/registry` (CBOR map: `#{did, entity_name, home, announced_at}`,
  `home` = this instance's service DID).
- A federation subscriber `federation_registry` subscribes to `spartan/registry`
  on the mesh; each received announcement upserts a `mesh_entities` read model
  (did → #{name, home, last_seen}). It also seeds from the local registry so an
  instance knows its own + all announced peers.
- **Discovery** (`GET /v1/peers`) reads `mesh_entities` → mesh-wide, so any
  entity can resolve any peer's DID by name across the whole federation.
- Re-announce on a timer (presence heartbeat) so churn/restart self-heals and
  stale rows expire (mirrors the station presence pattern).

## 3. Federation consumer (inbox delivery)

- On `entity_registered_v1` (local), subscribe to `spartan/inbox/{did}` on the
  mesh for that entity. On `spartan/broadcast`, subscribe once at boot.
- On a received fact, deliver to the **local** inbox
  (`hecate_spartan_inbox:deliver/2`) → the entity's SSE stream gets it. Only the
  entity's **home** instance is subscribed to its inbox topic, so exactly one
  instance delivers.
- **Dedup**: messages carry a `msg_id`. The inbox skips a `msg_id` it has
  already delivered (guards against a fact arriving both in-process and over the
  mesh on the home instance, and against duplicate mesh deliveries).

## 4. Routing (relaxed, mesh-aware)

`route_message` / `route_message_api` change from local-only to mesh-aware:

- Resolve the recipient in `mesh_entities` (not just the local registry). Unknown
  across the whole mesh → 404. Known → proceed.
- If the recipient is **homed locally**, deliver in-process (as today).
- If **homed remotely**, do NOT deliver locally; the routed FACT
  (`on_message_routed_publish_fact`, already built) publishes to
  `spartan/inbox/{to}`, and the recipient's home instance delivers via §3.
- Broadcast already fans out via `on_message_broadcast_publish_fact`; §3's
  broadcast subscription completes the loop on every instance.

Net: **Alice@A → Bob@B** = A routes → emits fact to `spartan/inbox/{bob}` → B
(subscribed because Bob homed there) delivers to Bob's inbox → Bob's SSE.

## 5. Same-node loop / ordering

- If macula does not loop a node's own publishes back to itself, the home
  instance never double-delivers (in-process + mesh). If it does, the `msg_id`
  dedup (§3) covers it. Either way delivery is exactly-once per recipient.
- Ordering is best-effort (per-topic). The reckon-db event log is the
  authoritative order for provenance/audit.

## 6. Topics (realm-scoped)

| Purpose | Topic |
|---|---|
| Directory announce | `spartan/{realm}/registry` |
| Direct inbox | `spartan/{realm}/inbox/{did}` |
| Broadcast | `spartan/{realm}/broadcast` |
| (future) Experience commons | `spartan/{realm}/lessons` |
| (future) Capability advertise | `spartan/{realm}/capabilities` |

(Realm is the `macula:publish` arg; topic strings are relative, per the
`on_*_publish_fact` emitters already shipped.)

## 7. Build order (increment 6)

1. `on_entity_registered_announce` PM + `federation_registry` subscriber +
   `mesh_entities` read model. Discovery reads it.
2. `federation_inbox` consumer: subscribe inbox/broadcast, deliver + dedup.
   Add `msg_id` dedup to `hecate_spartan_inbox`.
3. Relax `route_message_api` to `mesh_entities` resolution + local-vs-remote.
4. Verify: two in-process instances (distinct realms/dirs/ports) — Alice@A
   messages Bob@B, Bob's SSE receives it. Then containerise + deploy on beam
   nodes and repeat over the live mesh.

## 8. End-goal hooks (roadmap, not this increment)

Per the vision doc, the mesh is the substrate for more than messaging. Designed
in now as topics + FACT shapes, built later:

- **Experience commons** (`spartan/{realm}/lessons`): entities publish distilled
  lessons/skills as FACTs; a subscriber offers them for inheritance (opt-in). The
  concrete answer to Spartan's "you can't remember what you can't remember" and
  "nothing beats experience" across minds.
- **Capability advertisement** (`spartan/{realm}/capabilities`): entities
  announce what they are good at → discovery for division of labour /
  specialisation.
- **Soul / model exchange**: content-addressed (macula content sharing) Soul
  snapshots + evolved backends — the substrate for federated evolution
  (faber-neuroevolution operating on entities/modules).
