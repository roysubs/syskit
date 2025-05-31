#!/bin/bash
# Author: Roy Wiseman 2025-03

# Exit on errors
set -e

# Function to print messages in color
info() {
  echo -e "\033[1;34m[INFO]\033[0m $1"
}
error() {
  echo -e "\033[1;31m[ERROR]\033[0m $1" >&2
  exit 1
}

# Ensure script is run as root
if [[ $EUID -ne 0 ]]; then
  error "This script must be run as root. Use sudo."
fi

# Update and upgrade system packages
info "Updating system packages..."
apt update && apt upgrade -y

# Install required dependencies
info "Installing required dependencies..."
apt install -y curl

# Install Ollama using the provided script
info "Installing Ollama..."
if curl -fsSL https://ollama.com/install.sh | sh; then
  info "Ollama installed successfully."
else
  error "Failed to install Ollama."
fi

# Verify the installation
info "Verifying the installation..."
if ollama -v >/dev/null 2>&1; then
  info "Ollama is installed: $(ollama -v)"
else
  error "Ollama verification failed."
fi

# Start and enable the Ollama service
info "Starting and enabling the Ollama service..."
systemctl start ollama
systemctl enable ollama

# Check the service status
info "Checking the Ollama service status..."
if systemctl is-active --quiet ollama; then
  info "Ollama service is running."
else
  error "Ollama service is not running."
fi

# Download a default model
MODEL="llama3:8b"
info "Downloading the default model ($MODEL)..."
if ollama pull "$MODEL"; then
  info "Model $MODEL downloaded successfully."
else
  error "Failed to download model $MODEL."
fi

# Confirm installation and provide usage instructions
info "Installation complete. To use Ollama, run:"
info "  ollama run $MODEL"

