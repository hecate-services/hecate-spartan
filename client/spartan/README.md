# Spartan ↔ Macula mesh bridge

Run Gene Sher's Spartan over the Macula mesh (via a `hecate-spartan` node)
instead of SpartanRadio's file/SCP comms, with Groq as the cognitive backend.
Three pieces, each independent:

| Piece | File | Effect |
|---|---|---|
| Backend | [`groq_backend.md`](groq_backend.md) | Groq becomes a Spartan backend (OpenAI-compatible) |
| Outbound comms | `SpartanRadio.py` (this dir) + `../macula_radio.py` | Entity sends ride the mesh — **no genesis_core change** (identical CLI) |
| Inbound comms | `../macula_radio.py bridge` | Mesh messages become `alerts/*.alert` — Spartan's FileWatcher consumes them unchanged |

## Install

1. **Backend:** apply the three edits in [`groq_backend.md`](groq_backend.md);
   `export GROQ_API_KEY=...`; set `active_backend: groq_llama`.

2. **Outbound:** copy this `SpartanRadio.py` and `../macula_radio.py` into the
   entity's `Tools/`. Point it at a node and name the entity:

   ```
   export SPARTAN_MESH_URL=http://beam00.lab:8471   # its home node
   export SPARTAN_MESH_NAME=Athena                   # the entity's mesh name
   ```

   The entity's existing protocol works verbatim — `python Tools/SpartanRadio.py
   --target Bob --message "..."`, `--broadcast`, `--update` — now over the mesh.
   Identity (Ed25519 + UCAN) is minted once and cached as `.spartan_mesh.json`.

3. **Inbound:** run the bridge alongside the entity so incoming mesh messages
   land as alerts (FileWatcher already watches `alerts/`):

   ```
   python Tools/macula_radio.py --config Tools/.spartan_mesh.json \
       bridge --alerts-dir alerts
   ```

## What changes vs vanilla SpartanRadio

- Targets are **mesh entity names**; the registry resolves them across the whole
  federation, so the `local`/`remote`/SCP contact distinction disappears — a peer
  is reachable wherever it is homed (Brussels ↔ Milan, etc.).
- The `gene` CC becomes a mesh broadcast tagged `[CC]`/`[UPDATE]` (there is no
  private human channel on the mesh yet).
- Every message is an event-sourced FACT in the node's reckon-db store
  (provenance), and delivery is the multi-hop mesh, not SCP.

## Homing

The entity is homed on the node in `SPARTAN_MESH_URL`. Two real Spartans on two
country nodes (e.g. Brussels + Milan) converse over the multi-hop mesh exactly
as the lite `spartan_lite.py` entities do — same registry, routing, and inbox.
