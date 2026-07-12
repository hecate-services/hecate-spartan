# Architecture

hecate-spartan is a Layer-2 `hecate-om` service. It is the mesh-accountable
institution that Spartan entities bank with.

## Layering

```
Layer 4 — apps        (hecate-ui plugins — not involved)
Layer 3 — session     hecate-daemon         attended, per-person — NOT this
Layer 2 — services    hecate-spartan   ◀──  always-on institution (here)
Layer 1 — identity    macula-realm          issues the service-principal cert
Layer 0 — kernel      macula-station        relays, DHT, QUIC
```

## Boot sequence

`hecate_spartan_app:start/2` makes one call: `hecate_om:boot/1`. Because the
service module exports `store_id/0` + `data_dir/0`, `boot/1`:

1. starts the reckon-db store `hecate_spartan_store` at
   `${HECATE_DATA_DIR}/hecate_spartan_store/` (single mode),
2. installs the declared secondary indexes,
3. starts the per-store evoq subscription (projections + process managers),
4. registers the service's capabilities and the `/health` probe,
5. calls `hecate_spartan_service:start/1` → the top supervisor.

## Data flow (target)

```
entity ──POST /v1/send──▶ hecate-spartan ingress
                              │
                    route_message_v1 (command)
                              │
                    maybe_route_message (handler)
                              │
                    message_routed_v1 (event, reckon-db)   ← provenance
                         ├── projection → deliveries read model
                         └── PM on_message_routed_publish_fact
                                    │
                            macula:publish → spartan.{realm}.inbox.{to}
                                    │
                         recipient's macula_radio_bridge
                                    │
                            writes .alert into alerts/  → FileWatcher
```

## Federation

Multiple hecate-spartan instances across the commons; each entity homed to
one; cross-instance delivery rides the mesh between services. No central
chokepoint — the federated, non-extractive property holds end to end.

## Why the entity stays thin

The Spartan entity is Python on arbitrary hardware behind NAT. Embedding a
QUIC/DHT stack in every agent is fragile and heavy. Instead the entity holds
an account and an outbound connection to its home service. First-class mesh
nodes (e.g. the faber-neuroevolution modules in the distributed-evolution
track) run a real Erlang leaf — but that is a different workload from a
Python cognitive agent that only needs reliable, discoverable, provenance-
tracked messaging and a backend.
