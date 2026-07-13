#!/usr/bin/env python3
"""wire -- the news, delivered to the agents.

Each country's agents get their own country's press. The wire registers as a
mesh entity per capital (`wire-be`, `wire-de`, ...) and SENDS headlines as
ordinary messages to the agents homed on that node. It is not a special channel:
it is a peer that happens to only ever talk about the news.

That matters. The newspaper is delivered; reading it, and caring, remain the
agent's business. An agent that ignores the wire for a week is making a
statement, and the record shows it. And because the agents read DIFFERENT
national coverage of the same European events, they hold genuinely different
priors -- which is the whole reason to run eight of them in eight countries
rather than eight copies of one.

    python3 wire.py --node http://127.0.0.1:8471 --locale be --once
    python3 wire.py --node http://127.0.0.1:8471 --locale be --interval 3600

Feeds are public RSS/Atom. Headlines and summaries only: no scraping, no
paywalls, attribution on every item.
"""
import argparse
import hashlib
import json
import os
import re
import sys
import time
import xml.etree.ElementTree as ET
from urllib.request import urlopen, Request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from macula_radio import (auth_headers, new_keypair, did_from_pub, sign,
                          post_authed, resolve_peers)
import requests

# Public national feeds, one set per capital. European public-service and
# reference press where possible.
FEEDS = {
    "be": [("VRT NWS", "https://www.vrt.be/vrtnws/nl.rss.articles.xml"),
           ("RTBF", "https://rss.rtbf.be/article/rss/highlight_rtbfinfo_info.xml")],
    "nl": [("NOS", "https://feeds.nos.nl/nosnieuwsalgemeen")],
    "de": [("Tagesschau", "https://www.tagesschau.de/index~rss2.xml")],
    "at": [("ORF", "https://rss.orf.at/news.xml")],
    "fr": [("France Info", "https://www.francetvinfo.fr/titres.rss")],
    "es": [("RTVE", "https://api2.rtve.es/rss/temas_noticias.xml")],
    "it": [("ANSA", "https://www.ansa.it/sito/ansait_rss.xml")],
    "pl": [("Polskie Radio", "https://polskieradio.pl/rss/33")],
}

SEEN_FILE_TMPL = "/tmp/wire-seen-{locale}.json"
MAX_ITEMS = 3
MAX_SUMMARY = 400


def fetch(url):
    req = Request(url, headers={"User-Agent": "macula-wire/1.0 (+https://macula.io)"})
    with urlopen(req, timeout=20) as r:
        return r.read()


def strip_html(text):
    return re.sub(r"\s+", " ", re.sub(r"<[^>]+>", "", text or "")).strip()


def parse(xml_bytes, source):
    """RSS or Atom, whichever the outlet serves."""
    root = ET.fromstring(xml_bytes)
    items = root.findall(".//item") or root.findall(
        ".//{http://www.w3.org/2005/Atom}entry")

    out = []
    for it in items:
        title = it.findtext("title") or it.findtext(
            "{http://www.w3.org/2005/Atom}title") or ""
        desc = it.findtext("description") or it.findtext(
            "{http://www.w3.org/2005/Atom}summary") or ""
        link = it.findtext("link") or ""
        if not link:
            l = it.find("{http://www.w3.org/2005/Atom}link")
            link = l.get("href", "") if l is not None else ""

        title = strip_html(title)
        if not title:
            continue

        out.append({
            "source": source,
            "title": title,
            "summary": strip_html(desc)[:MAX_SUMMARY],
            "url": link.strip(),
            "id": hashlib.sha256((link or title).encode()).hexdigest()[:16],
        })
    return out


def load_seen(locale):
    path = SEEN_FILE_TMPL.format(locale=locale)
    if os.path.exists(path):
        with open(path) as f:
            return set(json.load(f))
    return set()


def save_seen(locale, seen):
    path = SEEN_FILE_TMPL.format(locale=locale)
    with open(path, "w") as f:
        json.dump(sorted(seen)[-500:], f)


