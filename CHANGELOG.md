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
- EUnit: 13 tests (UCAN roundtrip, entity-sig verify + forgery rejection,
  realm-scoped caps, handler validation). `rebar3 compile` + `rebar3 eunit`
  green against the full dependency graph.

### Still skeleton
- No ingress (cowboy `/v1/*`) and no projection wiring yet — the registry
  read model, `route`/`broadcast`/`share`/`receive` slices, and mesh publish
  are the next increments (Phase 1a).

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
