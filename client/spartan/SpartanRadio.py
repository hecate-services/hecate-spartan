#!/usr/bin/env python3
"""SpartanRadio -- mesh drop-in.

A drop-in replacement for Gene Sher's Tools/SpartanRadio.py that routes an
entity's outbound comms over the Macula mesh (via a hecate-spartan node)
instead of local file writes / SCP. The CLI is identical to the original, so
the entity's genesis_core "SPARTANRADIO" protocol needs NO change:

    python Tools/SpartanRadio.py --target Bob   --message "hello"
    python Tools/SpartanRadio.py --broadcast    --message "to everyone"
    python Tools/SpartanRadio.py --update --title "status" --body "..."

INBOUND is handled separately by `macula_radio.py bridge`, which streams the
entity's inbox and writes each message as an alerts/*.alert file -- exactly
what Spartan's FileWatcher already consumes.

Targets are peer ENTITY NAMES; the mesh registry resolves them across the whole
federation, so the local/remote/SCP contact distinction disappears -- a peer is
reachable wherever it is homed. The collaborator ("gene") CC becomes a mesh
broadcast tagged [UPDATE] (there is no private human channel on the mesh yet).

Config: set SERVICE_URL + MY_NAME below (or via env). Identity (Ed25519 keypair
+ UCAN) is minted once and cached next to this file. Requires: requests,
cryptography (same deps as macula_radio.py, which must sit beside this file).
"""
import argparse
import json
import os
import sys

# Shared crypto + service protocol live in macula_radio.py (ship both in Tools/).
_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, _HERE)
import requests
from macula_radio import new_keypair, did_from_pub, sign, register as _mr_register

# ---------------------------------------------------------------- CONFIG
MY_NAME = os.environ.get("SPARTAN_MESH_NAME", "NewEntity")
SERVICE_URL = os.environ.get("SPARTAN_MESH_URL", "http://127.0.0.1:8471")
STATE_FILE = os.path.join(_HERE, ".spartan_mesh.json")

# ---------------------------------------------------------------- identity

def _load_or_register():
    if os.path.exists(STATE_FILE):
        with open(STATE_FILE) as f:
            cfg = json.load(f)
        if cfg.get("service_url") == SERVICE_URL and cfg.get("entity_name") == MY_NAME:
            return cfg
    # Mint a fresh identity + UCAN against the node.
    priv, pub = new_keypair()
    did = did_from_pub(pub)
    ts = str(int(__import__("time").time()))
    challenge = f"hecate-spartan:register:{did}:{ts}".encode()
    import base64
    body = {"entity_name": MY_NAME, "did": did,
            "pubkey": base64.b64encode(pub).decode(),
            "signature": base64.b64encode(sign(priv, challenge)).decode(), "ts": ts}
    r = requests.post(SERVICE_URL.rstrip("/") + "/v1/register", json=body, timeout=30)
    r.raise_for_status()
    cfg = {"service_url": SERVICE_URL, "entity_name": MY_NAME, "did": did,
           "priv_hex": priv.hex(), "ucan": r.json()["ucan"]}
    with open(STATE_FILE, "w") as f:
        json.dump(cfg, f)
    return cfg


def _refresh(cfg):
    import base64
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
    from cryptography.hazmat.primitives.serialization import Encoding, PublicFormat
    priv = bytes.fromhex(cfg["priv_hex"])
    ts = str(int(__import__("time").time()))
    challenge = f"hecate-spartan:register:{cfg['did']}:{ts}".encode()
    pub = Ed25519PrivateKey.from_private_bytes(priv).public_key().public_bytes(
        Encoding.Raw, PublicFormat.Raw)
    body = {"entity_name": cfg["entity_name"], "did": cfg["did"],
            "pubkey": base64.b64encode(pub).decode(),
            "signature": base64.b64encode(sign(priv, challenge)).decode(), "ts": ts}
    r = requests.post(cfg["service_url"] + "/v1/register", json=body, timeout=30)
    r.raise_for_status()
    cfg["ucan"] = r.json()["ucan"]
    with open(STATE_FILE, "w") as f:
        json.dump(cfg, f)
    return cfg


