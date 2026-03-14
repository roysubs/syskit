#!/bin/bash
# Author: Roy Wiseman 2025-02
# Refactored script to manage h-* help files
# 1. Cleaner: Removes all stale h-* files from /usr/local/bin (legacy approach)
# 2. Permissions: Ensures all h-* files in ~/syskit/0-help are executable

# Exit on any error
set -e

# Directories
# Use dynamic path detection relative to this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
SOURCE_DIR="$(cd "$SCRIPT_DIR/../0-help" && pwd)"

echo "Optimizing h-* help system..."

# Check if source directory exists
if [ ! -d "$SOURCE_DIR" ]; then
    echo "Error: Source directory $SOURCE_DIR does not exist."
    exit 1
fi

# 1. Clean up stale copies from legacy approach (one-time cleanup)
if [ -d "/usr/local/bin" ]; then
    STALE_FILES=$(ls /usr/local/bin/h-* 2>/dev/null | wc -l)
    if [ "$STALE_FILES" -gt 0 ]; then
        echo "Removing $STALE_FILES stale h-* files from /usr/local/bin (legacy cleanup)..."
        sudo rm -f /usr/local/bin/h-*
    fi
fi

# 2. Ensure all h-* files in source are executable
echo "Ensuring help scripts in $SOURCE_DIR are executable..."
find "$SOURCE_DIR" -maxdepth 1 -type f -name "h-*" -exec chmod +x {} +
chmod +x "$SOURCE_DIR/mdcat-get.sh" 2>/dev/null || true

# 3. List available help commands
echo
echo "--- Help System Ready ---"
echo "All h-* scripts are now executable in $SOURCE_DIR."
echo "Since this directory is in your PATH, you can use them directly."
echo "Try typing 'h-' and hitting <TAB> to see available help topics."
echo

total_files=$(find "$SOURCE_DIR" -maxdepth 1 -type f -name "h-*" | wc -l)
echo "Total help topics available: $total_files"

echo "Done!"
