#!/bin/bash
# Created: 2026-11-25 22:45
#
# Installs the CM2320MfpClaude driver and adds a print queue.
#
# Installs:
#   /Library/Printers/CM2320MfpClaude/filter/cm2320claude-prefilter
#   /Library/Printers/PPDs/Contents/Resources/CM2320MfpClaude.ppd.gz
# Adds queue "CM2320MfpClaude" (existing queues are not changed).
#
# Build first:  ./scripts/build.sh
# Usage:        sudo ./scripts/install_cm2320mfpclaude.sh [device-uri]
# Without a device URI, the URI of an existing queue for a CM2320 is reused.
# Find URIs with:  lpinfo -v   (for example socket://192.168.1.50:9100)
#
# Environment (optional): TRAY3=True|False (default True), DUPLEXER=True|False
# (default True), PAGESIZE=A4|Letter|... (default A4), QUEUE=name.

set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: run this script with sudo." >&2
    exit 1
fi

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FILTER_SRC="${REPO_DIR}/work/build/cm2320claude-prefilter"
PPD_SRC="${REPO_DIR}/ppd/CM2320MfpClaude.ppd"
FILTER_DIR="/Library/Printers/CM2320MfpClaude/filter"
PPD_DST="/Library/Printers/PPDs/Contents/Resources/CM2320MfpClaude.ppd.gz"
QUEUE="${QUEUE:-CM2320MfpClaude}"

if [ ! -x "${FILTER_SRC}" ]; then
    echo "ERROR: ${FILTER_SRC} not found. Run ./scripts/build.sh first (without sudo)." >&2
    exit 1
fi

DEVICE_URI="${1:-}"
if [ -z "${DEVICE_URI}" ]; then
    DEVICE_URI="$(lpstat -v 2>/dev/null | grep -i "CM2320" | grep -v "${QUEUE}:" | head -1 | sed 's/^device for [^:]*: //')"
fi
if [ -z "${DEVICE_URI}" ]; then
    echo "ERROR: no device URI given and no existing CM2320 queue found." >&2
    echo "       Run 'lpinfo -v' and pass the printer's URI as argument." >&2
    exit 1
fi
echo "Device URI: ${DEVICE_URI}"

set -x
install -d -o root -g wheel -m 755 "${FILTER_DIR}"
install -o root -g wheel -m 755 "${FILTER_SRC}" "${FILTER_DIR}/cm2320claude-prefilter"
xattr -c "${FILTER_DIR}/cm2320claude-prefilter" 2>/dev/null || true
install -d -o root -g wheel -m 755 "$(dirname "${PPD_DST}")"
gzip -c "${PPD_SRC}" > "${PPD_DST}"
chown root:wheel "${PPD_DST}"
chmod 644 "${PPD_DST}"

lpadmin -p "${QUEUE}" -E \
    -v "${DEVICE_URI}" \
    -P "${PPD_DST}" \
    -D "HP Color LaserJet CM2320 MFP (CM2320MfpClaude)" \
    -o OptionDuplexer="${DUPLEXER:-True}" \
    -o OptionTray3="${TRAY3:-True}" \
    -o PageSize="${PAGESIZE:-A4}" \
    -o printer-is-shared=false
set +x

echo
echo "Installed queue ${QUEUE}. Main options:"
lpoptions -p "${QUEUE}" -l | grep -E "^(PageSize|InputSlot|Duplex|ColorModel|CMBooklet|CMLetterhead|CMRotate180|CMWmText|OptionTray3|OptionDuplexer)/" | cut -c1-120
