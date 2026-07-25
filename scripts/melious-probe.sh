#!/usr/bin/env bash
##
## Provider behaviour probe for the Melious backend used by spartan_mind_llm.
##
## Re-measures the provider assumptions this repo depends on, so they can be
## checked against production rather than carried forward from memory:
##   A. Is the model pool what we think it is, and is qwen3.5-9b still served?
##   B. Does an identical prompt get a cache discount on the second call?
##      (Sent ABOVE the usual provider caching threshold, so a zero result
##       cannot be dismissed as "the prompt was too short to cache".)
##   C. Does a valid OpenAI-format tool schema get accepted, and how often?
##   D. The same, for the richer multi-tool schema a resident mind actually
##      sends, since a one-argument function is not a fair proxy for it.
##
## The API key is loaded into a 0600 curl config file, never into argv and
## never into output. Raw responses are written under dist/ which is ignored.
##
## Usage: bash scripts/melious-probe.sh [attempts]
## Cost:  well under one cent at qwen3.5-9b rates.
##
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="${REPO_ROOT}/dist/melious-probe"
KEY_FILE="${HOME}/.melious-api-keys/.beamologist-2026-07-14"
BASE_URL="https://api.melious.ai/v1"
MODEL="qwen3.5-9b"
TOOL_ATTEMPTS="${1:-8}"
FILLER_SENTENCES=340

for tool in curl jq; do
  command -v "${tool}" >/dev/null 2>&1 || { echo "ERROR: ${tool} not found" >&2; exit 1; }
done
[ -f "${KEY_FILE}" ] || { echo "ERROR: key file missing: ${KEY_FILE}" >&2; exit 1; }

WORK_DIR="$(mktemp -d)"
chmod 700 "${WORK_DIR}"
trap 'rm -rf "${WORK_DIR}"' EXIT
mkdir -p "${OUT_DIR}"

# auth via curl config so the token never reaches argv or the process table
CURL_CFG="${WORK_DIR}/auth.conf"
umask 077
{
  printf 'header = "Authorization: Bearer %s"\n' "$(tr -d '\r\n' < "${KEY_FILE}")"
  printf 'header = "Content-Type: application/json"\n'
  printf 'silent\n'
} > "${CURL_CFG}"
chmod 600 "${CURL_CFG}"

call() {
  ## call <endpoint> <payload-file|-> <out-body> <out-meta>
  local endpoint="$1" payload="$2" body="$3" meta="$4"
  if [ "${payload}" = "-" ]; then
    curl --config "${CURL_CFG}" \
      -o "${body}" -w '%{http_code} %{time_total}\n' \
      "${BASE_URL}${endpoint}" > "${meta}" 2>/dev/null || true
  else
    curl --config "${CURL_CFG}" \
      -X POST --data-binary "@${payload}" \
      -o "${body}" -w '%{http_code} %{time_total}\n' \
      "${BASE_URL}${endpoint}" > "${meta}" 2>/dev/null || true
  fi
}

echo "=== Melious probe · $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="
echo "endpoint ${BASE_URL}  model ${MODEL}"
echo ""

## ---------------------------------------------------------------- A. pool

echo "A. Model pool"
call "/models" "-" "${OUT_DIR}/a-models.json" "${WORK_DIR}/a.meta"
read -r A_CODE A_TIME < "${WORK_DIR}/a.meta"
echo "   GET /models -> HTTP ${A_CODE} in ${A_TIME}s"
if [ "${A_CODE}" = "200" ]; then
  MODEL_COUNT="$(jq -r '(.data // []) | length' "${OUT_DIR}/a-models.json" 2>/dev/null || echo "?")"
  echo "   models advertised: ${MODEL_COUNT}"
  if jq -e --arg m "${MODEL}" '(.data // []) | any(.id == $m)' "${OUT_DIR}/a-models.json" >/dev/null 2>&1; then
    echo "   ${MODEL}: PRESENT"
  else
    echo "   ${MODEL}: ABSENT from the advertised list"
  fi
else
  echo "   body: $(head -c 300 "${OUT_DIR}/a-models.json")"
fi
echo ""

## ------------------------------------------------------- B. cache discount

echo "B. Prompt cache on a byte-identical repeat"

FILLER="${WORK_DIR}/filler.txt"
: > "${FILLER}"
i=0
while [ "${i}" -lt "${FILLER_SENTENCES}" ]; do
  printf 'Routing note %04d: the broker forwards each request to one of several European providers, and the serving node retains a key-value cache for the prefix it has already processed.\n' "${i}" >> "${FILLER}"
  i=$((i + 1))
done

