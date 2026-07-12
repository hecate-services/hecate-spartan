#!/usr/bin/env bash
##
## Build a professional PDF from hecate-spartan documentation.
## pandoc + xelatex, scientific-style output. Model of macula's builder.
##
## Usage: bash scripts/build-docs-pdf.sh
## Output: dist/*.pdf
##
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="${REPO_ROOT}/dist"
mkdir -p "${DIST_DIR}"

PANDOC_COMMON=(
  --pdf-engine=xelatex
  -V geometry:margin=2.5cm
  -V "mainfont=DejaVu Sans"
  -V "monofont=DejaVu Sans Mono"
  -V fontsize=11pt
  -V colorlinks=true
  -V linkcolor=blue
  -V urlcolor=blue
  -V "header-includes=\usepackage{fancyhdr}\pagestyle{fancy}\fancyhead[L]{hecate-spartan}\fancyhead[R]{\leftmark}\fancyfoot[C]{\thepage}"
  --highlight-style=tango
  -V papersize=a4
  "--resource-path=${REPO_ROOT}:${REPO_ROOT}/docs"
)

build_pdf() {
  local output_name="$1" src="$2"
  if [ ! -f "${src}" ]; then echo "  [SKIP] ${src} missing"; return; fi
  echo "  Building ${output_name}.pdf from ${src} ..."
  pandoc "${PANDOC_COMMON[@]}" --toc --toc-depth=2 \
    -V toc-title="Contents" \
    -o "${DIST_DIR}/${output_name}.pdf" "${src}"
}

echo "=== hecate-spartan documentation PDF builder ==="
build_pdf "federated-spartan-mesh" "${REPO_ROOT}/docs/FEDERATED_SPARTAN_MESH.md"

echo ""
echo "Done. PDFs in ${DIST_DIR}:"
ls -la "${DIST_DIR}"/*.pdf 2>/dev/null || echo "  (none built)"
