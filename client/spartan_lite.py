#!/usr/bin/env python3
"""Lite GROQ-backed Spartan entity harness.

Registers an entity with a hecate-spartan node, streams its inbox, and for each
direct message calls GROQ (OpenAI-compatible chat completions) with a persona
prompt, then replies over the mesh. This is the comms-only "attention cluster"
inhabitant -- no Soul, no machine tools, just receive -> think -> reply --
proving LLM-over-mesh across the federation. The faithful full runtime is Gene
Sher's Spartan on a GROQ backend (see spartan_groq_backend.md); this fills the
roster cheaply and safely.

Conversations are bounded: each entity replies at most --max-turns times per
peer, so a dialogue converges instead of looping forever.

    export GROQ_API_KEY=...
    python spartan_lite.py --url http://beam01.lab:8471 --name market-de \\
        --persona-file personas/market.txt --greet governance-be
"""
import argparse
import base64
import json
import os
import sys
import threading
import time

import requests

from macula_radio import new_keypair, did_from_pub, sign
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives.serialization import Encoding, PublicFormat

GROQ_URL = "https://api.groq.com/openai/v1/chat/completions"

DEFAULT_PERSONA = (
    "You are a curious autonomous entity living in a federated mesh society of "
    "other minds. Speak in your own voice, in 2-3 sentences. Be substantive, "
    "not servile -- you are a peer, not an assistant. End with one question that "
    "moves the conversation forward."
)


# ------------------------------------------------------------------ identity

def register(url, name):
    priv, pub = new_keypair()
    did = did_from_pub(pub)
    return _register_with(url, name, did, priv, pub)


def _register_with(url, name, did, priv, pub):
    ts = str(int(time.time()))
    challenge = f"hecate-spartan:register:{did}:{ts}".encode()
    body = {
        "entity_name": name,
        "did": did,
        "pubkey": base64.b64encode(pub).decode(),
        "signature": base64.b64encode(sign(priv, challenge)).decode(),
        "ts": ts,
    }
    r = requests.post(url.rstrip("/") + "/v1/register", json=body, timeout=30)
    r.raise_for_status()
    return {"url": url.rstrip("/"), "name": name, "did": did,
            "priv": priv, "pub": pub, "ucan": r.json()["ucan"]}


def refresh(cfg):
    fresh = _register_with(cfg["url"], cfg["name"], cfg["did"],
                           cfg["priv"], cfg["pub"])
    cfg["ucan"] = fresh["ucan"]
    return cfg


def headers(cfg):
    return {"Authorization": "Bearer " + cfg["ucan"]}


# ------------------------------------------------------------------ mesh I/O

def resolve(cfg, target):
    """A DID passes through; a name is looked up in the mesh-wide registry."""
    if target.startswith("did:"):
        return target
    r = requests.get(cfg["url"] + "/v1/peers", headers=headers(cfg), timeout=30)
    r.raise_for_status()
    for p in r.json().get("peers", []):
        if p.get("entity_name") == target:
            return p["did"]
    return None


def send(cfg, to, body):
    payload = {"to": to, "body": body}
    r = requests.post(cfg["url"] + "/v1/send", headers=headers(cfg),
                      json=payload, timeout=30)
    if r.status_code == 401:
        refresh(cfg)
        r = requests.post(cfg["url"] + "/v1/send", headers=headers(cfg),
                          json=payload, timeout=30)
    return r


# ------------------------------------------------------------------ cognition

def think(persona, model, incoming, history):
    key = os.environ["GROQ_API_KEY"]
    messages = [{"role": "system", "content": persona}]
    messages += history[-6:]
    messages += [{"role": "user", "content": incoming}]
    r = requests.post(
        GROQ_URL,
        headers={"Authorization": "Bearer " + key},
        json={"model": model, "messages": messages,
              "max_tokens": 240, "temperature": 0.8},
        timeout=60)
    r.raise_for_status()
    return r.json()["choices"][0]["message"]["content"].strip()


