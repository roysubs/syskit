#!/bin/bash
# Author: Roy Wiseman 2025-02

# Define the folder to search
folder="/home/boss/syskit/0-help"

# Process each file
find "$folder" -type f | while IFS= read -r file; do
    echo "Processing: $file"

    # Replace glow check with mdcat check
    sed -i.bak 's|if ! command -v mdcat >/dev/null 2>if ! command -v glow >/dev/null 2>&1; then echo "Install glow to render markdown."; fi1; then echo "Install mdcat to render markdown."; fi|if ! command -v mdcat >/dev/null 2>&1; then echo "Install mdcat to render markdown."; fi|g' "$file"

    # Ensure a blank line after 'cat <<'EOF' | mdcat | less -R' if the next line contains text
    awk '
    {print}
    last_line == "cat <<'\''EOF'\'' | mdcat | less -R" {
        if ($0 != "" && !blank_inserted) {
            print "";
            blank_inserted = 1;
        }
    }
    {last_line = $0}
    ' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
done

echo "Processing complete."

