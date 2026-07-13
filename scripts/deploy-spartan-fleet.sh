#!/usr/bin/env bash
# Deploy the hecate-spartan node fleet across the EU station partition: one node
# per country, each an outbound macula client dialing its own capital's station.
# All share one realm, so their mesh topics coincide and the federation is one
# society spread over eight countries. The minds (Gene's Spartan entities) run
# separately and dial a node's ingress; no LLM key ever reaches a beam node.
#
# TWO NODES PER HOST. The four beam boxes carry eight nodes, so each mind is
# homed in its own capital rather than sharing one. That needs three things to
# be per-node rather than per-image, all env-driven since the image roll of
# 2026-07-13:
#   HECATE_INGRESS_PORT / HECATE_HEALTH_PORT  (host networking puts them on the HOST)
#   HECATE_NODE_NAME                          (one epmd per host: names must differ)
#   HECATE_DATA_DIR + volume                  (one reckon-db store per node)
#
# NETWORK: --network host is REQUIRED. The stations are IPv6-only (Hetzner), the
# beam hosts have public IPv6, but the default docker bridge is IPv4-NAT only --
# so a bridged container cannot reach a station and stays dark (the pool attaches
# but the QUIC link never forms).
#
# The beam boxes run DOCKER (not podman, despite older docs). No watchtower label:
# a watchtower cycle recreates a node and tears down every entity's SSE stream, so
# this fleet is rolled deliberately.
#
#   HECATE_REALM=<64-hex> ./scripts/deploy-spartan-fleet.sh
set -euo pipefail

IMAGE="${SPARTAN_IMAGE:-ghcr.io/hecate-services/hecate-spartan:latest}"
REALM="${HECATE_REALM:?set HECATE_REALM to the 64-hex spartan realm tag}"

# host | station seed | country code | ingress port | health port | node name
#
# Two per host, each on a DIFFERENT country station. Copenhagen and Dublin are
# DNS aliases onto Amsterdam's and Brussels' addresses, not separate stations,
# so they are not used here.
#
# WHY BE/DE/FR/IT ARE STILL CALLED `hecate_spartan`, not `hecate_spartan_be`:
# reckon-db (Ra/khepri) persists cluster membership as {Name, Node}, so an
# existing store is bound to the Erlang node name that created it. Renaming the
# node orphans the store from its own leader -- it comes up logging
# "Leader detected: 'hecate_spartan@127.0.0.1'" for a node that no longer
# exists, and every dispatch times out. Those four nodes carry the fleet's event
# history (every registration since the beginning), so they keep their original
# name and their data. Only the nodes born with the new naming use it. Symmetry
# is not worth an event log.
MAP=(
  "beam00.lab|https://station-be-brussels.macula.io:4433|be|8471|8470|hecate_spartan"
  "beam00.lab|https://station-nl-amsterdam.macula.io:4433|nl|8481|8480|hecate_spartan_nl"
  "beam01.lab|https://station-de-frankfurt.macula.io:4433|de|8471|8470|hecate_spartan"
  "beam01.lab|https://station-at-vienna.macula.io:4433|at|8481|8480|hecate_spartan_at"
  "beam02.lab|https://station-fr-paris.macula.io:4433|fr|8471|8470|hecate_spartan"
  "beam02.lab|https://station-es-madrid.macula.io:4433|es|8481|8480|hecate_spartan_es"
  "beam03.lab|https://station-it-milan.macula.io:4433|it|8471|8470|hecate_spartan"
  "beam03.lab|https://station-pl-warsaw.macula.io:4433|pl|8481|8480|hecate_spartan_pl"
)

for entry in "${MAP[@]}"; do
  IFS='|' read -r HOST SEED CC PORT HPORT NODE <<<"$entry"
  echo "=== ${HOST} (${CC}) -> ${SEED}  ingress :${PORT}"
  # REALM/SEED/CC/IMAGE are not secrets (realm = topic tag, seeds = public URLs).
  ssh -o BatchMode=yes "rl@${HOST}" \
      "IMAGE='${IMAGE}' REALM='${REALM}' SEED='${SEED}' CC='${CC}' PORT='${PORT}' HPORT='${HPORT}' NODE='${NODE}' bash -s" <<'REMOTE'
set -euo pipefail
docker pull "$IMAGE" >/dev/null
name="spartan-${CC}"
# /bulk0/hecate is root-owned; the docker daemon (root) auto-creates the
# bind-mount source, so no sudo mkdir is needed and data still lands on /bulk0.
data="/bulk0/hecate/spartan/${name}"
docker rm -f "$name" >/dev/null 2>&1 || true
docker run -d --name "$name" --restart unless-stopped --network host \
  -e HECATE_REALM="$REALM" \
  -e MACULA_STATION_SEEDS="$SEED" \
  -e HECATE_NODE_NAME="$NODE" \
  -e HECATE_NODE_HOST=127.0.0.1 \
  -e HECATE_COOKIE="spartan_${CC}" \
  -e HECATE_INGRESS_PORT="$PORT" \
  -e HECATE_HEALTH_PORT="$HPORT" \
  -e HECATE_DATA_DIR=/data \
  -v "${data}:/data" \
  "$IMAGE" >/dev/null
echo "  ${name} up (host net) ingress :${PORT} health :${HPORT}"
REMOTE
done

cat <<'EOF'

Fleet up: eight countries, one node each.
  BE beam00.lab:8471   NL beam00.lab:8481
  DE beam01.lab:8471   AT beam01.lab:8481
  FR beam02.lab:8471   ES beam02.lab:8481
  IT beam03.lab:8471   PL beam03.lab:8481
EOF
