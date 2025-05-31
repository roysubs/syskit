#!/bin/bash
# Author: Roy Wiseman 2025-02
# Fixed script to update h-* help files in /usr/local/bin
# 1. Remove all h-* files from /usr/local/bin
# 2. Copy h-* files containing "mdcat" from ~/syskit/0-help to /usr/local/bin

# Exit on any error
set -e

# Directories
SOURCE_DIR="$HOME/syskit/0-help"
DEST_DIR="/usr/local/bin"

echo "Starting h-* script update process..."

# Check if source directory exists
if [ ! -d "$SOURCE_DIR" ]; then
    echo "Error: Source directory $SOURCE_DIR does not exist."
    exit 1
fi

# Verify with the user before proceeding
total_files=$(find "$SOURCE_DIR" -maxdepth 1 -type f -name "h-*" | wc -l)
echo "Found $total_files h-* files in $SOURCE_DIR"

# Remove existing h-* files from /usr/local/bin
echo "Removing existing h-* files from $DEST_DIR..."
sudo rm -f "$DEST_DIR"/h-*

# Create a temporary file to store the names of copied files
temp_file=$(mktemp)

# Try multiple grep methods to find "mdcat" in files
echo "Finding and copying h-* files containing 'mdcat' from $SOURCE_DIR to $DEST_DIR..."

# Method 1: Standard grep with binary files treated as text
find "$SOURCE_DIR" -maxdepth 1 -type f \( -name "h-*" -o -name "mdcat-get.sh" \) | while read -r file; do
    if grep -q "mdcat" "$file" 2>/dev/null || strings "$file" | grep -q "mdcat"; then
        # Make file executable
        chmod +x "$file"
        
        # Copy to destination with sudo
        if sudo cp -f "$file" "$DEST_DIR/"; then
            basename_file=$(basename "$file")
            echo "Copied: $basename_file"
            echo "$basename_file" >> "$temp_file"
        else
            echo "Failed to copy: $(basename "$file")"
        fi
    fi
done

# Count and display copied files
copied_count=$(wc -l < "$temp_file")
copied_files=$(cat "$temp_file")

echo
echo "--- Summary ---"
echo "Copied $copied_count h-* files to $DEST_DIR"
if [ "$copied_count" -gt 0 ]; then
    echo "Files copied:"
    cat "$temp_file" | sed 's/^/  /'
fi

# Clean up
rm -f "$temp_file"

echo "Done!"