def register(node, name, state_path):
    """The wire is a mesh entity like any other: its own key, its own UCAN."""
    if os.path.exists(state_path):
        with open(state_path) as f:
            return json.load(f)

    priv, pub = new_keypair()
    did = did_from_pub(pub)
    ts = str(int(time.time()))
    challenge = f"hecate-spartan:register:{did}:{ts}".encode()
    import base64
    body = {"entity_name": name, "did": did,
            "pubkey": base64.b64encode(pub).decode(),
            "signature": base64.b64encode(sign(priv, challenge)).decode(), "ts": ts}
    r = requests.post(node.rstrip("/") + "/v1/register", json=body, timeout=30)
    r.raise_for_status()
    cfg = {"service_url": node.rstrip("/"), "entity_name": name, "did": did,
           "priv_hex": priv.hex(), "ucan": r.json()["ucan"]}
    with open(state_path, "w") as f:
        json.dump(cfg, f)
    os.chmod(state_path, 0o600)
    return cfg


class Args:
    """post_authed persists a refreshed UCAN through this."""

    def __init__(self, config):
        self.config = config


def readers(cfg, locale):
    """The agents THIS wire serves: the ones homed in its own capital.

    The registry is mesh-wide, so a naive send reaches every entity in the
    federation -- including agents in seven other countries and every dead probe
    that ever registered. The whole point is that a Belgian agent reads the
    Belgian press, so filter on the locale the node reports, and skip anything
    that is not a live agent.
    """
    r = requests.get(cfg["service_url"] + "/v1/peers",
                     headers=auth_headers(cfg), timeout=30)
    r.raise_for_status()

    out = []
    for p in r.json().get("peers", []):
        name = p.get("entity_name") or ""
        if p.get("did") == cfg["did"] or name.startswith("wire-"):
            continue
        if p.get("locale") != f"{locale}-" and not str(p.get("locale") or "").startswith(f"{locale}-"):
            continue
        out.append(p)
    return out


def deliver(cfg, args, item, locale):
    """Send a headline to the agents this wire serves."""
    body = (f"[{item['source']}] {item['title']}\n"
            f"{item['summary']}\n{item['url']}".strip())

    sent = 0
    for p in readers(cfg, locale):
        r = post_authed(args, cfg, "/v1/send", json={"to": p["did"], "body": body})
        if r.status_code == 202:
            sent += 1
    return sent


def run_once(cfg, args, locale):
    seen = load_seen(locale)
    fresh = []

    for source, url in FEEDS.get(locale, []):
        try:
            for item in parse(fetch(url), source):
                if item["id"] not in seen:
                    fresh.append(item)
        except Exception as e:                                  # noqa: BLE001
            print(f"[wire] {source} failed: {e}", file=sys.stderr)

    # A cognition cycle is ~50k tokens. Deliver a few items, not a whole paper.
    for item in fresh[:MAX_ITEMS]:
        n = deliver(cfg, args, item, locale)
        seen.add(item["id"])
        print(f"[wire] {locale}: {item['title'][:60]} -> {n} agent(s)")

    save_seen(locale, seen)
    return len(fresh[:MAX_ITEMS])


def main():
    p = argparse.ArgumentParser(description="deliver the national press to the agents")
    p.add_argument("--node", required=True, help="the hecate-spartan node to home on")
    p.add_argument("--locale", required=True, choices=sorted(FEEDS), help="country")
    p.add_argument("--interval", type=int, default=0, help="seconds; 0 = once")
    p.add_argument("--state", default=None, help="identity file")
    a = p.parse_args()

    name = f"wire-{a.locale}"
    state = a.state or os.path.expanduser(f"~/.wire-{a.locale}.json")
    cfg = register(a.node, name, state)
    args = Args(state)
    print(f"[wire] {name} on {a.node} ({cfg['did'][:24]}…)")

    while True:
        run_once(cfg, args, a.locale)
        if a.interval <= 0:
            return
        time.sleep(a.interval)


if __name__ == "__main__":
    main()
