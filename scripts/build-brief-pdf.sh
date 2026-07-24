#!/usr/bin/env bash
##
## Render a designed HTML brief to PDF, preserving its own stylesheet.
##
## The source pages under docs/ are Artifact fragments: they carry <title>,
## <style> and content, but no <!doctype>/<html>/<head>/<body> (the Artifact
## host supplies those). This wraps the fragment into a standalone document
## and drives headless Chrome, so the printed result matches the page the
## reader sees. Print rules live in the page itself, not here.
##
## Usage: bash scripts/build-brief-pdf.sh [name ...]
##        name = docs/<name>.html, default melious-meeting-brief
## Output: dist/<name>.pdf
##
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DOCS_DIR="${REPO_ROOT}/docs"
DIST_DIR="${REPO_ROOT}/dist"

BROWSER=""
for candidate in google-chrome-stable google-chrome chromium chromium-browser; do
  if command -v "${candidate}" >/dev/null 2>&1; then BROWSER="${candidate}"; break; fi
done
if [ -z "${BROWSER}" ]; then
  echo "ERROR: no Chrome/Chromium found; cannot render." >&2
  exit 1
fi

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT

mkdir -p "${DIST_DIR}"

build_one() {
  local name="$1"
  local src="${DOCS_DIR}/${name}.html"
  local wrapped="${WORK_DIR}/${name}.html"
  local out="${DIST_DIR}/${name}.pdf"

  if [ ! -f "${src}" ]; then
    echo "  [SKIP] ${src} missing"
    return
  fi

  echo "  Rendering ${name}.pdf from docs/${name}.html ..."

  {
    printf '%s\n' '<!doctype html>'
    printf '%s\n' '<html lang="en">'
    printf '%s\n' '<head>'
    printf '%s\n' '<meta charset="utf-8">'
    printf '%s\n' '<meta name="viewport" content="width=device-width, initial-scale=1">'
    printf '%s\n' '<style>*,*::before,*::after{box-sizing:border-box}'
    printf '%s\n' 'body,h1,h2,h3,p,ol,ul,table,figure{margin:0;padding:0}'
    printf '%s\n' 'img{max-width:100%}</style>'
    printf '%s\n' '</head>'
    printf '%s\n' '<body>'
    cat "${src}"
    printf '%s\n' '</body></html>'
  } > "${wrapped}"

  "${BROWSER}" \
    --headless=new \
    --disable-gpu \
    --user-data-dir="${WORK_DIR}/profile-${name}" \
    --virtual-time-budget=4000 \
    --no-pdf-header-footer \
    --print-to-pdf-no-header \
    --print-to-pdf="${out}" \
    "file://${wrapped}" 2>/dev/null

  if [ ! -s "${out}" ]; then
    echo "  ERROR: ${out} was not produced" >&2
    return 1
  fi
}

echo "=== hecate-spartan brief PDF builder (${BROWSER}) ==="

if [ "$#" -gt 0 ]; then
  for name in "$@"; do build_one "${name}"; done
else
  build_one "melious-meeting-brief"
fi

echo ""
echo "Done. PDFs in ${DIST_DIR}:"
ls -la "${DIST_DIR}"/*.pdf 2>/dev/null || echo "  (none built)"
