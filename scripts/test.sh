#!/bin/bash
# Created: 2026-11-25 22:33
#
# Runs the CM2320MfpClaude tests with code coverage:
#   1. unit tests (tests/CoreTests.swift + src/CM2320Core.swift)
#   2. integration tests of the filter binary (src/*.swift), as CUPS calls it
#   3. PPD check with cupstestppd
# Prints a line-coverage report for src/. Fails when a test fails or when
# coverage of src/ is below 80 %.
# Usage: ./scripts/test.sh

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${REPO_DIR}/work/testbuild"
rm -rf "${OUT}"
mkdir -p "${OUT}/profiles"
PROF_FLAGS=(-profile-generate -profile-coverage-mapping -swift-version 5 -Onone)
PPD="${REPO_DIR}/ppd/CM2320MfpClaude.ppd"

echo "== Build (instrumented)"
swiftc "${PROF_FLAGS[@]}" -parse-as-library "${REPO_DIR}/src/CM2320Core.swift" "${REPO_DIR}/tests/CoreTests.swift" -o "${OUT}/coretests"
swiftc "${PROF_FLAGS[@]}" "${REPO_DIR}/src/CM2320Core.swift" "${REPO_DIR}/src/main.swift" -o "${OUT}/prefilter"

echo "== Unit tests"
LLVM_PROFILE_FILE="${OUT}/profiles/unit.profraw" "${OUT}/coretests" "${PPD}" "${OUT}/sample.pdf"

echo "== Integration tests (filter binary)"
FAIL=0
pages() { perl -0777 -ne 'my $n = () = /\/Type\s*\/Page[^s]/g; print $n' "$1"; }
run() {
    # run <name> <expected-exit> <expected-pages or -> <options> [stdin|file]
    local name="$1" want_exit="$2" want_pages="$3" opts="$4" mode="${5:-file}"
    local code=0
    if [ "${mode}" = "stdin" ]; then
        PPD="${PPD}" LLVM_PROFILE_FILE="${OUT}/profiles/${name}.profraw" \
            "${OUT}/prefilter" 1 user title 1 "${opts}" < "${OUT}/sample.pdf" > "${OUT}/${name}.pdf" 2> "${OUT}/${name}.log" || code=$?
    elif [ "${mode}" = "usage" ]; then
        LLVM_PROFILE_FILE="${OUT}/profiles/${name}.profraw" "${OUT}/prefilter" 1 2> "${OUT}/${name}.log" || code=$?
    elif [ "${mode}" = "missing" ]; then
        LLVM_PROFILE_FILE="${OUT}/profiles/${name}.profraw" "${OUT}/prefilter" 1 u t 1 "" /nonexistent.pdf 2> "${OUT}/${name}.log" || code=$?
    elif [ "${mode}" = "notpdf" ]; then
        PPD="${PPD}" LLVM_PROFILE_FILE="${OUT}/profiles/${name}.profraw" \
            "${OUT}/prefilter" 1 u t 1 "${opts}" "${PPD}" > "${OUT}/${name}.out" 2> "${OUT}/${name}.log" || code=$?
    else
        PPD="${PPD}" LLVM_PROFILE_FILE="${OUT}/profiles/${name}.profraw" \
            "${OUT}/prefilter" 1 user title 1 "${opts}" "${OUT}/sample.pdf" > "${OUT}/${name}.pdf" 2> "${OUT}/${name}.log" || code=$?
    fi
    local got_pages="-"
    if [ "${want_pages}" != "-" ]; then got_pages="$(pages "${OUT}/${name}.pdf")"; fi
    if [ "${code}" = "${want_exit}" ] && [ "${got_pages}" = "${want_pages}" ]; then
        echo "PASS ${name}"
    else
        echo "FAIL ${name}: exit ${code} (want ${want_exit}), pages ${got_pages} (want ${want_pages})"
        FAIL=1
    fi
}
run passthrough   0 6  ""
run booklet       0 4  "CMBooklet=LeftBinding PageSize=A4"
run booklet_stdin 0 4  "CMBooklet=RightBinding" stdin
run letterhead    0 12 "CMLetterhead=True Duplex=None"
run lh_duplex     0 6  "CMLetterhead=True Duplex=DuplexNoTumble"
run watermark     0 6  "CMWmText=Confidential CMWmIntensity=Light"
run rotate        0 6  "CMRotate180=True"
run usage         1 -  "" usage
run missing       1 -  "" missing
run notpdf        0 -  "CMRotate180=True" notpdf
if ! cmp -s "${OUT}/sample.pdf" "${OUT}/passthrough.pdf"; then echo "FAIL passthrough is not byte-identical"; FAIL=1; fi
if ! cmp -s "${PPD}" "${OUT}/notpdf.out"; then echo "FAIL non-PDF input not passed through"; FAIL=1; fi

echo "== PPD check"
cupstestppd -W all "${PPD}" | head -1 | grep -q PASS && echo "PASS cupstestppd" || { echo "FAIL cupstestppd"; FAIL=1; }

echo "== Coverage (src/)"
xcrun llvm-profdata merge -o "${OUT}/merged.profdata" "${OUT}/profiles/"*.profraw
xcrun llvm-cov report "${OUT}/prefilter" -object "${OUT}/coretests" -instr-profile "${OUT}/merged.profdata" \
    "${REPO_DIR}/src/CM2320Core.swift" "${REPO_DIR}/src/main.swift" | tee "${OUT}/coverage.txt"
TOTAL="$(awk '/^TOTAL/ {print $(NF-3)}' "${OUT}/coverage.txt" | tr -d '%')"
echo "Line coverage of src/: ${TOTAL}%"
if [ "$(echo "${TOTAL} < 80" | bc -l)" = "1" ]; then echo "FAIL coverage below 80%"; FAIL=1; fi

exit ${FAIL}
