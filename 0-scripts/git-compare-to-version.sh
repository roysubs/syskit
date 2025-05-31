#!/bin/bash
# Author: Roy Wiseman 2025-05

# Usage check
if [ $# -ne 2 ]; then
    echo "Usage: ${0##*/} <file> <nth-most-recent>"
    exit 1
fi

file=$1
nth=$2

# Check file exists
if [ ! -f "$file" ]; then
    echo "File '$file' does not exist in the working directory."
    exit 1
fi

# Get commit hashes
commit_hash=$(git log --format="%H" -n "$nth" -- "$file" | tail -n 1)
current_hash=$(git log --format="%H" -n 1 -- "$file")

# Check hash success
if [ -z "$commit_hash" ]; then
    echo "Couldn't find the $nth most recent commit for file '$file'"
    exit 1
fi

# Get commit timestamps
older_time=$(git show -s --format="%ci" "$commit_hash")
current_time=$(git show -s --format="%ci" "$current_hash")

# Print pre-diff summary
echo
echo "Script: $0"
echo "Older script was committed at $older_time ($nth versions before current)"
echo "Current script was last committed at $current_time"
echo

# Show git status
echo "Git status (staged/unstaged changes):"
git status --short "$file"
echo

# Bright white prompt (ANSI)
echo -e "\033[97mPress any key to continue...\033[0m"
read -n 1 -s

# Show the diff
git diff "$commit_hash" -- "$file"

