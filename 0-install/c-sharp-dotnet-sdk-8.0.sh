#!/bin/bash
# Author: Roy Wiseman 2025-01

# Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root."
  exit 1
fi

# Update package index
apt update

# Install prerequisites
apt install -y wget apt-transport-https software-properties-common gnupg

# Add Microsoft package signing key and repository for .NET 8.0
wget https://packages.microsoft.com/config/ubuntu/22.04/packages-microsoft-prod.deb -O packages-microsoft-prod.deb
if [ $? -ne 0 ]; then
  echo "Failed to download Microsoft package. Check your network connection."
  exit 1
fi

dpkg -i packages-microsoft-prod.deb || exit 1
rm packages-microsoft-prod.deb

# Update package index again
apt update

# Install .NET SDK 8.0
apt install -y dotnet-sdk-8.0 || {
  echo "Failed to install .NET SDK. Attempting to fix dependencies..."
  apt --fix-broken install -y
  apt install -y dotnet-sdk-8.0
}

# Verify installation
if command -v dotnet &> /dev/null; then
  echo "Installation successful. .NET version:"
  dotnet --version
else
  echo "Installation failed. Please check logs for errors."
  exit 1
fi

