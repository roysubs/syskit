#!/bin/bash
# Author: Roy Wiseman 2025-04
set -e

# Set constants
# Use a more specific temp directory name for clarity and robustness
TMP_DIR="$(mktemp -d install-trufflehog-XXXXXX)"
INSTALL_DIR="$HOME/.local/bin"
ARCH="linux_amd64" # Assuming 64-bit Linux. Use $(uname -m) for more general arch detection if needed.

# --- Cleanup Function ---
# This function will be called automatically when the script exits
cleanup() {
  echo "Cleaning up temporary directory: $TMP_DIR..."
  if [ -d "$TMP_DIR" ]; then
    rm -rf "$TMP_DIR"
    echo "Cleanup complete."
  else
    echo "Temporary directory $TMP_DIR not found, skipping cleanup."
  fi
}

# Register the cleanup function to run on script exit (EXIT signal)
# This ensures cleanup happens even if the script fails or is interrupted
trap cleanup EXIT

# Get latest release tag from GitHub API
echo "Step 1: Fetching latest release tag from GitHub..."
LATEST_TAG=$(curl -s https://api.github.com/repos/trufflesecurity/trufflehog/releases/latest |
    grep '"tag_name":' | cut -d'"' -f4)

if [ -z "$LATEST_TAG" ]; then
    echo "❌ Error: Failed to fetch latest tag. Check GitHub API or internet connection."
    exit 1
fi
echo "✅ Latest tag found: $LATEST_TAG"

# Construct the tarball name and URL
# Remove the leading 'v' from the tag name for the filename
TARBALL_NAME="trufflehog_${LATEST_TAG#v}_${ARCH}.tar.gz"
TARBALL_PATH="$TMP_DIR/$TARBALL_NAME"
URL="https://github.com/trufflesecurity/trufflehog/releases/download/${LATEST_TAG}/${TARBALL_NAME}"

# Download the tarball
echo "Step 2: Downloading $URL..."
# Add --progress-bar for visibility during download
# Add -f (--fail) to exit immediately if curl fails
curl -L -f --progress-bar "$URL" -o "$TARBALL_PATH"

# Check if download was successful
if [ ! -f "$TARBALL_PATH" ]; then
    echo "❌ Error: Download failed. Tarball not found at $TARBALL_PATH."
    exit 1
fi
echo "✅ Download complete."

# Extract the tarball
echo "Step 3: Extracting $TARBALL_NAME to $TMP_DIR..."
# Using -v (verbose) to see what's being extracted might help if it hangs here
tar -xzf "$TARBALL_PATH" -C "$TMP_DIR"
echo "✅ Extraction complete."

# Define the expected binary path in the temporary directory after extraction
EXTRACTED_BINARY="$TMP_DIR/trufflehog"

# Check if the expected binary was extracted
if [ ! -f "$EXTRACTED_BINARY" ]; then
    echo "❌ Error: Expected binary '$EXTRACTED_BINARY' not found after extraction."
    echo "This might mean the tarball structure is different than expected."
    echo "Contents of temporary directory after extraction:"
    ls -al "$TMP_DIR"
    # Optionally, uncomment the next two lines to see the contents of the tarball
    # echo "Contents of the tarball:"
    # tar -tf "$TARBALL_PATH"
    exit 1
fi
echo "✅ Found extracted binary: $EXTRACTED_BINARY"

# Move binary to ~/.local/bin
echo "Step 4: Installing trufflehog to $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"
# Move the binary to the installation directory
mv "$EXTRACTED_BINARY" "$INSTALL_DIR/trufflehog"
# Make the binary executable
chmod +x "$INSTALL_DIR/trufflehog"
echo "✅ Installation complete."

# Ensure ~/.local/bin is in PATH
# Check if INSTALL_DIR is already in PATH using a more robust method
if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
    echo "Step 5: Adding $INSTALL_DIR to PATH..."
    echo "Adding 'export PATH=\"\$HOME/.local/bin:\$PATH\"' to ~/.bashrc (for future sessions)."
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"

    # Update PATH for the current session immediately
    echo "Updating PATH for the current session..."
    export PATH="$HOME/.local/bin:$PATH"
    echo "✅ PATH updated."
    echo "Note: You may need to run 'source ~/.bashrc' in other terminals for the change to take effect."
else
    echo "Step 5: $INSTALL_DIR is already in PATH. No changes needed for PATH."
fi


# Verify installation
echo "Step 6: Verifying installation..."
# Use 2>&1 to redirect stderr to stdout, suppressing potential command not found errors from the check itself
if ! command -v trufflehog >/dev/null 2>&1; then
    echo "❌ Verification failed: trufflehog command not found on PATH after installation."
    echo "Please ensure $INSTALL_DIR is in your PATH and potentially re-source your shell configuration (e.g., 'source ~/.bashrc')."
    exit 1
else
    echo "✅ Verification successful: trufflehog found on PATH."
    echo "Trufflehog version: $(trufflehog --version)"
fi

echo "✨ Trufflehog installation script finished successfully."

# The trap will now automatically run the cleanup function as the script exits successfully.
