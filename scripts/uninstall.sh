#!/bin/bash
# Remove hplip-arm64: filter, PPDs and the installer receipt.
# Usage: sudo /Library/Printers/hplip-arm64/uninstall.sh [--remove-queues]
#   --remove-queues  also delete print queues that use this driver
# Leaves any other HP software, and kexts moved by fix-hp-usb-classdriver.sh,
# untouched (restore those with: sudo fix-hp-usb-classdriver.sh --restore
# *before* uninstalling, or move them back from
# "/Library/Application Support/hplip-arm64/disabled-kexts").
set -euo pipefail

PREFIX=/Library/Printers/hplip-arm64
UI_PPD="/Library/Printers/PPDs/Contents/Resources/HP Deskjet 5900 Series hpcups arm64.ppd.gz"
PKG_ID=io.github.claxonberlin.hplip-arm64

[ "$(id -u)" = 0 ] || { echo "run with sudo" >&2; exit 1; }

for ppd in /etc/cups/ppd/*.ppd; do
    [ -e "$ppd" ] || continue
    grep -q "$PREFIX/" "$ppd" || continue
    q=$(basename "$ppd" .ppd)
    if [ "${1:-}" = --remove-queues ]; then
        echo "Removing print queue $q"; lpadmin -x "$q"
    else
        echo "warning: queue $q uses this driver; remove it with: sudo lpadmin -x $q" >&2
    fi
done

rm -f "$UI_PPD"
if [ -d "$PREFIX" ]; then echo "Removing $PREFIX"; rm -rf "$PREFIX"; fi
pkgutil --pkgs | grep -qx "$PKG_ID" && pkgutil --forget "$PKG_ID" >/dev/null
echo "Done."
