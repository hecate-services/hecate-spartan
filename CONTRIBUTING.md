# Contributing

Trunk-based. Commit directly to `main`. No PRs.

## Build

```bash
rebar3 compile
rebar3 ct
```

## Style

- Erlang: `warnings_as_errors`, dialyzer clean
- Vertical slicing — no `services/`, no `helpers/`. Each capability is a desk
  (`register_entity/`, `route_message/`, …) owning its command, event,
  handler, and projection. No central "all listeners" supervisor.
- Business-verb events only — `entity_registered`, `message_routed`. Never
  `created` / `updated` / `deleted`.
- This service is built on `hecate_om`; extend the behaviour, don't write a
  parallel service runner.

## Issues

https://codeberg.org/hecate-services/hecate-spartan/issues
