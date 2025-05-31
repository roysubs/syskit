#!/usr/bin/env bash
# Author: Roy Wiseman 2025-02

set -e

REPO="ozwaldorf/punfetch"
ARCH="x86_64"
INSTALL_DIR="/usr/local/bin"
TMPDIR=$(mktemp -d)

# Function to get latest release version from GitHub API
get_latest_version() {
    curl -s "https://api.github.com/repos/$REPO/releases/latest" \
    | grep '"tag_name":' \
    | sed -E 's/.*"([^"]+)".*/\1/' \
    | sed 's/^v//'  # in case it's like "v0.3.6"
}

# Check if punfetch exists
if command -v punfetch >/dev/null 2>&1; then
    CURRENT_VERSION=$(punfetch --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
    echo "Installed punfetch version: $CURRENT_VERSION"
else
    CURRENT_VERSION="none"
    echo "punfetch not found in PATH."
fi

LATEST_VERSION=$(get_latest_version)
echo "Latest punfetch version on GitHub: $LATEST_VERSION"

# Compare versions
if [[ "$CURRENT_VERSION" == "$LATEST_VERSION" ]]; then
    echo "You already have the latest version. Running punfetch:"
    punfetch
    exit 0
fi

echo "Updating punfetch to version $LATEST_VERSION..."

# Get download URL
TAR_URL="https://github.com/$REPO/releases/download/$LATEST_VERSION/punfetch-${LATEST_VERSION}-${ARCH}.tar.gz"
FILENAME=$(basename "$TAR_URL")

echo "Downloading $FILENAME..."
curl -L "$TAR_URL" -o "$TMPDIR/$FILENAME"

echo "Extracting..."
tar -xzf "$TMPDIR/$FILENAME" -C "$TMPDIR"

# Move the binary into place
echo "Installing punfetch to $INSTALL_DIR..."
sudo mv "$TMPDIR/punfetch" "$INSTALL_DIR/punfetch"
sudo chmod +x "$INSTALL_DIR/punfetch"

echo "Cleaning up..."
rm -rf "$TMPDIR"

echo "Running punfetch:"
punfetch

