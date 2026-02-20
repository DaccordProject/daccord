#!/usr/bin/env bash
set -euo pipefail

REPO="DaccordProject/daccord"
INSTALL_DIR="$HOME/.local/share/daccord"
BIN_DIR="$HOME/.local/bin"
DESKTOP_DIR="$HOME/.local/share/applications"

# -- Detect architecture ---------------------------------------------------

ARCH=$(uname -m)
case "$ARCH" in
    x86_64)  ARTIFACT="daccord-linux-x86_64" ;;
    aarch64) ARTIFACT="daccord-linux-arm64" ;;
    *)
        echo "Error: unsupported architecture '$ARCH'. Daccord supports x86_64 and arm64."
        exit 1
        ;;
esac

echo "Installing Daccord for $ARCH..."

# -- Find latest release ----------------------------------------------------

RELEASE_URL=$(curl -sfL "https://api.github.com/repos/$REPO/releases/latest" \
    | grep -o "\"browser_download_url\": *\"[^\"]*${ARTIFACT}\\.tar\\.gz\"" \
    | head -1 \
    | cut -d '"' -f 4)

if [ -z "$RELEASE_URL" ]; then
    echo "Error: could not find a $ARTIFACT.tar.gz download in the latest release."
    echo "Check https://github.com/$REPO/releases for available downloads."
    exit 1
fi

VERSION=$(echo "$RELEASE_URL" | grep -oP '/download/v?\K[^/]+')
echo "Latest version: $VERSION"

# -- Download and extract ---------------------------------------------------

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "Downloading $ARTIFACT.tar.gz..."
curl -#fL "$RELEASE_URL" -o "$TMP/daccord.tar.gz"

echo "Installing to $INSTALL_DIR..."
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
tar xzf "$TMP/daccord.tar.gz" -C "$INSTALL_DIR"

# -- Create launcher symlink ------------------------------------------------

mkdir -p "$BIN_DIR"

# Find the main executable (named daccord.x86_64, daccord.arm64, etc.)
EXE=$(find "$INSTALL_DIR" -maxdepth 1 -name 'daccord.*' -executable -type f | head -1)

if [ -z "$EXE" ]; then
    echo "Warning: could not find the Daccord executable in the archive."
else
    ln -sf "$EXE" "$BIN_DIR/daccord"
fi

# -- Desktop entry ----------------------------------------------------------

mkdir -p "$DESKTOP_DIR"

ICON_PATH="$INSTALL_DIR/daccord.png"

cat > "$DESKTOP_DIR/daccord.desktop" <<EOF
[Desktop Entry]
Name=Daccord
Comment=Chat client for accordserver instances
Exec=$BIN_DIR/daccord
Icon=$ICON_PATH
Terminal=false
Type=Application
Categories=Network;Chat;InstantMessaging;
Keywords=chat;messaging;
StartupWMClass=daccord
EOF

# -- Done -------------------------------------------------------------------

echo ""
echo "Daccord $VERSION installed successfully!"
echo ""
echo "  Launch from your app menu, or run:"
echo "    daccord"
echo ""

if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
    echo "  Note: $BIN_DIR is not in your PATH."
    echo "  Add it by appending this to your ~/.bashrc or ~/.zshrc:"
    echo "    export PATH=\"\$HOME/.local/bin:\$PATH\""
    echo ""
fi
