# Changelog

All notable changes to hecate-spartan are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/); versions follow SemVer.

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
