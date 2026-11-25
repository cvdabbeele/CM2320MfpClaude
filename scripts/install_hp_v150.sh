#!/bin/bash
# Created: 2026-11-25 22:09
#
# Install the PostScript driver parts of HP's macOS package
# "HP CLJ CM2320 MFP series v1.5.0" by hand, and add a new print queue.
#
# Why by hand: HP's installer scripts only accept macOS 10.x
# (InstallationCheck: SYSTEM_MAJOR_VERSION -eq 10), so on macOS 11 and later
# the PostScript driver and PPD sub-packages are skipped. The driver itself
# (hpPostProcessing filter, x86_64) still runs on Intel Macs with macOS 26.
#
# Installs:
#   /Library/Printers/hp/filter/hpPostProcessing.bundle   (CUPS filter)
#   /Library/Printers/hp/Profiles/{sRGB,CMYK,Gray}_A.icc  (colour profiles)
#   /Library/Printers/hp/Icons/HP Color LaserJet CM2320 MFP Series.icns
#   /Library/Printers/PPDs/Contents/Resources/HP Color LaserJet CM2320 MFP Series.gz
# Not installed: the print dialog plugin (hpPostScriptPDE), scan, fax
# (fax backend is ppc/i386 only), HP Director and other utilities.
#
# Adds queue HP_CM2320fxi_HPv150. Existing queues are not changed.
#
# Source files: the unpacked installer under work/expand15 (see CM2320Claude.md).
# Usage: sudo ./scripts/install_hp_v150.sh [device-uri]

set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: run this script with sudo." >&2
    exit 1
fi

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${REPO_DIR}/work/expand15"

FILTER_SRC="${SRC}/hpPSDriver/Library/Printers/hp/filter/hpPostProcessing.bundle"
PROFILES_SRC="${SRC}/profiles/Library/Printers/hp/Profiles"
ICON_SRC="${SRC}/icons/Library/Printers/hp/Icons/HP Color LaserJet CM2320 MFP Series.icns"
PPD_SRC="${SRC}/ppd/HP_Color_LaserJet_CM2320_MFP_Series.ppd"

HP_DIR="/Library/Printers/hp"
PPD_DST="/Library/Printers/PPDs/Contents/Resources/HP Color LaserJet CM2320 MFP Series.gz"

QUEUE="HP_CM2320fxi_HPv150"

# Device URI: first argument, else the URI of an existing CM2320 queue.
DEVICE_URI="${1:-}"
if [ -z "${DEVICE_URI}" ]; then
    DEVICE_URI="$(lpstat -v 2>/dev/null | grep -i "CM2320" | grep -v "${QUEUE}:" | head -1 | sed 's/^device for [^:]*: //')"
fi
if [ -z "${DEVICE_URI}" ]; then
    echo "ERROR: no device URI given and no existing CM2320 queue found." >&2
    echo "       Run 'lpinfo -v' and pass the printer's URI as argument." >&2
    exit 1
fi

for f in "${FILTER_SRC}" "${PROFILES_SRC}" "${ICON_SRC}" "${PPD_SRC}"; do
    if [ ! -e "${f}" ]; then
        echo "ERROR: source not found: ${f}" >&2
        exit 1
    fi
done

set -x

# 1. Filter, profiles, icon
install -d -o root -g wheel -m 755 "${HP_DIR}" "${HP_DIR}/filter" "${HP_DIR}/Profiles" "${HP_DIR}/Icons"
rm -rf "${HP_DIR}/filter/hpPostProcessing.bundle"
ditto "${FILTER_SRC}" "${HP_DIR}/filter/hpPostProcessing.bundle"
install -o root -g wheel -m 644 "${PROFILES_SRC}/"*.icc "${HP_DIR}/Profiles/"
install -o root -g wheel -m 644 "${ICON_SRC}" "${HP_DIR}/Icons/"

# CUPS refuses filters that are not owned by root or are group/world writable.
chown -R root:wheel "${HP_DIR}/filter/hpPostProcessing.bundle"
chmod -R go-w "${HP_DIR}/filter/hpPostProcessing.bundle"
chmod 755 "${HP_DIR}/filter/hpPostProcessing.bundle/Contents/MacOS/"*
xattr -dr com.apple.quarantine "${HP_DIR}" 2>/dev/null || true

# 2. PPD (stored gzipped, like HP's installer does)
install -d -o root -g wheel -m 755 "$(dirname "${PPD_DST}")"
gzip -c "${PPD_SRC}" > "${PPD_DST}"
chown root:wheel "${PPD_DST}"
chmod 644 "${PPD_DST}"

# 3. New queue: duplex unit and 500-sheet Tray 3 installed, A4 default
lpadmin -p "${QUEUE}" -E \
    -v "${DEVICE_URI}" \
    -P "${PPD_DST}" \
    -D "HP Color LaserJet CM2320fxi MFP (HP v1.5.0 driver)" \
    -o HPOption_Duplexer=True \
    -o HPOption_500_Sheet_Feeder_Tray3=True \
    -o PageSize=A4 \
    -o printer-is-shared=false

set +x
echo
echo "Installed. Queue options:"
lpoptions -p "${QUEUE}" -l | grep -E "^(PageSize|InputSlot|Duplex|HPOption_Duplexer|HPOption_500_Sheet_Feeder_Tray3)/"
