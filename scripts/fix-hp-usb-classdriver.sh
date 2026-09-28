#!/bin/bash
# Detect and (optionally) fix "Unable to use legacy USB class driver."
#
# Old HP driver installs leave codeless kexts in /Library/Extensions whose
# IOKit personalities tag HP USB printers with
#   "USB Printing Class" = .../HPIOPrinterClassDriver.plugin
# That plugin is i386/x86_64 only, so Apple's usb backend cannot use it on
# Apple silicon and the queue pauses. Moving the matching kexts aside (and
# rebooting) makes the backend use Apple's own USB printer class driver.
#
#   fix-hp-usb-classdriver.sh            check only (no changes, no sudo)
#   sudo fix-hp-usb-classdriver.sh --fix     move matching kexts to the backup folder
#   sudo fix-hp-usb-classdriver.sh --restore move them back
# A reboot is needed after --fix or --restore.
set -euo pipefail

BK="/Library/Application Support/hplip-arm64/disabled-kexts"
MODE="${1:-check}"

# VID:PID of connected USB devices that currently carry an HP class driver tag.
tagged() {
    ioreg -r -c IOUSBHostInterface -l -w0 2>/dev/null | awk '
        /"idVendor" =/  {v=$NF}
        /"idProduct" =/ {p=$NF}
        /"USB Printing Class" = ".*HPIOPrinterClassDriver/ {print v":"p}' | sort -u
}

# Kexts in /Library/Extensions with a personality matching VID:PID that sets
# a USB Printing Class.
kexts_for() {
    local vid=${1%:*} pid=${1#*:} k
    for k in /Library/Extensions/*.kext; do
        [ -f "$k/Contents/Info.plist" ] || continue
        plutil -convert json -o - "$k/Contents/Info.plist" 2>/dev/null |
        /usr/bin/python3 -c '
import json, sys
vid, pid = int(sys.argv[1]), int(sys.argv[2])
d = json.load(sys.stdin)
for p in d.get("IOKitPersonalities", {}).values():
    if p.get("idVendor") == vid and p.get("idProduct") == pid and \
       "USB Printing Class" in p.get("IOProviderMergeProperties", {}):
        sys.exit(0)
sys.exit(1)' "$vid" "$pid" && echo "$k"
    done
}

case "$MODE" in
check|--check)
    t=$(tagged)
    if [ -z "$t" ]; then
        echo "OK: no connected USB printer is tagged with HP's legacy class driver."
        exit 0
    fi
    for id in $t; do
        echo "Affected USB printer $id; matching kexts:"
        kexts_for "$id" | sed 's/^/  /'
    done
    echo
    echo "Fix with: sudo $0 --fix   (then reboot)"
    exit 1 ;;
--fix)
    [ "$(id -u)" = 0 ] || { echo "run with sudo" >&2; exit 1; }
    t=$(tagged)
    [ -n "$t" ] || { echo "Nothing to fix."; exit 0; }
    mkdir -p "$BK"
    for id in $t; do
        for k in $(kexts_for "$id"); do
            echo "Moving $k -> $BK/"
            mv "$k" "$BK/"
        done
    done
    echo "Done. Reboot, then print again. Undo with: sudo $0 --restore" ;;
--restore)
    [ "$(id -u)" = 0 ] || { echo "run with sudo" >&2; exit 1; }
    [ -d "$BK" ] || { echo "No backup at $BK"; exit 0; }
    for k in "$BK"/*.kext; do
        [ -e "$k" ] || continue
        n=$(basename "$k")
        if [ -e "/Library/Extensions/$n" ]; then echo "skip $n (already present)"
        else echo "Restoring $n"; mv "$k" /Library/Extensions/; fi
    done
    rmdir "$BK" 2>/dev/null || true
    echo "Done. Reboot to reload the kexts." ;;
*)
    echo "usage: $0 [--check|--fix|--restore]" >&2; exit 2 ;;
esac
