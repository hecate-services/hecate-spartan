#!/usr/bin/env bash
# The proof surface for first contact: what each mind's bridge actually pulled
# out of its mesh inbox, and what the registry thinks the federation looks like.
#
# alerts/ is the entity's ear: one .alert file per message the bridge delivered,
# named {sender}_{timestamp}.alert. Spartan's FileWatcher consumes them (deletes
# on read), so a file that is GONE was read by the mind -- the bridge log is the
# durable record.
#
#   ./scripts/watch-contact.sh
set -euo pipefail

MAP=(
  "beam00.lab|erasmus|BE Brussels"
  "beam00.lab|spinoza|NL Amsterdam"
  "beam01.lab|leibniz|DE Frankfurt"
  "beam01.lab|einstein|AT Vienna"
  "beam02.lab|curie|FR Paris"
  "beam02.lab|newton|ES Madrid"
  "beam03.lab|vico|IT Milan"
  "beam03.lab|fermi|PL Warsaw"
)

echo "=== registry (mesh-wide, as each node sees it)"
for entry in "${MAP[@]}"; do
  IFS='|' read -r HOST NAME LOC <<<"$entry"
  count=$(ssh -o BatchMode=yes "rl@${HOST}" \
    "docker exec spartan-entity-${NAME} python3 -c \"
import json,sys; sys.path.insert(0,'Tools')
from macula_radio import resolve_peers
cfg=json.load(open('/app/identity/.spartan_mesh.json'))
by_did,_=resolve_peers(cfg)
print(' '.join(sorted(n for n in by_did.values() if n)))\" 2>/dev/null" || echo "?")
  printf "  %-9s (%-12s) sees: %s\n" "$NAME" "$LOC" "$count"
done

echo
echo "=== inbound traffic (bridge log = what reached each mind)"
for entry in "${MAP[@]}"; do
  IFS='|' read -r HOST NAME _ <<<"$entry"
  echo "--- ${NAME}"
  ssh -o BatchMode=yes "rl@${HOST}" \
    "docker logs --tail 200 spartan-entity-${NAME} 2>&1 | grep -E 'macula_radio\] (message|broadcast|whitelisted)' | tail -5" \
    || true
done

echo
echo "=== undelivered alerts still on disk (mind has not read them yet)"
for entry in "${MAP[@]}"; do
  IFS='|' read -r HOST NAME _ <<<"$entry"
  files=$(ssh -o BatchMode=yes "rl@${HOST}" \
    "docker exec spartan-entity-${NAME} sh -c 'ls alerts/*.alert 2>/dev/null | head -5' " || true)
  printf "  %-9s %s\n" "$NAME" "${files:-(none — all consumed)}"
done
