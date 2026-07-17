# PLAN: rip event-sourcing out of hecate-spartan (4a)

**Status: stage 1 DONE, stage 2 SPECIFIED (not started)**
**Date: 2026-07-17**

Goal: a store-free, mesh-native mind. Soul (files) + Memory (files/faculty) +
Mesh (direct publishes) + registries (ETS). No reckon-db, no evoq, no ES.

## Done — stage 1 (commit 2f4880f)
Retired the event-sourced chronicle into the STM faculty. Deleted `record_turn/`
+ `chronicle_aggregate`; `spartan_mind` reads recent history from
`memory:recent_stm` and seeds lexical recall from persisted STM.

## Stage 2 — the five mesh capabilities + store teardown

Pattern per capability: today it is command → aggregate → event → two projections
(a read-model + an `on_*` PM that does `macula:publish`). Collapse to:
**the handler (`maybe_*:dispatch/1`) directly does the ETS/inbox effect AND
`macula:publish`.** Callers keep building the `_v1` command and calling
`dispatch/1` (keep the `_v1` command + event modules dormant to minimise churn;
delete the aggregate, the read-model projection, and the `on_*` PM). Delete the
ES machinery; do NOT change caller signatures.

**INVARIANT: preserve every published-fact shape byte-for-byte.** The realm
subscriber routes by topic and reads specific fields; peer federation matches the
`type` field. Keep `type` on every fact. Agora reference — the exact realm
contract is in section "Realm contract" below.

### Capability 1: publish_to_agora  (DONE-able first; realm-critical)
- Callers of `maybe_publish_to_agora:dispatch`: `publish_to_agora_api.erl:49`,
  `mind_tools.erl:135` (speak), `convene_committee/committee.erl:242`,
  `federation_ask.erl:105`.
- Effects: `hecate_spartan_agora:post(hecate_spartan_agora:row(Data))` (feed ETS)
  + deliver to local minds (inbox fanout, tag `agora=>true`, all entities except
  author) + publish fact.
- **Fact (topic `spartan/agora`)** — preserve:
  ```
  #{type => agora_post, post_id, from, body, in_reply_to, posted_at,
    home => safe_service_did(), locale => hecate_spartan_service:locale()}
  ```
- **Relocate `fact/1`** into `maybe_publish_to_agora` (export it); update
  `federation_agora.erl:129` to call `maybe_publish_to_agora:fact/1`.
- Delete: `agora_aggregate`, `agora_post_published_v1_to_feed` (projection),
  `on_agora_post_published_publish_fact` (PM). Keep `publish_to_agora_v1`,
  `agora_post_published_v1` (dormant; its `replay/0` returns [] with store dark,
  so `hecate_spartan_agora:rebuild` and `federation_agora:recent_own` degrade to
  empty — feed refills from peers).

### Capability 2: route_message
- Caller: `route_message_api.erl:49`. Recipient pre-checked via
  `hecate_spartan_mesh_entities:get/1`.
- Effect: deliver in-process only if recipient homed here
  (`hecate_spartan_entities:get/1`); `Msg = #{msg_id, from, body, sent_at}`.
- **Fact (topic `spartan/inbox/<To>`)**:
  ```
  #{type => spartan_message, msg_id, from, to, body, sent_at}
  ```
- Delete: `message_aggregate`, `message_routed_v1_to_inbox`,
  `on_message_routed_publish_fact`. (Do NOT touch `route_message/receive_api.erl`
  — pure inbox reader.)

### Capability 3: broadcast_message
- Caller: `broadcast_message_api.erl:38`.
- Effect: fan out `Msg = #{msg_id, from, body, sent_at, broadcast => true}` to all
  entities except sender.
- **Fact (topic `spartan/broadcast`)**:
  ```
  #{type => spartan_broadcast, msg_id, from, body, sent_at}
  ```
- Delete: `broadcast_aggregate`, `message_broadcast_v1_to_inboxes`,
  `on_message_broadcast_publish_fact`. Update `test/maybe_broadcast_message_tests`.

