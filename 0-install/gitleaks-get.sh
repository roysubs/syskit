#!/bin/bash
# Author: Roy Wiseman 2025-02

# Clear any old files
rm -f gitleaks*.tar.gz gitleaks

# Download latest release info and get the correct link for Linux x86_64
DOWNLOAD_URL=$(curl -s https://api.github.com/repos/gitleaks/gitleaks/releases/latest | grep -o "https://.*linux_x64.tar.gz" || grep -o "https://.*linux_amd64.tar.gz")

# Check if a valid URL was found
if [ -z "$DOWNLOAD_URL" ]; then
    echo "❌ Failed to find download URL for Gitleaks. Exiting..."
    exit 1
fi

# Download the file
echo "⬇️ Downloading Gitleaks from $DOWNLOAD_URL..."
wget -q "$DOWNLOAD_URL"

# Extract the tarball (using the actual filename)
TARBALL_NAME=$(basename "$DOWNLOAD_URL")
tar -xzf "$TARBALL_NAME"

# Clean up the tarball
rm -f "$TARBALL_NAME"

# Move to the proper path
echo "🔧 Installing Gitleaks to /usr/local/bin/..."
sudo mv gitleaks /usr/local/bin/
sudo mv README.md /usr/local/bin/gitleaks_README.md
sudo rm -f LICENSE

# Verify installation
echo "✅ Gitleaks installed. Verifying installation..."
which gitleaks
gitleaks --version

