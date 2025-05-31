#!/bin/bash
# Author: Roy Wiseman 2025-05

# Find all files that have 'glow -p$' in them (i.e. glow -p at end of line)
# and replace that by 'glow -p -w $(( $(tput cols) - 8 ))'
# to dynamically fit the glow output to terminal width

# Define the folder to search
folder="/home/boss/syskit/0-help"

# Define the search regex and replacement text
search_regex="glow -p$"
replacement='glow -p -w $(( $(tput cols) - 6 ))'

# Find files with matching pattern and apply replacement
find "$folder" -type f -exec grep -l -E "$search_regex" {} + | while read -r file; do
    echo "Processing file: $file"
    sed -i "s|$search_regex|$replacement|g" "$file"
done

echo "Replacement complete."

