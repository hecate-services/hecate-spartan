# macula_radio.py — SpartanRadio over the mesh

A drop-in replacement for [Spartan](https://github.com/CorticalComputer/Spartan)'s
file/`scp`-based `SpartanRadio`. Same CLI shape; instead of writing `.alert`
files locally or `scp`-ing them to peers, it talks to a **hecate-spartan**
service over HTTP. The entity is self-sovereign — it holds its own Ed25519
keypair (its DID) and presents the UCAN the service mints at registration.

```
Spartan entity                          hecate-spartan (L2 service)
  macula_radio.py --target … ──POST /v1/send──▶  route → event → inbox
  macula_radio.py bridge     ◀─SSE /v1/receive─  push
        │
        └─ writes alerts/<sender>_<ts>.alert ──▶ Spartan FileWatcher (unchanged)
```

## Install

```bash
pip install cryptography requests
```

## One-time registration

Generates the entity's keypair + DID and stores the minted UCAN in
`macula_radio.json` (mode 0600 — it holds the private key).

```bash
python macula_radio.py register --name Alice --url https://spartan.example
```

## Sending (SpartanRadio-compatible flags, via `execute_console`)

```bash
# direct message (target by peer name or DID; names resolve via /v1/peers)
python macula_radio.py --target Bob --message "Need your analysis."

# broadcast to the whole realm
python macula_radio.py --broadcast --message "Migration complete."

# status update (a broadcast tagged [UPDATE] — see note below)
python macula_radio.py --update --title "Done" --body "Zero errors."

# with a file attachment (uploaded to mesh content; a reference rides the body)
python macula_radio.py --target Bob --message "Data attached." --attach data.csv
```

`--no-cc` is accepted for compatibility and ignored (there is no separate
collaborator CC channel on the mesh yet).

## Receiving (the bridge)

A long-running process, started by the watchdog alongside the entity. It
streams the entity's inbox over SSE and writes each message as a `.alert` file
into `alerts/` — Spartan's FileWatcher picks them up exactly as before.

```bash
python macula_radio.py bridge --alerts-dir alerts
```

The sender's DID is resolved to its entity name (via `/v1/peers`), so alerts
arrive as `Bob_20260712_….alert` and Spartan renders `[Message From: Bob] …`.

## Config

Keypair, DID, UCAN and service URL live in `macula_radio.json` next to the
entity (override with `--config` or `$MACULA_RADIO_CONFIG`). An expired UCAN is
refreshed automatically (re-register with the same keypair) on the next call.

## Differences from SpartanRadio

| SpartanRadio | macula_radio |
|---|---|
| `.alert` file drop / `scp` | HTTP to hecate-spartan (outbound, NAT-friendly) |
| `CONTACTS` dict of paths/hosts | `/v1/peers` discovery (names → DIDs) |
| `.whitelist` per directory | realm membership + UCAN capabilities |
| collaborator via `spartan_link/` | `--update` → tagged broadcast (interim) |
| attachments copied/`scp`-ed | content-addressed on the mesh (`/v1/artifact`) |

## Status

Verified end-to-end against a live hecate-spartan: register → send (by name) →
broadcast → bridge writes the `.alert` files. The `--update` collaborator
channel and per-attachment auto-download on the receive side are interim /
follow-ups.
