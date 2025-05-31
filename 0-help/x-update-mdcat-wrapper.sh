#!/bin/bash
# Author: Roy Wiseman 2025-03

# Script to transform a specific cat <<'EOF' line in a file

# Check if exactly one argument is provided
if [ $# -ne 1 ]; then
  echo "Usage: $0 <file_path>"
  exit 1
fi

file="$1"

# Check if the provided path is a regular file
if [ ! -f "$file" ]; then
  echo "Error: File not found or is not a regular file: '$file'"
  exit 1
fi

echo "Processing file: '$file'"

# Use sed to find the line containing the specific pattern and replace the entire line.
# Pattern to find:    cat <<'EOF' | mdcat | less -R
# Replacement (2 lines):
# WIDTH=$(if [ $(tput cols) -ge 105 ]; then echo 100; else echo $(($(tput cols) - 5)); fi)
# mdcat --columns="$WIDTH" <(cat <<'EOF'

# Explanation of the sed command:
# -i          : Edit the file in place.
# /pattern/   : Address - apply the command only to lines matching 'pattern'.
# c\          : The 'change' command - replace the entire matched line(s).
# replacement : The text to replace the line with. Use '\n' for newlines.
# Escaping:
# '\''        : Shell trick to put a literal single quote inside a single-quoted string.
# \|          : Escape pipe '|' as it's a regex special character.
# \-R         : Escape hyphen '-' (optional but safe in ranges, good habit).

sed -i '/cat <<'\''EOF'\'' \| mdcat \| less \-R/ c\WIDTH=$(if [ $(tput cols) -ge 105 ]; then echo 100; else echo $(($(tput cols) - 5)); fi)\nmdcat --columns="$WIDTH" <(cat <<'\''EOF'\''' "$file"

# You might want to add a check here to see if the pattern was actually found and replaced.
# sed -i doesn't easily provide a count, but you could grep for the original pattern before running sed,
# or grep for the *new* pattern after running sed.
# For simplicity, we'll just report based on sed's exit status (usually 0 unless syntax error or file issue).

if [ $? -eq 0 ]; then
    echo "Transformation applied successfully to '$file' (or original pattern not found)."
else
    echo "Error during sed processing for '$file'."
    exit 1
fi

exit 0