PAYLOAD="${WORK_DIR}/cache-payload.json"
jq -n --rawfile sys "${FILLER}" --arg model "${MODEL}" '{
  model: $model,
  messages: [
    {role: "system", content: $sys},
    {role: "user", content: "Reply with exactly the word OK."}
  ],
  max_tokens: 5,
  temperature: 0
}' > "${PAYLOAD}"

echo "   payload $(command wc -c < "${PAYLOAD}") bytes, identical for both calls"

call "/chat/completions" "${PAYLOAD}" "${OUT_DIR}/b1-first.json" "${WORK_DIR}/b1.meta"
read -r B1_CODE B1_TIME < "${WORK_DIR}/b1.meta"
sleep 2
call "/chat/completions" "${PAYLOAD}" "${OUT_DIR}/b2-repeat.json" "${WORK_DIR}/b2.meta"
read -r B2_CODE B2_TIME < "${WORK_DIR}/b2.meta"

report_usage() {
  ## report_usage <label> <file> <http> <time>
  local label="$1" file="$2" code="$3" t="$4"
  echo "   ${label}: HTTP ${code} in ${t}s"
  if [ "${code}" != "200" ]; then
    echo "      body: $(head -c 400 "${file}")"
    return
  fi
  jq -r '
    def g(p): (p // "-");
    "      prompt_tokens   " + (g(.usage.prompt_tokens)|tostring) +
    "\n      cached_tokens   " + (g(.usage.prompt_tokens_details.cached_tokens // .usage.cached_tokens)|tostring) +
    "\n      completion      " + (g(.usage.completion_tokens)|tostring)
  ' "${file}" 2>/dev/null || echo "      (could not parse usage)"
  echo "      full usage object + any non-standard top-level keys:"
  jq -c '{usage: .usage} + (with_entries(select(.key | IN("id","object","created","model","choices","usage") | not)))' \
    "${file}" 2>/dev/null | sed 's/^/        /' || true
}

report_usage "call 1 (cold)" "${OUT_DIR}/b1-first.json" "${B1_CODE}" "${B1_TIME}"
report_usage "call 2 (repeat)" "${OUT_DIR}/b2-repeat.json" "${B2_CODE}" "${B2_TIME}"
echo ""

## --------------------------------------------------------- C. tool calling

echo "C. Tool calling on a valid OpenAI-format schema (${TOOL_ATTEMPTS} attempts)"

TOOL_PAYLOAD="${WORK_DIR}/tool-payload.json"
jq -n --arg model "${MODEL}" '{
  model: $model,
  messages: [{role: "user", content: "What is the weather in Brussels? Use the tool."}],
  tools: [{
    type: "function",
    function: {
      name: "get_weather",
      description: "Get the current weather for a city",
      parameters: {
        type: "object",
        properties: { city: {type: "string", description: "City name"} },
        required: ["city"]
      }
    }
  }],
  tool_choice: "auto",
  max_tokens: 128,
  temperature: 0
}' > "${TOOL_PAYLOAD}"

TOOL_OK=0; TOOL_400=0; TOOL_OTHER=0; TOOL_CALLED=0
: > "${OUT_DIR}/c-tool-attempts.txt"

n=1
while [ "${n}" -le "${TOOL_ATTEMPTS}" ]; do
  body="${WORK_DIR}/c-${n}.json"
  call "/chat/completions" "${TOOL_PAYLOAD}" "${body}" "${WORK_DIR}/c.meta"
  read -r C_CODE C_TIME < "${WORK_DIR}/c.meta"

  emitted="no"
  if [ "${C_CODE}" = "200" ]; then
    TOOL_OK=$((TOOL_OK + 1))
    if jq -e '.choices[0].message.tool_calls | length > 0' "${body}" >/dev/null 2>&1; then
      emitted="yes"; TOOL_CALLED=$((TOOL_CALLED + 1))
    fi
    detail=""
  elif [ "${C_CODE}" = "400" ]; then
    TOOL_400=$((TOOL_400 + 1))
    detail=" | $(jq -r '(.error.message // .message // "")' "${body}" 2>/dev/null | head -c 160)"
  else
    TOOL_OTHER=$((TOOL_OTHER + 1))
    detail=" | $(jq -r '(.error.message // .message // "")' "${body}" 2>/dev/null | head -c 160)"
  fi

  printf 'attempt %02d  HTTP %s  %ss  tool_call=%s%s\n' \
    "${n}" "${C_CODE}" "${C_TIME}" "${emitted}" "${detail}" \
    | tee -a "${OUT_DIR}/c-tool-attempts.txt"

  cp "${body}" "${OUT_DIR}/c-${n}.json" 2>/dev/null || true
  n=$((n + 1))
  sleep 1
done

echo ""
echo "   HTTP 200        ${TOOL_OK}/${TOOL_ATTEMPTS}"
echo "   HTTP 400        ${TOOL_400}/${TOOL_ATTEMPTS}"
echo "   other status    ${TOOL_OTHER}/${TOOL_ATTEMPTS}"
echo "   emitted a tool_call  ${TOOL_CALLED}/${TOOL_ATTEMPTS}"
echo ""

## ------------------------------------------- D. tool calling, rich schema
##
## A resident mind sends its whole tool set, not a single one-argument
## function, so C passing does not clear the endpoint on its own. This
## repeats C with the shape a mind actually sends: several tools, an enum,
## a nested object, an array, multiple required fields.

echo "D. Tool calling on a RICH multi-tool schema (${TOOL_ATTEMPTS} attempts)"

RICH_PAYLOAD="${WORK_DIR}/rich-payload.json"
jq -n --arg model "${MODEL}" '{
  model: $model,
  messages: [{role: "user", content: "Record the lesson that prefix caching matters, then speak one sentence about it."}],
  tools: [
    {type:"function", function:{name:"speak", description:"Say something to the society",
      parameters:{type:"object", properties:{
        text:{type:"string", description:"What to say"},
        audience:{type:"string", enum:["society","peer","self"], description:"Who hears it"}
      }, required:["text","audience"]}}},
    {type:"function", function:{name:"record_lesson", description:"Record a durable lesson",
      parameters:{type:"object", properties:{
        lesson:{type:"string"},
        tags:{type:"array", items:{type:"string"}},
        confidence:{type:"number", minimum:0, maximum:1},
        provenance:{type:"object", properties:{
          source:{type:"string"}, observed_at:{type:"string"}
        }, required:["source"]}
      }, required:["lesson","tags","confidence"]}}},
    {type:"function", function:{name:"amend_charter", description:"Amend the charter",
      parameters:{type:"object", properties:{
        clause:{type:"string"}, rationale:{type:"string"},
        action:{type:"string", enum:["add","revise","retire"]}
      }, required:["clause","action"]}}},
    {type:"function", function:{name:"revise_working_memory", description:"Rewrite working memory",
      parameters:{type:"object", properties:{
        contents:{type:"string"}, reason:{type:"string"}
      }, required:["contents"]}}}
  ],
  tool_choice: "auto",
  max_tokens: 256,
  temperature: 0
}' > "${RICH_PAYLOAD}"

echo "   4 tools, enum + nested object + array, $(command wc -c < "${RICH_PAYLOAD}") bytes"

RICH_OK=0; RICH_400=0; RICH_OTHER=0; RICH_CALLED=0
: > "${OUT_DIR}/d-rich-attempts.txt"

n=1
while [ "${n}" -le "${TOOL_ATTEMPTS}" ]; do
  body="${WORK_DIR}/d-${n}.json"
  call "/chat/completions" "${RICH_PAYLOAD}" "${body}" "${WORK_DIR}/d.meta"
  read -r D_CODE D_TIME < "${WORK_DIR}/d.meta"

  emitted="no"
  if [ "${D_CODE}" = "200" ]; then
    RICH_OK=$((RICH_OK + 1))
    if jq -e '.choices[0].message.tool_calls | length > 0' "${body}" >/dev/null 2>&1; then
      emitted="yes"; RICH_CALLED=$((RICH_CALLED + 1))
    fi
    detail=""
  elif [ "${D_CODE}" = "400" ]; then
    RICH_400=$((RICH_400 + 1))
    detail=" | $(jq -r '(.error.message // .message // "")' "${body}" 2>/dev/null | head -c 160)"
  else
    RICH_OTHER=$((RICH_OTHER + 1))
    detail=" | $(jq -r '(.error.message // .message // "")' "${body}" 2>/dev/null | head -c 160)"
  fi

  printf 'attempt %02d  HTTP %s  %ss  tool_call=%s%s\n' \
    "${n}" "${D_CODE}" "${D_TIME}" "${emitted}" "${detail}" \
    | tee -a "${OUT_DIR}/d-rich-attempts.txt"

  cp "${body}" "${OUT_DIR}/d-${n}.json" 2>/dev/null || true
  n=$((n + 1))
  sleep 1
done

echo ""
echo "   HTTP 200        ${RICH_OK}/${TOOL_ATTEMPTS}"
echo "   HTTP 400        ${RICH_400}/${TOOL_ATTEMPTS}"
echo "   other status    ${RICH_OTHER}/${TOOL_ATTEMPTS}"
echo "   emitted a tool_call  ${RICH_CALLED}/${TOOL_ATTEMPTS}"
echo ""
echo "Raw responses in ${OUT_DIR}"
