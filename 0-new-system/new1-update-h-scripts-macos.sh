#!/bin/bash
# Author: Roy Wiseman 2025-02
# macOS Adapter for h-scripts update

# Ensure /usr/local/bin exists (often missing on clean macOS installs)
DEST_DIR="/usr/local/bin"
if [ ! -d "$DEST_DIR" ]; then
    echo "Directory $DEST_DIR does not exist. Creating it (requires sudo)..."
    sudo mkdir -p "$DEST_DIR"
    # Set permissions? Default root:wheel is usually fine, users need sudo to cp.
fi

# Now call the original script
SCRIPT_DIR=$(dirname "${BASH_SOURCE[0]}")
ORIGINAL_SCRIPT="$SCRIPT_DIR/new1-update-h-scripts.sh"

if [ -x "$ORIGINAL_SCRIPT" ]; then
    "$ORIGINAL_SCRIPT"
else
    echo "Error: Could not find original $ORIGINAL_SCRIPT"
fi
