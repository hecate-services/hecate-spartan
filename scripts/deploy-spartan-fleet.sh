#!/usr/bin/env bash
# Deploy the hecate-spartan node fleet across the 4-country Macula partition:
# one node per beam box, each an outbound macula client dialing its country
# station. All share one realm so their mesh topics coincide. Entities (the
# minds) run separately -- spartan_lite.py or Gene's Spartan -- and dial a
# node's ingress; no secret (GROQ key etc.) ever reaches the beam nodes.
#
# NETWORK: --network host is REQUIRED. The stations are IPv6-only (Hetzner),
# the beam hosts have working public IPv6, but the default docker bridge is
# IPv4-NAT only -- so a bridged container cannot reach a station and stays
# effectively dark (the pool attaches but the QUIC link never forms). Host
# networking gives the container the host's IPv6. dronex does the same.
#
# Host networking means the release's fixed ports (8471 ingress, 8470 health)
# bind on the host, so this runs ONE node per host. Running the spec's 2 nodes
# per station needs env-configurable ingress/health ports (a follow-up rebuild).
#
# The beam boxes run DOCKER (not podman, despite older docs). watchtower is
# present and label-gated -- these nodes deliberately DO NOT carry
# com.centurylinklabs.watchtower.enable, so watchtower leaves them alone (it
# still auto-updates dronex, which does carry the label). A watchtower cycle
# recreates the node, drops every entity's SSE stream and (before the registry
# rebuild landed) wiped the registry -- fleet churn, not a fault of the
# entities. Roll a new image here explicitly instead.
#
#   HECATE_REALM=<64-hex> ./scripts/deploy-spartan-fleet.sh
set -euo pipefail

IMAGE="${SPARTAN_IMAGE:-ghcr.io/hecate-services/hecate-spartan:latest}"
REALM="${HECATE_REALM:?set HECATE_REALM to the 64-hex spartan realm tag}"

# beam host | country station seed | country code
MAP=(
  "beam00.lab|https://station-be-brussels.macula.io:4433|be"
  "beam01.lab|https://station-de-frankfurt.macula.io:4433|de"
  "beam02.lab|https://station-fr-paris.macula.io:4433|fr"
  "beam03.lab|https://station-it-milan.macula.io:4433|it"
)

for entry in "${MAP[@]}"; do
  IFS='|' read -r HOST SEED CC <<<"$entry"
  echo "=== ${HOST} (${CC}) -> ${SEED} ==="
  # REALM/SEED/CC/IMAGE are not secrets (realm = topic tag, seeds = public URLs).
  ssh -o BatchMode=yes "rl@${HOST}" \
      "IMAGE='${IMAGE}' REALM='${REALM}' SEED='${SEED}' CC='${CC}' bash -s" <<'REMOTE'
set -euo pipefail
docker pull "$IMAGE" >/dev/null
name="spartan-${CC}"
# /bulk0/hecate is root-owned; the docker daemon (root) auto-creates the
# bind-mount source, so no sudo mkdir is needed and data still lands on /bulk0.
data="/bulk0/hecate/spartan/${name}"
docker rm -f "$name" "spartan-${CC}-1" "spartan-${CC}-2" >/dev/null 2>&1 || true
docker run -d --name "$name" --restart unless-stopped --network host \
  -e HECATE_REALM="$REALM" \
  -e MACULA_STATION_SEEDS="$SEED" \
  -e HECATE_NODE_HOST=127.0.0.1 \
  -e HECATE_COOKIE="spartan_${CC}" \
  -e HECATE_DATA_DIR=/data \
  -v "${data}:/data" \
  "$IMAGE" >/dev/null
echo "  ${name} up (host net) ingress :8471"
REMOTE
done

echo ""
echo "Fleet up. Ingress: BE http://beam00.lab:8471  DE http://beam01.lab:8471"
echo "                   FR http://beam02.lab:8471  IT http://beam03.lab:8471"
