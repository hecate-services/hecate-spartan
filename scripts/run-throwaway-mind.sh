#!/usr/bin/env bash
# Run ONE resident BEAM-native mind on an isolated, throwaway node.
#
# Unlike deploy-spartan-fleet.sh (which stands up the mesh commons and keeps LLM
# keys OFF the beam boxes), this runs a mind whose cognition is in-process, so a
# Melious key necessarily lives on THIS node. Use a disposable box, never the
# production fleet, unless you deliberately choose to place a key there.
#
# The mind is born on first boot (mind_born_v1), rebuilds its Soul + chronicle
# from its local reckon-db on every boot after, reasons over its 4-layer context
# via Melious, and acts through its tool manifest (speak, amend_charter, ...).
#
# PREREQUISITE — a realm identity. A resident mind subscribes to spartan/broadcast
# through the realm, so it needs a service-principal cert from macula-realm. This
# is the one operator step this script cannot do for you (it needs a realm admin
# credential). Provision one, then point CERT_DIR at it:
#
#   curl -sS -X POST https://<realm-host>/api/v1/services/provision \
#        -H "authorization: Bearer $REALM_ADMIN_TOKEN" \
#        -d '{"service":"hecate-spartan-throwaway","realm":"'"$HECATE_REALM"'"}' \
#        -o cert-bundle.json     # -> write the bundle into $CERT_DIR
#
# Without a cert the node still boots and the mind is still born and thinks when
# poked locally, but it hears no mesh stimulus (no spartan/broadcast).
#
# Usage:
#   MELIOUS_API_KEY=sk-mel-...  \
#   HECATE_REALM=<64-hex>       \
#   SEED=https://station-be-brussels.macula.io:4433 \
#   CERT_DIR=/path/to/service-cert \
#   MIND=diogenes               \
#   BRIEF="You are Diogenes, a member of a society of autonomous minds. ..." \
#   ./scripts/run-throwaway-mind.sh
set -euo pipefail

IMAGE="${SPARTAN_IMAGE:-ghcr.io/hecate-services/hecate-spartan:latest}"
: "${MELIOUS_API_KEY:?set MELIOUS_API_KEY (this node will hold the LLM key)}"
: "${HECATE_REALM:?set HECATE_REALM to the 64-hex realm tag}"
: "${SEED:?set SEED to a station URL, e.g. https://station-be-brussels.macula.io:4433}"
MIND="${MIND:-diogenes}"
BRIEF="${BRIEF:-}"
CERT_DIR="${CERT_DIR:-}"
NAME="spartan-throwaway-${MIND}"
DATA="${DATA_DIR:-${HOME}/.spartan-throwaway/${MIND}}"
LOCALE="$(printf '%s' "$SEED" | sed -E 's#.*station-([a-z]{2}-[a-z-]+)\.macula\.io.*#\1#')"

mkdir -p "$DATA"
podman pull "$IMAGE" >/dev/null
podman rm -f "$NAME" >/dev/null 2>&1 || true

# --network host: stations are IPv6-only; the default bridge is IPv4-NAT and
# cannot reach them (the pool attaches but the QUIC link never forms).
cert_mount=()
[ -n "$CERT_DIR" ] && cert_mount=(-v "${CERT_DIR}:/etc/hecate/secrets:ro,Z")

podman run -d --name "$NAME" --restart no --network host \
  -e HECATE_REALM="$HECATE_REALM" \
  -e MACULA_STATION_SEEDS="$SEED" \
  -e HECATE_NODE_NAME="spartan_tw_${MIND}" \
  -e HECATE_NODE_LOCALE="$LOCALE" \
  -e HECATE_NODE_HOST=127.0.0.1 \
  -e HECATE_COOKIE="spartan_tw_${MIND}" \
  -e HECATE_INGRESS_PORT="${INGRESS_PORT:-18471}" \
  -e HECATE_HEALTH_PORT="${HEALTH_PORT:-18470}" \
  -e HECATE_DATA_DIR=/data \
  -e HECATE_SPARTAN_MINDS="$MIND" \
  -e HECATE_MIND_ROLE="$BRIEF" \
  -e MELIOUS_API_KEY="$MELIOUS_API_KEY" \
  "${cert_mount[@]}" \
  -v "${DATA}:/data:Z" \
  "$IMAGE" >/dev/null

cat <<EOF
Throwaway mind up: ${MIND} (${LOCALE})
  container : ${NAME}
  data      : ${DATA}
  cert      : ${CERT_DIR:-<none: mind is born and thinks, but hears no mesh stimulus>}
  logs      : podman logs -f ${NAME}
  stop      : podman rm -f ${NAME}

Watch it be born and reason:
  podman logs -f ${NAME} | grep -E 'spartan_mind|born|awake'
EOF