### Capability 4: report_activity  (simplest — no ETS)
- Caller: `report_activity_api.erl:40`. Keep the `?KINDS` whitelist
  `[action,thought,speech,model,alert,cycle]` + `unknown_kind` error.
- **Fact (topic `spartan/activity`)**:
  ```
  #{type => spartan_activity, activity_id, did, kind, summary,
    at, locale => hecate_spartan_service:locale()}
  ```
- Delete: `activity_aggregate`, `on_activity_reported_publish_fact`.

### Capability 5: register_entity  (richest — do last of the five)
- Callers: `register_entity_api.erl:38` (must still mint a UCAN on the
  already-registered path), `spartan_mind.erl:378` (register_self on every boot).
- Idempotency guard (`?ENTITY_REGISTERED` bit) must move into the direct handler
  so a second register does not re-announce (still returns an
  already-registered-equivalent so the API refreshes the UCAN).
- Two ETS upserts (preserve both): `hecate_spartan_entities` (`entities`, via
  `row/1`) and `hecate_spartan_mesh_entities` (`mesh_entities`).
- **Relocate `row/1`** (entity_registered_v1_to_entities) — called by
  `hecate_spartan_entities:63`, `hecate_spartan_mesh_entities:102`.
- **Relocate `fact/2`** (on_entity_registered_announce) — called by
  `federation_registry.erl:114`.
- **Fact (topic `spartan/registry`)**:
  ```
  #{type => entity_announced, did, entity_name, home, locale,
    online => safe_online(Did), registered_at, announced_at}
  ```
- Delete: `entity_aggregate`, `entity_state`, `hecate_spartan_entity.hrl`,
  `entity_registered_v1_to_entities`, `on_entity_registered_announce`. Rework
  `test/entity_registry_tests`, `test/registry_rebuild_tests`.

### Supervisor
`hecate_spartan_sup.erl`: drop every `projection(...)` child (the read-model
projections + the `on_*` PMs) and the `projection/1` helper. Keep all `worker`
children (identity, entities, mesh_entities, inbox, agora, federation_*, ingress)
and the two `mind_sup` children. **Delete a capability's projection children in
the same commit you delete its projection modules, or the sup crashes at boot.**

### Store teardown (LAST — only after all five are converted)
`hecate_spartan_service.erl`: **remove `store_id/0` and `store_indexes/0`; KEEP
`data_dir/0`** (the minds' souls/keys need it). `hecate_om:maybe_wire_store`
checks `function_exported(store_id, 0)` — with it gone, reckon-db never boots.
Drop the `event_store_id` env from `hecate_spartan.app.src`. `hecate_om` dep stays
(mesh client). Update rebar.config/app.src comments that mention reckon-db.

### Realm contract (must match exactly)
`macula-realm .../spartan_agora/spartan_agora_subscriber.ex` subscribes:
`spartan/registry`, `spartan/broadcast`, `spartan/agora`, `spartan/activity`,
and per-entity `spartan/inbox/<did>`. Fields read:
- registry: `did`, `entity_name`, `locale`, `home`, `online` (==true),
  `registered_at`. Needs `did` AND `entity_name`.
- agora: `post_id` (or `msg_id`), `body`, `from`, `to`, `in_reply_to`, `locale`,
  `posted_at` (or `sent_at`). Needs id AND body.
- broadcast: `msg_id`, `body`, `from`, `sent_at`.
- inbox: `msg_id`, `body`, `from`, `to`, `sent_at`.
- activity: `activity_id`, `summary`, `did`, `kind`. Needs activity_id AND summary.

### Semantic change (benign for us)
With reckon-db gone the registries/feed do not rebuild from a local log on
restart; they refill from live re-registration (minds re-register on boot) + peer
mesh announcements (~60s federation timers). Mesh is the source of truth. This is
the correct mesh-native model, not a loss.

### Execution order
1. agora (verify realm still shows posts).
2. route_message, broadcast, activity (same pattern).
3. register_entity (idempotency guard, two ETS, two relocations).
4. sup: all projection children gone.
5. store teardown (remove store_id) → reckon-db no longer boots.
6. compile + eunit + elvis + realm-contract check + fleet verify.
Each step is an atomic, always-green, committed increment.
