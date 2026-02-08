#!/bin/bash
# Author: Roy Wiseman 2025-03

# Ensure at least one argument is provided
if [ $# -eq 0 ]; then
    echo "Display space that will be deleted before deleting"
    echo "Usage: $0 '<pattern>'"
    echo "Example: $0 'namestring-*'"
    exit 1
fi

# Expand all matching directories
TARGET_DIRS=("$@")

# Ensure at least one match exists
if [ -z "${TARGET_DIRS[*]}" ]; then
    echo "No matching directories found for pattern: $1"
    exit 1
fi

# Get initial free disk space
INITIAL_FREE=$(df -h . | awk 'NR==2 {print $4}')

# Calculate total size of target directories
TOTAL_SIZE=$(du -shc "${TARGET_DIRS[@]}" 2>/dev/null | tail -1 | awk '{print $1}')

echo "Current free space: $INITIAL_FREE"
echo "Total size of matching directories (${TARGET_DIRS[*]}): $TOTAL_SIZE"

# Prompt for deletion
read -p "Do you want to delete these folders? (y/n): " CONFIRM
if [[ "$CONFIRM" == "y" ]]; then
    rm -rf "${TARGET_DIRS[@]}"
    FINAL_FREE=$(df -h . | awk 'NR==2 {print $4}')
    echo "Deletion complete."
    echo "New free space: $FINAL_FREE"
else
    echo "Aborted. No files deleted."
fi

