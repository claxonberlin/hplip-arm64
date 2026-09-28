#!/bin/bash
# Package ./dist into an installer: out/hplip-arm64-<version>.pkg
# Usage: pkg/make-pkg.sh <version>        (run ./build.sh first)
# Optional: SIGN_ID="Developer ID Installer: …" to sign the product archive.
set -euo pipefail
export COPYFILE_DISABLE=1   # no AppleDouble ._ files in the payload

VERSION="${1:?usage: $0 <version>}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
PKG_ID=io.github.claxonberlin.hplip-arm64
WORK="$HERE/build/pkg"
OUT="$HERE/out"

[ -x "$HERE/dist/filter/hpcups" ] || { echo "run ./build.sh first" >&2; exit 1; }

rm -rf "$WORK"; mkdir -p "$WORK/root/filter" "$WORK/root/ppd" "$WORK/scripts" "$OUT"

# Payload -> /Library/Printers/hplip-arm64
cp "$HERE/dist/filter/hpcups" "$WORK/root/filter/"
cp "$HERE/dist/ppd/"*.ppd "$WORK/root/ppd/"
cp "$HERE/scripts/uninstall.sh" "$HERE/scripts/fix-hp-usb-classdriver.sh" "$WORK/root/"
cp "$HERE/README.md" "$HERE/LICENSE" "$HERE/NOTICE" "$WORK/root/"
chmod 755 "$WORK/root" "$WORK/root/filter" "$WORK/root/ppd" \
          "$WORK/root/filter/hpcups" "$WORK/root/uninstall.sh" "$WORK/root/fix-hp-usb-classdriver.sh"
chmod 644 "$WORK/root/ppd/"*.ppd "$WORK/root/README.md" "$WORK/root/LICENSE" "$WORK/root/NOTICE"
xattr -cr "$WORK/root"

cp "$HERE/pkg/postinstall" "$WORK/scripts/postinstall"
chmod 755 "$WORK/scripts/postinstall"

pkgbuild --root "$WORK/root" \
    --install-location /Library/Printers/hplip-arm64 \
    --scripts "$WORK/scripts" \
    --identifier "$PKG_ID" --version "$VERSION" \
    --ownership recommended \
    "$WORK/hplip-arm64-component.pkg"

# pkgbuild turns extended attributes (e.g. com.apple.provenance, which macOS
# may add and not allow removing) into AppleDouble ._ entries. Rewrite the
# payload without them.
X="$WORK/expanded"
pkgutil --expand "$WORK/hplip-arm64-component.pkg" "$X"
ditto -c -z --norsrc --noextattr --noacl --zlibCompressionLevel 9 "$WORK/root" "$X/Payload"
lsbom "$X/Bom" | grep -v '/\._' > "$WORK/bom.txt"
rm "$X/Bom"; mkbom -i "$WORK/bom.txt" "$X/Bom"
n=$(wc -l < "$WORK/bom.txt" | tr -d ' ')
sed -i '' "s/numberOfFiles=\"[0-9]*\"/numberOfFiles=\"$n\"/" "$X/PackageInfo"
if lsbom "$X/Bom" | grep -q '/\._'; then echo "AppleDouble files still in Bom" >&2; exit 1; fi
rm "$WORK/hplip-arm64-component.pkg"
pkgutil --flatten "$X" "$WORK/hplip-arm64-component.pkg"
rm -rf "$X"

mkdir -p "$WORK/resources"
cp "$HERE/pkg/welcome.html" "$HERE/pkg/conclusion.html" "$WORK/resources/"
cp "$HERE/LICENSE" "$WORK/resources/LICENSE.txt"
sed "s/@VERSION@/$VERSION/g; s/@PKG_ID@/$PKG_ID/g" "$HERE/pkg/distribution.xml" > "$WORK/distribution.xml"

SIGN_ARGS=()
[ -n "${SIGN_ID:-}" ] && SIGN_ARGS=(--sign "$SIGN_ID")
productbuild --distribution "$WORK/distribution.xml" \
    --resources "$WORK/resources" --package-path "$WORK" \
    "${SIGN_ARGS[@]+"${SIGN_ARGS[@]}"}" \
    "$OUT/hplip-arm64-$VERSION.pkg"

(cd "$OUT" && shasum -a 256 "hplip-arm64-$VERSION.pkg" > "hplip-arm64-$VERSION.pkg.sha256")
echo "Built $OUT/hplip-arm64-$VERSION.pkg"
cat "$OUT/hplip-arm64-$VERSION.pkg.sha256"
