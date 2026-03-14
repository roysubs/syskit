#!/bin/bash
# Author: Roy Wiseman 2025-02
# macOS Adapter for h-scripts update

# Now call the original script which handles the cross-platform logic
SCRIPT_DIR=$(dirname "${BASH_SOURCE[0]}")
ORIGINAL_SCRIPT="$SCRIPT_DIR/new1-update-h-scripts.sh"

if [ -x "$ORIGINAL_SCRIPT" ]; then
    "$ORIGINAL_SCRIPT"
else
    echo "Error: Could not find original $ORIGINAL_SCRIPT"
fi
