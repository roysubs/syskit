#!/usr/bin/env bash
if ((BASH_VERSINFO[0] < 4)); then echo "This script needs bash 4+. On macOS: brew install bash" >&2; return 1 2>/dev/null || exit 1; fi
# Author: Roy Wiseman 2025-05

# Script to invoke and run the script at ~/syskit/0-new-system/myhelp.sh

# Define the path to the target script
TARGET_SCRIPT=../0-new-system/new2-update-h-scripts.sh

# Check if the target script exists and is executable
if [[ -x "$TARGET_SCRIPT" ]]; then
    # Run the target script
    "$TARGET_SCRIPT"
else
    echo "Error: $TARGET_SCRIPT does not exist or is not executable." >&2
    exit 1
fi

