#!/bin/bash
set -e

# --- Configuration ---
# You can change this variable to install a different version of Go
GO_VERSION="1.22.5"
GO_FILENAME="go${GO_VERSION}.linux-amd64.tar.gz"
DOWNLOAD_URL="https://go.dev/dl/${GO_FILENAME}"
INSTALL_DIR="/usr/local"
GO_BIN_DIR="${INSTALL_DIR}/go/bin"
PROFILE_FILE="${HOME}/.bashrc"
# --- End Configuration ---

echo "Starting Go ${GO_VERSION} installation..."

# Step 1: Download
echo "Changing to home directory..."
cd ~
echo "Downloading ${DOWNLOAD_URL}..."
if ! wget -q --show-progress "${DOWNLOAD_URL}"; then
    echo "❌ ERROR: Download failed. Please check the version/URL."
    exit 1
fi
echo "Download complete."

# Step 2: Remove Old Installation
echo "Removing any old Go installation (requires sudo)..."
if [ -d "${INSTALL_DIR}/go" ]; then
    sudo rm -rf "${INSTALL_DIR}/go"
    echo "Removed old version."
else
    echo "No old version found. Skipping."
fi

# Step 3: Extract the Tarball
echo "Extracting ${GO_FILENAME} to ${INSTALL_DIR} (requires sudo)..."
sudo tar -C "${INSTALL_DIR}" -xzf "${GO_FILENAME}"
echo "Extraction complete."

# Step 4: Set Up Environment (PATH)
echo "Checking your ${PROFILE_FILE} for Go PATH..."
if ! grep -q "${GO_BIN_DIR}" "${PROFILE_FILE}"; then
    echo "Adding Go PATH to ${PROFILE_FILE}..."
    # Add the export line to .bashrc
    echo "" >> "${PROFILE_FILE}"
    echo "# Add Go (Golang) to PATH" >> "${PROFILE_FILE}"
    echo "export PATH=\$PATH:${GO_BIN_DIR}" >> "${PROFILE_FILE}"
    echo "PATH added."
else
    echo "Go PATH already exists in ${PROFILE_FILE}. Skipping."
fi

# Step 5: Clean up
echo "Cleaning up downloaded file..."
rm "${GO_FILENAME}"

# Step 6: Verify Installation
echo "Verifying installation..."
# Temporarily set PATH for this script to run 'go version'
export PATH=$PATH:${GO_BIN_DIR}
if ! command -v go &> /dev/null; then
    echo "❌ ERROR: 'go' command not found even after setting PATH."
    exit 1
fi

echo ""
go version
echo ""
echo "✅ --- SUCCESS! ---"
echo ""
echo "Go ${GO_VERSION} is now installed."
echo "Please restart your terminal or run the command below to update your session:"
echo ""
echo "  source ${PROFILE_FILE}"
echo ""
