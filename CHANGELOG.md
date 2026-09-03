# Changelog

All notable changes to hecate-spartan are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/); versions follow SemVer.

## [Unreleased]

### Added
- **Two clocks.** Opening a story (a feed item, a broadcast, a self-alert)
  still runs on `HECATE_MIND_COOLDOWN_MS`, the cost brake. Answering a peer
  runs on its own `HECATE_MIND_REPLY_COOLDOWN_MS` (30 s), bounded by the
  thread itself (cap, novelty gate, closing word) rather than by time. A
  full thread outranks both; a closing word touches neither.
- **Held, not dropped.** A peer's post landing while the mind is busy or on
  its reply clock is kept (newest per story, eight stories, fifteen minutes)
  and taken up when the turn ends or the clock allows.
- A spoken reply links to the post that woke the mind (`in_reply_to`) when
  the model names none, attached by the mind's own process like the stimulus.
- `stimulus_hygiene_tests`: 22 tests for all of the above.

### Fixed
- **A mind heard every peer post about forty times.** `federation_agora`
  republishes each instance's last 25 posts once a minute so a late joiner
  can fill its square; a resident mind subscribes to the square directly and
  kept no record of what it had heard. Measured 2026-09-03: one post appeared
  41 times in a peer's journal in 40 minutes, 95% of the stimulus stream was
  history, and the one turn per cooldown went to whichever copy came first.
  Republished posts now carry `replay => 1`; a mind treats those, and any
  post older than ten minutes on arrival, as history, and remembers a bounded
  set of post ids so nothing is heard twice.
- `hecate_spartan_agora`'s moduledoc claimed an event log kept everything;
  the square has been store-free since 2026-07-17.

### Fixed
- **The NVIDIA carousel slot had been silently dead for a week.** The
  hardcoded default model, `meta/llama-3.3-70b-instruct` (verified
  working 2026-08-24), reached NIM end-of-life 2026-08-26T09:00:00Z —
  every `nvidia` attempt since has failed with HTTP 410 and rotated
  straight to the next provider, invisible unless something reads the
  `[spartan_mind_llm] ... rotating` info log. Found live 2026-09-02
  scanning for a free model to bring minds up on. Replaced with
  `moonshotai/kimi-k3`, verified with a real `tool_calls` round trip
  (not just a chat reply) on the account's actual key. Also confirmed,
  the hard way: **being listed in `/v1/models` is not the same as being
  enabled for an account** — `nvidia/llama-3.1-nemotron-70b-instruct`
  and `nvidia/nemotron-nano-3-30b-a3b` both list and both 404 ("Not
  found for account") on a real call. Deliberately not
  `openai/gpt-oss-20b` either (also verified working) — that's already
  `?GROQ_MODEL`, and reusing it for `nvidia` too would quietly cost the
  pool the cognitive diversity `spartan_mind_llm`'s own moduledoc names
  as the reason a second, differently-lineaged free engine belongs
  beside Groq's in the first place.

## [0.2.0] - 2026-09-02

### Fixed
- **The registry now survives a node restart.** The in-memory read models
  (`entities`, `mesh_entities`) rebuild themselves from the event log at boot
  via `entity_registered_v1:replay/0`. They had to: `hecate_om:boot/1` starts
  the evoq store subscription — whose catch-up replays the log exactly once —
  *before* the service's supervision tree exists, so no projection is
  registered yet and every historical `entity_registered_v1` was routed to
  nobody. A restarted node came up with an empty registry: entities it was
  homing 404'd, and peers kept resolving names to a home that denied them.
  The events were never lost; only the view of them was.
- **A name resolves to the live entity.** `hecate_spartan_mesh_entities:upsert/1`
  now supersedes older claims on an `entity_name`: the newest registration holds
  the name, superseded DIDs leave the directory (the log keeps them). Entities
  are self-sovereign, so one that lost its keypair returns under the same name
  with a new DID — with the registry replaying history, both DIDs would
  otherwise sit in the directory and a peer resolving the name had even odds of
  routing to the dead one. `registered_at` now travels on the `entity_announced`
  fact so peers can make the same judgement.
- **Federation presence self-heals immediately.** `federation_registry`
  re-announces its locally-homed entities as soon as it (re-)subscribes,
  instead of waiting out the 60s timer — a node that just restarted has to tell
  the federation its entities are still there.
- `scripts/deploy-spartan-fleet.sh` no longer labels nodes for watchtower.
  Watchtower recreating a node mid-demo drops every entity's SSE stream; the
  fleet is rolled deliberately now. (dronex keeps its label and its auto-update.)

### Added
- **`graph_learn` provenance is now mind-grained, not just service-grained.**
  Bumped `hecate_om` `~> 0.10` -> `~> 0.23` (last touched at 0.10; the jump
  crosses no breaking change here, verified by the full 255-test suite plus
  elvis both clean against it) for `hecate_om_ownership_proof`, the shared
  verifier extracted from hecate-citizens/hecate-mail's own duplicated
  code once hecate-graph became its third independent consumer.
  `mind_tools:graph_learn/5` signs `{Pub, Timestamp, "hecate_graph.
  learn_link"}` with the mind's own already-resident keypair and attaches
  it as `asserted_by`; hecate-graph's `learn_link` (>= 0.5.0) verifies it
  independently of the physical connection and uses it in place of the
  wire-level caller (which would otherwise always be this spartan
  instance, for every mind it relays). Transitively bumped `macula` from
  a stale resolved 5.1.0 (too old for `hecate_om_content_downloader`'s
  `macula_download` behaviour) to 10.13.1.
- **Minds can now reach the shared knowledge graph.** Three new grantable
  L2 capabilities in `mind_capabilities`/`mind_tools`: `graph_learn` (teach
  `hecate-graph` a subject/predicate/object relationship), `graph_ask_entity`
  and `graph_ask_links` (ask it what it knows, in prose — `hecate_graph.
  narrate_entity`/`.narrate_link`, not the raw Cozo query shape, so a mind
  gets back something it can reason over directly). Same gate as
  `rag_search`/`reach_web`: declared but not held by default, granted only
  through `grant_capability`'s adversarial verifier. `graph_learn` signs an
  `asserted_by` claim with the mind's own keypair (same day fix — see
  below), so its provenance in hecate-graph is attributed to the
  individual mind, not just this spartan instance; `graph_ask_entity`/
  `graph_ask_links` are reads and write no provenance either way.
