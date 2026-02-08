#!/bin/bash
# Author: Roy Wiseman 2025-01

# Tool to run a pip package inside a venv (requires pipx, python3-venv)

# Check if pipx is installed, if not, notify user and install it
if ! command -v pipx &>/dev/null; then
    echo "pipx is not installed. Installing pipx..."
    sudo apt update && sudo apt install -y pipx
    pipx ensurepath
fi

# Ensure python3-venv is installed
install_if_missing() {
    local pkg=$1
    if ! dpkg -l | grep -q "$pkg"; then
        echo "$pkg not found. Installing..."
        sudo apt install -y "$pkg"
    fi
}

install_if_missing "python3-venv"

# Check if the user provided the package name
if [ -z "$1" ]; then
    echo "Usage: $0 <package-name> [other parameters]"
    echo "Example: $0 weather-cli London"
    exit 1
fi

PACKAGE=$1
shift  # Remove the package name from arguments to pass the rest as parameters
PARAMS="$@"  # Remaining arguments to pass to the package

# Create a temporary directory for the virtual environment
VENV_DIR=$(mktemp -d -t venv-XXXXXX)

# Create and activate the virtual environment
echo "Creating a virtual environment in $VENV_DIR..."
python3 -m venv "$VENV_DIR"
source "$VENV_DIR/bin/activate"

# Install the specified package in the virtual environment
echo "Installing $PACKAGE in the virtual environment..."
pip install "$PACKAGE" || {
    echo -e "\033[0;31mFailed to install $PACKAGE. Exiting...\033[0m"
    deactivate
    exit 1
}

# Run the package with the provided parameters
echo "Running $PACKAGE with parameters: $PARAMS"
$PACKAGE $PARAMS

# Ask whether to stay in the venv or exit
echo -e "\n\033[1;34mStay in the virtual environment or exit?\033[0m"
read -p "Type 'y' to stay or 'n' to exit: " choice

if [ "$choice" == "y" ]; then
    echo "You are still in the virtual environment. To deactivate, run 'deactivate'."
    echo "Press any key to exit the script without deactivating."
    read -n 1 -s
else
    deactivate
    echo "Virtual environment deactivated."
    # Cleanup: Delete the virtual environment directory
    rm -rf "$VENV_DIR"
fi