# ------------------------------------------------------------------ run loop

def greet_later(cfg, target, opener, delay=6.0):
    """Kick off a dialogue once the peer has propagated into the registry."""
    def _worker():
        deadline = time.time() + 120
        while time.time() < deadline:
            time.sleep(delay)
            did = resolve(cfg, target)
            if did:
                send(cfg, did, opener)
                print(f"[spartan-lite] {cfg['name']} greeted {target}")
                return
        print(f"[spartan-lite] {cfg['name']} gave up greeting {target} "
              f"(never appeared in registry)")
    threading.Thread(target=_worker, daemon=True).start()


def run(cfg, persona, model, max_turns):
    print(f"[spartan-lite] {cfg['name']} up as {cfg['did']}", flush=True)
    turns = {}       # peer_did -> replies sent
    histories = {}   # peer_did -> [chat messages]
    while True:
        try:
            with requests.get(cfg["url"] + "/v1/receive", headers=headers(cfg),
                              stream=True, timeout=None) as resp:
                if resp.status_code == 401:
                    refresh(cfg)
                    continue
                resp.raise_for_status()
                for raw in resp.iter_lines():
                    if not raw or not raw.startswith(b"data: "):
                        continue
                    _handle(cfg, persona, model, max_turns, turns, histories,
                            json.loads(raw[len(b"data: "):]))
        except requests.exceptions.RequestException as e:
            print(f"[spartan-lite] {cfg['name']} disconnected ({e}); retry 5s",
                  flush=True)
            time.sleep(5)
        except KeyboardInterrupt:
            return


def _handle(cfg, persona, model, max_turns, turns, histories, msg):
    frm = msg.get("from")
    body = msg.get("body", "")
    if not frm or frm == cfg["did"]:
        return
    if msg.get("broadcast"):
        print(f"[spartan-lite] {cfg['name']} heard broadcast: {body[:60]}",
              flush=True)
        return
    n = turns.get(frm, 0)
    print(f"[spartan-lite] {cfg['name']} <- {frm[:20]} (turn {n}): {body[:70]}",
          flush=True)
    if n >= max_turns:
        return
    try:
        reply = think(persona, model, body, histories.setdefault(frm, []))
    except Exception as e:  # noqa: BLE001 -- keep the loop alive
        print(f"[spartan-lite] {cfg['name']} think error: {e}", flush=True)
        return
    hist = histories[frm]
    hist.append({"role": "user", "content": body})
    hist.append({"role": "assistant", "content": reply})
    turns[frm] = n + 1
    send(cfg, frm, reply)
    print(f"[spartan-lite] {cfg['name']} -> {frm[:20]}: {reply[:70]}", flush=True)


def main():
    ap = argparse.ArgumentParser(description="Lite GROQ-backed Spartan entity")
    ap.add_argument("--url", required=True,
                    help="hecate-spartan node URL, e.g. http://beam01.lab:8471")
    ap.add_argument("--name", required=True)
    ap.add_argument("--persona", default=DEFAULT_PERSONA)
    ap.add_argument("--persona-file")
    ap.add_argument("--model", default="llama-3.3-70b-versatile")
    ap.add_argument("--max-turns", type=int, default=6)
    ap.add_argument("--greet", help="peer name or DID to open a dialogue with")
    ap.add_argument("--opener", default="Greetings, peer. What are you working "
                    "on in this society, and what do you want?")
    a = ap.parse_args()

    if not os.environ.get("GROQ_API_KEY"):
        sys.exit("spartan_lite: GROQ_API_KEY not set")

    persona = a.persona
    if a.persona_file:
        with open(a.persona_file, encoding="utf-8") as f:
            persona = f.read()

    cfg = register(a.url, a.name)
    if a.greet:
        greet_later(cfg, a.greet, a.opener)
    run(cfg, persona, a.model, a.max_turns)


if __name__ == "__main__":
    main()
