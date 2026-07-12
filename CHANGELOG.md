# Changelog

All notable changes to hecate-spartan are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/); versions follow SemVer.

## [Unreleased]

### Added
- **Self-sovereign identity decided** (Ed25519 + UCAN) and implemented:
  `hecate_spartan_identity` owns the service issuer keypair (load-or-generate,
  raw keys, 0600), derives the service DID, mints per-entity UCANs scoped to
  realm topics, and verifies presented UCANs — all on the macula-native NIFs
  (`macula_crypto_nif` / `macula_ucan_nif`).
- **`register_entity` write-side slice**: command, event, handler, aggregate,
  and state (evoq). Proof-of-possession is an ingress concern; the event never
  stores the signature.
- **Entity registry read model** (`hecate_spartan_entities`, ETS) + its
  projection (`entity_registered_v1_to_entities`), wired to the evoq
  subscription. Discovery queries: `get/1`, `all/0`, `count/0`.
- **Ingress** (`hecate_spartan_ingress` + `register_entity_api`): `POST
  /v1/register` — verifies the entity's signature proof, dispatches
  register_entity, returns a minted UCAN. Also serves `/health` on the
  loopback port (hecate_om ships the handler but starts no listener, so the
  container HEALTHCHECK was dead until now).
- Uses the current evoq 1.23 command path (`evoq_command:new/5` +
  `evoq_command_router:dispatch/2`); the older `evoq_dispatcher` reference was
  removed upstream.
- **Verified end-to-end**: booting the service and driving `POST /v1/register`
  over HTTP runs the full path (sig → dispatch → reckon_db event → projection
  → registry) and returns a valid UCAN; forged signatures get 401; `/health`
  returns 200. 24 EUnit tests green.

- **Messaging: `route_message` + inbox + SSE receive.**
  - `hecate_spartan_inbox` — per-entity in-process delivery: push to a live
    receiver, else queue backlog; subscribers monitored for cleanup.
  - `hecate_spartan_auth` — UCAN bearer authentication + capability checks
    (`msg/send`, `msg/recv`) for the messaging endpoints.
  - `route_message` slice (command, event, handler, `message_aggregate` /
    `message_state`, and the `message_routed_v1_to_inbox` projection).
  - `POST /v1/send` (sender = UCAN audience; recipient must be registered) and
    `GET /v1/receive` (SSE stream: backlog flush + live push + keepalive).
- **Verified end-to-end**: two entities register; A `POST /v1/send` to B;
  B receives the message live over its SSE `/v1/receive` connection with the
  correct body + sender; unauthenticated send → 401. 31 EUnit tests green.

- **Broadcast: `broadcast_message` slice.** Command, event, handler,
  `broadcast_aggregate` (reuses `message_state`), and the
  `message_broadcast_v1_to_inboxes` projection (fan-out to every registered
  entity's inbox except the sender). `POST /v1/broadcast`.
- **Content: `share_artifact`.** `POST /v1/artifact` (content/share cap → macula
  content → hash) and `GET /v1/artifact/:hash` (hash → bytes), over the Macula
  content-sharing primitive. Degrades to `503` when no mesh client is attached.
- **Verified end-to-end**: A broadcasts; B and C both receive it live over SSE
  with the broadcast flag; authenticated artifact POST offline → 503,
  unauthenticated → 401. 39 EUnit tests green.

- **Federation emitters** (`on_message_routed_publish_fact`,
  `on_message_broadcast_publish_fact`): process managers that publish an
  integration FACT (a CBOR map, not a domain-event bridge) to the realm inbox /
  broadcast topics via `macula:publish`. The seam that lets a peer instance
  deliver to entities homed there. Degrade safely while dark; delivery to
  locally-homed entities is unaffected. Forward-compat until cross-relay PubSub
  propagation is fixed upstream.

### Still to build (Phase 1a)
- The `macula_radio.py` client (SpartanRadio drop-in).
- Federation consumer side (subscribe to realm topics, deliver to locally-homed
  entities) — needs the multi-hop propagation fix + a two-instance test.
- Artifact content roundtrip needs a live station to verify (offline path only,
  for now).

## [0.1.0] - 2026-07-12

### Added
- Initial scaffold. Walking-skeleton L2 `hecate-om` service: boots, wires a
  reckon-db event store (`hecate_spartan_store`), registers a liveness
  `/health` probe, and declares its `identity_spec`.
- `hecate_spartan_service` implementing the `hecate_om_service` behaviour
  (six required callbacks + `store_id/0` / `data_dir/0` / `store_indexes/0`).
- Container packaging: `Containerfile`, `quadlet/hecate-spartan.container`,
  `manifest.json`, GitHub-mirror CI (`build-push.yml`).
- `plans/PLAN_HECATE_SPARTAN.md` — the desk-by-desk implementation roadmap
  (register / route / broadcast / share-artifact / discover / receive).

### Not yet
- No capabilities advertised and no vertical slices implemented — the desks
  land in Phase 1a. `capabilities/0` returns `[]` until each backing desk
  ships.
