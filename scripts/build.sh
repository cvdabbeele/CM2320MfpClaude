#!/bin/bash
# Created: 2026-11-25 22:28
#
# Builds the CM2320MfpClaude pre-filter as a universal binary (x86_64 + arm64)
# into work/build/cm2320claude-prefilter.
# Usage: ./scripts/build.sh

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${REPO_DIR}/work/build"
mkdir -p "${OUT}"

for arch in x86_64 arm64; do
    swiftc -O -swift-version 5 -target "${arch}-apple-macos12" \
        "${REPO_DIR}/src/CM2320Core.swift" "${REPO_DIR}/src/main.swift" \
        -o "${OUT}/cm2320claude-prefilter-${arch}"
done
lipo -create "${OUT}/cm2320claude-prefilter-x86_64" "${OUT}/cm2320claude-prefilter-arm64" \
    -output "${OUT}/cm2320claude-prefilter"
rm -f "${OUT}/cm2320claude-prefilter-x86_64" "${OUT}/cm2320claude-prefilter-arm64"
echo "Built ${OUT}/cm2320claude-prefilter ($(lipo -archs "${OUT}/cm2320claude-prefilter"))"
