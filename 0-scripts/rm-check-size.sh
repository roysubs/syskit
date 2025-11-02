#!/bin/bash
# Author: Roy Wiseman 2025-03
# Display space that will be freed before deleting files/directories

# Ensure at least one argument is provided
if [ $# -eq 0 ]; then
    echo "Display space that will be freed before deleting"
    echo "Usage: $0 <path1> [path2] [path3] ..."
    echo "Examples:"
    echo "  $0 'namestring-*'        # Delete matching files/dirs"
    echo "  $0 file1.txt dir1/       # Delete specific items"
    echo "  $0 *.log old_data/       # Mix of patterns and paths"
    exit 1
fi

# Expand all matching files/directories
TARGETS=("$@")

# Check if any targets exist
EXISTING_TARGETS=()
for target in "${TARGETS[@]}"; do
    if [ -e "$target" ]; then
        EXISTING_TARGETS+=("$target")
    fi
done

# Ensure at least one match exists
if [ ${#EXISTING_TARGETS[@]} -eq 0 ]; then
    echo "Error: No matching files or directories found"
    echo "Searched for: $*"
    exit 1
fi

# Get initial free disk space
INITIAL_FREE=$(df -h . | awk 'NR==2 {print $4}')

# Calculate total size of targets
TOTAL_SIZE=$(du -shc "${EXISTING_TARGETS[@]}" 2>/dev/null | tail -1 | awk '{print $1}')

# Display summary
echo "========================================"
echo "Current free space: $INITIAL_FREE"
echo "Total size to delete: $TOTAL_SIZE"
echo "========================================"
echo "Items to be deleted (${#EXISTING_TARGETS[@]}):"
for target in "${EXISTING_TARGETS[@]}"; do
    SIZE=$(du -sh "$target" 2>/dev/null | awk '{print $1}')
    if [ -d "$target" ]; then
        echo "  [DIR]  $SIZE  $target"
    else
        echo "  [FILE] $SIZE  $target"
    fi
done
echo "========================================"

# Prompt for deletion
read -p "Proceed with deletion? (y/n): " CONFIRM

if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Deleting..."
    rm -rf "${EXISTING_TARGETS[@]}"
    
    # Get final free space
    FINAL_FREE=$(df -h . | awk 'NR==2 {print $4}')
    
    echo "========================================"
    echo "Deletion complete."
    echo "Previous free space: $INITIAL_FREE"
    echo "New free space:      $FINAL_FREE"
    echo "========================================"
else
    echo "Aborted. No items deleted."
fi
