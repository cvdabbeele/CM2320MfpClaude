#!/bin/bash
# Created: 2026-11-25 22:46
#
# Removes the CM2320MfpClaude queue, PPD and pre-filter.
# Usage: sudo ./scripts/uninstall_cm2320mfpclaude.sh [queue-name]

set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: run this script with sudo." >&2
    exit 1
fi

QUEUE="${1:-CM2320MfpClaude}"
set -x
lpadmin -x "${QUEUE}" 2>/dev/null || echo "Queue ${QUEUE} not found"
rm -f "/Library/Printers/PPDs/Contents/Resources/CM2320MfpClaude.ppd.gz"
rm -rf "/Library/Printers/CM2320MfpClaude"