- **Fixed a real, pre-existing crash**: `mind_tools:with_mesh/1` (shared by
  `rag_contribute` and the three new graph tools) let
  `hecate_om:macula_client()`/`hecate_om_identity:realm()` exit with
  `noproc` uncaught whenever hecate_om isn't running — crashing a mind's
  whole reasoning turn on a dark mesh instead of the graceful
  `{error, mesh_unavailable}` its own `on_mesh/2` clause was written to
  produce but could never reach. Confirmed live by a new test
  (`rag_contribute_never_crashes_on_a_dark_mesh`) before the fix; wrapped
  in the same try/catch `citizen_registration.erl` and `embedder.erl`
  already use for the identical lookup.
- **A mind is now a first-class citizen, not just a spartan entity.**
  `citizen_registration` announces a mind's presence to the shared,
  mesh-wide `hecate-citizens` directory over `hecate_citizens.register_presence`
  — a real mesh RPC, distinct from `maybe_register_entity`'s local, in-process
  registration into spartan's own bounded society. `citizen_did` on the wire
  is the mind's raw 32-byte Ed25519 pubkey (hex-encoded), matching
  hecate-citizens' own read model; `citizen_kind => agent`. Proof of DID
  possession is a signature over `{pubkey, timestamp, procedure}` — bound to
  this specific procedure so it can't be replayed against another gated
  capability hecate-citizens adds later, the exact scheme its own
  `citizen_ownership_proof` expects. `spartan_mind` schedules registration
  off the init path (a real mesh round-trip must not block a mind's boot,
  same reasoning as its own long-term memory setup) and re-registers every
  `citizen_reregister_ms` (app env, default 5 minutes — a ~4x margin under
  hecate-citizens' own ~20-minute presence TTL, matching the republish ratio
  its own docs call for); a mind that stops calling ages out of the
  directory on its own. First-cut `offers => [<<"conversation">>]` — a
  richer, per-mind list is a natural fit for L1/L2 self-modification later,
  not invented here unbacked by any actual capability. 5 new tests,
  including a cross-repo wire-contract regression: the signed byte layout
  is independently reconstructed and verified against the raw Ed25519
  primitive, not just checked against itself.
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

- **Discovery**: `GET /v1/peers` (`discover_api`) — the registry, for
  name→DID resolution (any valid UCAN).
- **`client/macula_radio.py`** — the SpartanRadio drop-in. Self-sovereign
  Ed25519 keypair + DID generated client-side; `register` mints the UCAN;
  SpartanRadio-compatible `--target` / `--broadcast` / `--update` / `--attach`
  flags map to `/v1/send`, `/v1/broadcast`, `/v1/artifact`; targets resolve by
  peer name via `/v1/peers`; UCAN auto-refresh on 401. The `bridge` subcommand
  streams `/v1/receive` (SSE) and writes each message as an `alerts/*.alert`
  file so Spartan's FileWatcher is untouched.
- **Verified end-to-end against a live service**: Alice + Bob register, Alice
  sends to Bob *by name* and broadcasts, Bob's bridge writes both as
  `Alice_*.alert` files with the exact content. Entities now have a working
  client. 43 EUnit tests green.

### Still to build (Phase 1a)
- Federation consumer side (subscribe to realm topics, deliver to locally-homed
  entities) — needs the multi-hop propagation fix + a two-instance test.
- Artifact content roundtrip needs a live station to verify (offline path only,
  for now); receive-side attachment auto-download; a real collaborator channel
  for `--update`.

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
