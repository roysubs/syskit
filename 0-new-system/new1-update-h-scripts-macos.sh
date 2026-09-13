#!/usr/bin/env bash
if ((BASH_VERSINFO[0] < 4)); then echo "This script needs bash 4+. On macOS: brew install bash" >&2; return 1 2>/dev/null || exit 1; fi
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
