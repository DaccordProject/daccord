#!/usr/bin/env bash
# Package the Flutter Linux release bundle into a .deb.
#
# Usage: dist/build-deb.sh <version> [output.deb]
# Run from the repo root after `flutter build linux`.
#
# Layout produced:
#   /opt/daccord/<bundle>            the Flutter bundle (daccord + data/ + lib/)
#   /usr/bin/daccord                 symlink onto PATH
#   /usr/share/applications/...      desktop entry (from dist/daccord.desktop)
#   /usr/share/icons/hicolor/...     app icons (from dist/icons/icon_*.png)
set -euo pipefail

VERSION="${1:?usage: build-deb.sh <version> [output.deb]}"
OUTPUT="${2:-daccord-linux-x86_64.deb}"
ARCH="amd64"
PKG="daccord"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE="$REPO_ROOT/build/linux/x64/release/bundle"
DIST="$REPO_ROOT/dist"

[ -x "$BUNDLE/daccord" ] || { echo "error: bundle not found at $BUNDLE — run 'flutter build linux' first" >&2; exit 1; }

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

# App payload under /opt, with a launcher symlink on PATH.
install -d "$STAGE/opt/$PKG" "$STAGE/usr/bin"
cp -r "$BUNDLE"/. "$STAGE/opt/$PKG/"
ln -s "/opt/$PKG/daccord" "$STAGE/usr/bin/daccord"

# Desktop entry.
install -Dm644 "$DIST/daccord.desktop" "$STAGE/usr/share/applications/daccord.desktop"

# Icons across the hicolor theme.
for size in 16 32 48 64 128 256 512; do
  src="$DIST/icons/icon_${size}x${size}.png"
  [ -f "$src" ] && install -Dm644 "$src" \
    "$STAGE/usr/share/icons/hicolor/${size}x${size}/apps/daccord.png"
done

# Control metadata. Installed-Size is in KiB.
INSTALLED_SIZE="$(du -sk "$STAGE" | cut -f1)"
install -d "$STAGE/DEBIAN"
cat > "$STAGE/DEBIAN/control" <<EOF
Package: $PKG
Version: $VERSION
Section: net
Priority: optional
Architecture: $ARCH
Installed-Size: $INSTALLED_SIZE
Depends: libgtk-3-0, libstdc++6, libsecret-1-0, libmpv2 | libmpv1
Maintainer: The Daccord Project <noreply@daccord-projects.dev>
Homepage: https://github.com/DaccordProject/daccord
Description: Daccord desktop client
 A fast, cross-platform Flutter client for Daccord communities.
EOF

dpkg-deb --build --root-owner-group "$STAGE" "$REPO_ROOT/$OUTPUT"
echo "built $OUTPUT"
