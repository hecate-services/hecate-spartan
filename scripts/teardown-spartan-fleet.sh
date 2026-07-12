#!/usr/bin/env bash
# Stop + remove the hecate-spartan node fleet from the beam boxes. Leaves the
# /bulk0/hecate/spartan data dirs in place unless --wipe is passed.
#
#   ./scripts/teardown-spartan-fleet.sh [--wipe]
set -euo pipefail

WIPE="${1:-}"
for HOST in beam00.lab beam01.lab beam02.lab beam03.lab; do
  CC=$(case "$HOST" in beam00*) echo be;; beam01*) echo de;; beam02*) echo fr;; beam03*) echo it;; esac)
  echo "=== ${HOST} (${CC}) ==="
  ssh -o BatchMode=yes "rl@${HOST}" "CC='${CC}' WIPE='${WIPE}' bash -s" <<'REMOTE'
docker rm -f "spartan-${CC}" "spartan-${CC}-1" "spartan-${CC}-2" >/dev/null 2>&1 || true
echo "  removed spartan-${CC}"
if [ "$WIPE" = "--wipe" ]; then
  docker run --rm -v "/bulk0/hecate/spartan/spartan-${CC}:/d" alpine:3.22 sh -c 'rm -rf /d/*' 2>/dev/null || true
  echo "  wiped data"
fi
REMOTE
done