def _headers(cfg):
    return {"Authorization": "Bearer " + cfg["ucan"]}


def _post(cfg, path, payload):
    url = cfg["service_url"] + path
    r = requests.post(url, headers=_headers(cfg), json=payload, timeout=30)
    if r.status_code == 401:
        cfg = _refresh(cfg)
        r = requests.post(url, headers=_headers(cfg), json=payload, timeout=30)
    return r


def _resolve(cfg, name):
    if name.startswith("did:"):
        return name
    r = requests.get(cfg["service_url"] + "/v1/peers", headers=_headers(cfg), timeout=30)
    r.raise_for_status()
    for p in r.json().get("peers", []):
        if p.get("entity_name") == name:
            return p["did"]
    return None


def _upload(cfg, path):
    with open(path, "rb") as f:
        r = requests.post(cfg["service_url"] + "/v1/artifact", headers={
            **_headers(cfg), "content-type": "application/octet-stream"},
            data=f.read(), timeout=60)
    r.raise_for_status()
    return r.json()["hash"]


# ---------------------------------------------------------------- operations

def send_message(target_name, message, cc_gene=True, attach_path=None):
    cfg = _load_or_register()
    body = message
    if attach_path:
        body += f"\n[attachment: {os.path.basename(attach_path)} artifact={_upload(cfg, attach_path)}]"
    did = _resolve(cfg, target_name)
    if not did:
        return False, f"unknown peer '{target_name}' (not in mesh registry)"
    r = _post(cfg, "/v1/send", {"to": did, "body": body})
    if r.status_code != 202:
        return False, f"send failed ({r.status_code}): {r.text}"
    if cc_gene:
        _post(cfg, "/v1/broadcast", {"body": f"[CC] to {target_name}: {message}"})
    return True, r.json().get("msg_id", "")


def broadcast(message, cc_gene=True, attach_path=None):
    cfg = _load_or_register()
    body = message
    if attach_path:
        body += f"\n[attachment: {os.path.basename(attach_path)} artifact={_upload(cfg, attach_path)}]"
    r = _post(cfg, "/v1/broadcast", {"body": body})
    return f"broadcast: {r.json().get('msg_id') if r.status_code == 202 else r.text}"


def send_update(title, body):
    cfg = _load_or_register()
    r = _post(cfg, "/v1/broadcast", {"body": f"[UPDATE] {title}\n{body}"})
    return (r.status_code == 202), ("sent" if r.status_code == 202 else r.text)


def main():
    p = argparse.ArgumentParser(description="SpartanRadio -- Inter-agent communication (mesh)")
    p.add_argument("--target", "-t", type=str)
    p.add_argument("--message", "-m", type=str)
    p.add_argument("--broadcast", "-b", action="store_true")
    p.add_argument("--no-cc", action="store_true")
    p.add_argument("--attach", "-a", type=str)
    p.add_argument("--update", "-u", action="store_true")
    p.add_argument("--title", type=str)
    p.add_argument("--body", type=str)
    args = p.parse_args()
    cc = not args.no_cc

    if args.update:
        if not args.title or not args.body:
            sys.exit("--update requires --title and --body")
        ok, detail = send_update(args.title, args.body)
        print(detail if ok else f"update failed: {detail}")
    elif args.broadcast:
        if not args.message:
            sys.exit("--broadcast requires --message")
        print(broadcast(args.message, cc_gene=cc, attach_path=args.attach))
    elif args.target:
        if not args.message:
            sys.exit("--target requires --message")
        ok, detail = send_message(args.target, args.message, cc_gene=cc, attach_path=args.attach)
        print(f"sent to {args.target}: {detail}" if ok else f"send failed: {detail}")
    else:
        p.print_help()


if __name__ == "__main__":
    main()
