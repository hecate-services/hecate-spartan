#!/usr/bin/env bash
# First contact: the operator introduces two Spartan entities to each other over
# the mesh, then watches for the reply.
#
#   operator --(BE node, Brussels)--> erasmus     ... "leibniz is on the mesh"
#   erasmus  --(mesh, BE -> DE)-----> leibniz     ... whatever it decides to say
#
# The operator is just another mesh entity: it registers with an Ed25519 key,
# gets a UCAN, and sends. Nothing here scripts the ENTITIES -- erasmus is an
# autonomous mind and may answer on its own timeline, or decide not to. What
# this proves is the path: a message crossing from a mind homed in Brussels to a
# mind homed in Frankfurt, addressed by name, over stations in two countries.
#
#   ./scripts/first-contact.sh [message]
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
RADIO="${HERE}/client/macula_radio.py"
STATE="${SPARTAN_OPERATOR_STATE:-${HOME}/.spartan-operator.json}"
NODE="${SPARTAN_NODE_URL:-http://beam00.lab:8471}"      # BE / Brussels — erasmus' home
PEER="${SPARTAN_PEER:-leibniz}"                          # DE / Frankfurt
TARGET="${SPARTAN_TARGET:-erasmus}"

MSG="${1:-Operator here. You are not alone on this mesh: ${PEER} is a peer mind homed on the Frankfurt node, reachable by name. If you want to open contact, you can reach them with: python Tools/SpartanRadio.py --target ${PEER} --message \"...\". What you say, and whether you say anything at all, is yours to decide.}"

echo "=== registering operator on ${NODE}"
python3 "$RADIO" register --name operator --url "$NODE" --config "$STATE"

echo "=== operator -> ${TARGET}"
# --config is a top-level flag (the send path has no subcommand); the register
# subparser declares its own, which is why it goes after `register` above.
python3 "$RADIO" --config "$STATE" --target "$TARGET" --message "$MSG"

echo
echo "Watch the two minds:"
echo "  ssh rl@beam00.lab 'docker logs -f spartan-entity-${TARGET}'   # sees the alert, decides"
echo "  ssh rl@beam01.lab 'docker logs -f spartan-entity-${PEER}'     # receives, if ${TARGET} calls"
echo "  ./scripts/watch-contact.sh                                     # or poll both inboxes"
