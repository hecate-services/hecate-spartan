#!/usr/bin/env bash
# Test every ~/.gemini-api-keys/.spartan-* key against the model the entities
# actually run (models/gemini-2.5-flash), before a single mind is deployed on it.
#
# A key that 429s or 403s under load looks exactly like "the entity is broken",
# so it gets checked here first, with a real generateContent call rather than a
# listModels ping (listing works on keys whose generate quota is dead).
#
# The key never reaches argv: curl reads its header from a --config file on
# stdin, so it cannot show up in `ps`, shell history, or a log line.
#
#   ./scripts/test-gemini-keys.sh
set -uo pipefail

KEYDIR="${GEMINI_KEY_DIR:-$HOME/.gemini-api-keys}"
# NOT gemini-2.5-flash: Google has closed it to new projects ("no longer
# available to new users"), so the fleet's original key can call it and a
# freshly minted one cannot. ListModels still advertises it, which is how you
# get a 404 on a model the API just told you exists. Test what you will run.
MODEL="${GEMINI_MODEL:-models/gemini-flash-latest}"
URL="https://generativelanguage.googleapis.com/v1beta/${MODEL}:generateContent"
BODY='{"contents":[{"parts":[{"text":"Reply with the single word: ready"}]}],"generationConfig":{"maxOutputTokens":512}}'

fail=0
for f in "${KEYDIR}"/.spartan-*; do
    name="$(basename "$f" | sed 's/^\.spartan-//')"

    perms="$(stat -c %a "$f")"
    [ "$perms" = "600" ] || echo "  ! ${name}: key file is ${perms}, should be 600"

    out="$(printf 'header = "x-goog-api-key: %s"\nheader = "content-type: application/json"\nurl = "%s"\ndata = %s\nsilent\nwrite-out = "\\n%%{http_code}"\n' \
             "$(tr -d '\r\n' <"$f")" "$URL" "$(printf '%s' "$BODY" | sed 's/"/\\"/g; s/^/"/; s/$/"/')" \
           | curl --config - 2>/dev/null)"

    code="$(printf '%s' "$out" | tail -1)"
    text="$(printf '%s' "$out" | python3 -c "
import sys,json
raw=sys.stdin.read().rsplit('\n',1)[0]
try:
    d=json.loads(raw)
except Exception:
    print('(no json)'); raise SystemExit
if 'error' in d:
    print(d['error'].get('status','?') + ': ' + d['error'].get('message','')[:70]); raise SystemExit
try:
    print(d['candidates'][0]['content']['parts'][0]['text'].strip()[:30])
except Exception:
    print('(empty candidate: ' + str(d.get('candidates',[{}])[0].get('finishReason','?')) + ')')
" 2>/dev/null)"

    if [ "$code" = "200" ]; then
        printf "  ok   %-10s HTTP %s  %s\n" "$name" "$code" "$text"
    else
        printf "  FAIL %-10s HTTP %s  %s\n" "$name" "$code" "$text"
        fail=1
    fi
done

echo
echo "Quota separation is NOT observable from the API: two keys in the same"
echo "Google Cloud project share one free-tier bucket and will throttle each"
echo "other. Confirm in AI Studio that each key sits in its OWN project."
exit $fail
