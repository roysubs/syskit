#!/bin/bash
# Author: Roy Wiseman 2025-04

# Script to replace non-breaking spaces (U+00A0)
# with regular spaces (U+0020) in a file.

# Check if a filename is provided
if [ -z "$1" ]; then
    echo "Usage: $0 <filename>"
    exit 1
fi

input_file="$1"

# Check if the input file exists
if [ ! -f "$input_file" ]; then
    echo "Error: File '$input_file' not found."
    exit 1
fi

# Create a backup of the original file
backup_file="${input_file}.bak"
cp "$input_file" "$backup_file"

if [ $? -ne 0 ]; then
    echo "Error: Could not create backup file '$backup_file'."
    exit 1
fi
echo "Backup of '$input_file' created as '$backup_file'"

# Use perl to replace U+00A0 with a regular space in the original file.
# -C : Enables various Unicode features. S ensures STDIN/OUT/ERR are UTF-8.
# -i : Edits files in-place.
# -p : Creates a loop around the script, printing each line after processing.
# -e : Executes the following string as a perl script.
# 's/\x{00A0}/ /g' : Substitutes (s) the Unicode char U+00A0 with a space, globally (g).
perl -CS -i -pe 's/\x{00A0}/ /g' "$input_file"

if [ $? -eq 0 ]; then
    echo "Successfully replaced non-breaking spaces in '$input_file'."
else
    echo "An error occurred while processing '$input_file'."
    echo "Your original file is safe in '$backup_file'."
    exit 1
fi

exit 0
