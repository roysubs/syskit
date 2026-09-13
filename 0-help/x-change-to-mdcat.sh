#!/usr/bin/env bash
if ((BASH_VERSINFO[0] < 4)); then echo "This script needs bash 4+. On macOS: brew install bash" >&2; return 1 2>/dev/null || exit 1; fi
# Author: Roy Wiseman 2025-05

# Find all files that have 'glow -p' in them (i.e. glow -p to the of line)
# and replace that by 'mdcat | less -R'

# Define the folder to search
folder="/home/boss/syskit/0-help"

# Define the exact search text and replacement
search="cat <<'EOF' | glow -p -w \$(( \$(tput cols) - 6 ))"
replace="cat <<'EOF' | mdcat | less -R"

# Process each file
find "$folder" -type f | while IFS= read -r file; do
    if grep -qF "$search" "$file"; then
        echo "Replacing in: $file"
        sed -i.bak "s/$search/$replace/g" "$file"
    fi
done

echo "Replacement complete."

