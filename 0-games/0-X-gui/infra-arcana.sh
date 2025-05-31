#!/bin/bash
# Author: Roy Wiseman 2025-02

# Use mktemp to create unique temporary directories
# -d ensures a directory is created
SOURCE_DIR=$(mktemp -d -t infra-arcana-source-XXXX) || { echo "Failed to create source temp directory"; exit 1; }
BUILD_DIR=$(mktemp -d -t infra-arcana-build-XXXX) || { echo "Failed to create build temp directory"; rm -rf "$SOURCE_DIR"; exit 1; }
INSTALL_DIR="/usr/local" # Still installing to a standard system location

# Ensure the script exits if any command fails
set -e

echo "Using temporary source directory: $SOURCE_DIR"
echo "Using temporary build directory: $BUILD_DIR"

# Ensure the system is up-to-date and install dependencies
echo "Updating system..."
sudo apt update && sudo apt upgrade -y

echo "Installing dependencies..."
# Ensure comments are on their own lines or before the command
# Using standard spaces for indentation if desired, or no indentation
sudo apt install -y \
    build-essential \
    libasound2-dev \
    libbrotli-dev \
    libbz2-dev \
    libdbus-1-dev \
    libglib2.0-dev \
    libicu-dev \
    libpng-dev \
    libfreetype-dev \
    libjpeg-dev \
    libx11-dev \
    libxrandr-dev \
    libsdl2-dev \
    libsdl2-image-dev \
    libsdl2-mixer-dev \
    git \
    cmake

# Clean any pre-existing source or build directories (these will be the ones just created by mktemp, safe to remove if previous run failed prematurely)
echo "Cleaning up potentially existing temporary directories..."
# mktemp ensures they are unique, but cleaning before use is good practice if rerunning
rm -rf "$SOURCE_DIR" "$BUILD_DIR"

# Re-create directories after clean, just in case mktemp failed partially
SOURCE_DIR=$(mktemp -d -t infra-arcana-source-XXXX) || { echo "Failed to re-create source temp directory"; exit 1; }
BUILD_DIR=$(mktemp -d -d -t infra-arcana-build-XXXX) || { echo "Failed to re-create build temp directory"; rm -rf "$SOURCE_DIR"; exit 1; }

echo "Fresh temporary source directory: $SOURCE_DIR"
echo "Fresh temporary build directory: $BUILD_DIR"


# Clone the repository
echo "Cloning repository into $SOURCE_DIR..."
git clone https://gitlab.com/martin-tornqvist/ia.git "$SOURCE_DIR"

# Navigate to build directory and configure with CMake
echo "Configuring the software with CMake in $BUILD_DIR..."
cd "$BUILD_DIR"
cmake "$SOURCE_DIR" -DCMAKE_INSTALL_PREFIX="$INSTALL_DIR"

# Compile the software
echo "Compiling the software..."
make -j"$(nproc)"

# Install the compiled software
echo "Installing the software..."
sudo make install

# Clean up the temporary source and build directories
echo "Cleaning up temporary source ($SOURCE_DIR) and build ($BUILD_DIR) directories..."
sudo rm -rf "$SOURCE_DIR" "$BUILD_DIR"

# Verify installation
echo "Verifying installation..."
# The executable name for Infra Arcana is 'ia' and it should be in $INSTALL_DIR/bin
EXECUTABLE_PATH="$INSTALL_DIR/bin/ia"

if [ -f "$EXECUTABLE_PATH" ]; then
    echo "Infra Arcana executable found at: $EXECUTABLE_PATH"
    echo "You should be able to run it from the terminal now (it might require your user to have $INSTALL_DIR/bin in their PATH, or run with the full path)."
    # Optional: Add $INSTALL_DIR/bin to current session's PATH
    # export PATH="$INSTALL_DIR/bin:$PATH"
else
    echo "Error: Could not find the Infra Arcana executable at $EXECUTABLE_PATH. Please check the build output for errors."
    exit 1 # Exit with error code if verification fails
fi

echo "Installation and cleanup complete!"
