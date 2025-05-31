#!/usr/bin/env bash
# Author: Roy Wiseman 2025-04
set -e

REPO="o2sh/onefetch"

# Function to get latest version
get_latest_version() {
    curl -s "https://api.github.com/repos/$REPO/releases/latest" \
    | grep '"tag_name":' \
    | sed -E 's/.*"([^"]+)".*/\1/' \
    | sed 's/^v//'  # remove leading v if present
}

# Function to check if Rust/Cargo is installed
check_rust() {
    if command -v cargo >/dev/null 2>&1; then
        echo "Cargo found: $(cargo --version)"
        return 0
    else
        echo "Cargo not found."
        return 1
    fi
}

# Function to install Rust/Cargo
install_rust() {
    echo "Installing Rust and Cargo..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source "$HOME/.cargo/env"
    echo "Rust installed: $(cargo --version)"
}

# Check for existing onefetch and its version
if command -v onefetch >/dev/null 2>&1; then
    CURRENT_VERSION=$(onefetch --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")
    echo "Installed onefetch version: $CURRENT_VERSION"
elif dpkg -l 2>/dev/null | grep -q "^ii.*onefetch"; then
    CURRENT_VERSION=$(dpkg -l | grep onefetch | awk '{print $3}' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")
    echo "Installed onefetch version (via dpkg): $CURRENT_VERSION"
    echo "Note: Removing incompatible .deb package..."
    sudo dpkg -r onefetch 2>/dev/null || true
    CURRENT_VERSION="none"
else
    CURRENT_VERSION="none"
    echo "onefetch not found."
fi

LATEST_VERSION=$(get_latest_version)
echo "Latest onefetch version on GitHub: $LATEST_VERSION"

if [[ "$CURRENT_VERSION" == "$LATEST_VERSION" ]]; then
    echo "You already have the latest version. Running onefetch:"
    onefetch
    exit 0
fi

# Check if Rust/Cargo is available
if ! check_rust; then
    echo
    read -p "Rust/Cargo is required to compile onefetch. Install it? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        install_rust
    else
        echo "Cannot proceed without Rust/Cargo. Exiting."
        exit 1
    fi
fi

# Make sure cargo is in PATH
if ! command -v cargo >/dev/null 2>&1; then
    echo "Loading Rust environment..."
    source "$HOME/.cargo/env"
fi

echo "Installing/updating onefetch via Cargo..."
echo "This may take a few minutes as it compiles from source..."

# Install onefetch via cargo
cargo install onefetch

# Verify installation
if command -v onefetch >/dev/null 2>&1; then
    NEW_VERSION=$(onefetch --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
    echo "Successfully installed onefetch version: $NEW_VERSION"
    echo
    echo "Running onefetch:"
    onefetch
else
    echo "Installation failed. Make sure ~/.cargo/bin is in your PATH:"
    echo 'export PATH="$HOME/.cargo/bin:$PATH"'
    echo "Add this line to your ~/.bashrc or ~/.profile"
fi
