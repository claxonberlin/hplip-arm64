#!/bin/bash
# Build a native arm64 hpcups filter + HP DeskJet 5900-series PPD into ./dist.
# Downloads HPLIP, verifies it, applies ./patches, builds only hpcups.
# No sudo needed.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
HPLIP_VER=3.26.6
HPLIP_SHA256=5fb2235a9cb6ec07cb4786c4066b151359c301324d54aaabf69ae7eef35606b3
HPLIP_URL="https://sourceforge.net/projects/hplip/files/hplip/$HPLIP_VER/hplip-$HPLIP_VER.tar.gz/download"
PREFIX=/Library/Printers/hplip-arm64
PPD_NAME=hp-deskjet_5900_series.ppd
export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-13.0}"

BUILD="$HERE/build"
DIST="$HERE/dist"
TARBALL="$BUILD/hplip-$HPLIP_VER.tar.gz"
SRC="$BUILD/hplip-$HPLIP_VER"

[ "$(uname -m)" = arm64 ] || { echo "Build this on an Apple silicon Mac." >&2; exit 1; }
command -v brew >/dev/null || { echo "Homebrew is required: https://brew.sh" >&2; exit 1; }
xcode-select -p >/dev/null 2>&1 || { echo "Run: xcode-select --install" >&2; exit 1; }

for f in jpeg-turbo autoconf automake libtool pkgconf; do
    brew list --versions "$f" >/dev/null 2>&1 || brew install "$f"
done
BREW="$(brew --prefix)"
export PATH="$BREW/bin:$PATH"
JPEG="$(brew --prefix jpeg-turbo)"

mkdir -p "$BUILD"

# 1. Fetch + verify HPLIP.
if [ ! -f "$TARBALL" ] || ! echo "$HPLIP_SHA256  $TARBALL" | shasum -a 256 -c --status; then
    echo "Downloading HPLIP $HPLIP_VER..."
    curl -fL --retry 3 -o "$TARBALL.part" "$HPLIP_URL"
    mv "$TARBALL.part" "$TARBALL"
fi
echo "$HPLIP_SHA256  $TARBALL" | shasum -a 256 -c

# 2. Fresh source tree + patches.
rm -rf "$SRC"
tar -xzf "$TARBALL" -C "$BUILD"
for p in "$HERE"/patches/*.patch; do
    echo "Applying $(basename "$p")"
    patch -d "$SRC" -p1 -s < "$p"
done

# 3. Link libjpeg statically: cupsd runs filters in a sandbox, so the filter
#    should depend only on system libraries, not on Homebrew.
mkdir -p "$BUILD/jpeg-static"
ln -sf "$JPEG/lib/libjpeg.a" "$BUILD/jpeg-static/libjpeg.a"

# 4. Configure + build just hpcups.
cd "$SRC"
AUTOMAKE="automake --foreign" autoreconf -fi > "$BUILD/autoreconf.log" 2>&1
./configure --prefix="$PREFIX" \
    --enable-hpcups-only-build --disable-imageProcessor-build \
    --disable-network-build --disable-scan-build --disable-gui-build \
    --disable-fax-build --disable-dbus-build --disable-doc-build \
    --disable-cups-drv-install \
    --with-cupsfilterdir="$PREFIX/filter" \
    --with-cupsbackenddir="$PREFIX/backend" \
    --with-hpppddir="$PREFIX/ppd" \
    CPPFLAGS="-I$JPEG/include" LDFLAGS="-L$BUILD/jpeg-static" \
    > "$BUILD/configure.log" 2>&1
make -j"$(sysctl -n hw.ncpu)" hpcups > "$BUILD/make.log" 2>&1 ||
    { tail -30 "$BUILD/make.log"; exit 1; }

# 5. Stage.
rm -rf "$DIST"
mkdir -p "$DIST/filter" "$DIST/ppd"
cp hpcups "$DIST/filter/hpcups"
strip -S "$DIST/filter/hpcups"
codesign --force --sign - --timestamp=none "$DIST/filter/hpcups"

# PPD: taken straight from the tarball (configure regenerates the PPDs in the
# tree). Point cupsFilter2 at the installed filter by absolute path.
tar -xOzf "$TARBALL" "hplip-$HPLIP_VER/ppd/hpcups/$PPD_NAME.gz" | gunzip > "$DIST/ppd/$PPD_NAME"
sed -i '' \
    -e "s|^\*cupsFilter: \"application/vnd.cups-raster 0 hpcups\"|*cupsFilter2: \"application/vnd.cups-raster application/vnd.hp-pcl3gui2 0 $PREFIX/filter/hpcups\"|" \
    -e 's|^\*NickName: "\(.*\)"|*NickName: "\1 (arm64)"|' \
    "$DIST/ppd/$PPD_NAME"
grep -q "^\*cupsFilter2: .*$PREFIX/filter/hpcups\"" "$DIST/ppd/$PPD_NAME"
! grep -q '^\*cupsFilter:' "$DIST/ppd/$PPD_NAME"
cupstestppd -q -I filters -W translations -W sizes "$DIST/ppd/$PPD_NAME"

echo
file "$DIST/filter/hpcups"
otool -L "$DIST/filter/hpcups" | tail -n +2
if otool -L "$DIST/filter/hpcups" | tail -n +2 | grep -qv '^\s*/usr/lib/'; then
    echo "error: filter links against a non-system library" >&2; exit 1
fi
echo "Built into $DIST"
