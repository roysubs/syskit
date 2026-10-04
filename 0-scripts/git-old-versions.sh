#!/usr/bin/env bash
if ((BASH_VERSINFO[0] < 4)); then echo "This script needs bash 4+. On macOS: brew install bash" >&2; return 1 2>/dev/null || exit 1; fi
# Author: Roy Wiseman 2025-01

RED='\e[0;31m'
GREEN='\e[0;32m'
YELLOW='\e[0;33m'
BLUE='\e[0;34m'
BOLD='\e[1m'
NC='\e[0m'

# Check if the correct number of arguments is provided
if [ $# -ne 2 ]; then
    echo -e "${BOLD}Usage: ${0##*/} [file] [num]${NC}"
    echo "Get the last [num] versions of [file] from the git history."
    echo "Place them in the current directory with the datetime stamp of the"
    echo "commit date. They will be new/untracked files."
    exit 1
fi

# Get the input file and number of versions to fetch
file=$1
num_versions=$2

# Ensure the file exists in the git repository
if [ ! -f "$file" ]; then
    echo "File $file does not exist in the repository!"
    exit 1
fi

# Fetch the commit hashes for the given number of versions (latest first)
commits=$(git log --format="%H" -n "$num_versions" "$file")

# Loop through the commits and create a backup with the timestamp
for commit in $commits; do
    # Get the commit date and time for the current commit (in UTC)
    timestamp=$(git show -s --format=%cd --date=iso-strict "$commit")
    
    # Convert the timestamp to yymmdd-hhmmss format (using UTC to avoid local timezone issues)
    if [[ "$(uname)" == "Darwin" ]]; then
        # BSD date's %z can't parse the colon in iso-strict's +HH:MM offset, so strip it first
        timestamp_no_colon=$(echo "$timestamp" | sed -E 's/([+-][0-9]{2}):([0-9]{2})$/\1\2/')
        timestamp_filename=$(date -j -u -f "%Y-%m-%dT%H:%M:%S%z" "$timestamp_no_colon" +'%y%m%d-%H%M%S')
    else
        timestamp_filename=$(date -d "$timestamp" -u +'%y%m%d-%H%M%S')
    fi
    
    # Checkout the file as it was at that commit (so we get the content)
    git checkout "$commit" -- "$file"

    # Create a copy of the file with the timestamp in the filename
    cp "$file" "${file}-${timestamp_filename}"

    # Optionally, restore the working directory to the latest commit after each extraction
    git checkout HEAD -- "$file"
    
    echo "Created backup: ${file}-${timestamp_filename}"
done

