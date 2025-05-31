#!/bin/bash
# Author: Roy Wiseman 2025-05

# Default behavior: Show aliases and functions as they appear in .bashrc
sort=false

# Check for sorting switch
while getopts "s" opt; do
    case ${opt} in
        s)
            sort=true
            ;;
        \?)
            echo "Usage: $0 [-s]"
            exit 1
            ;;
    esac
done

# Path to .bashrc (can change if using a non-default location)
bashrc_file="$HOME/.bashrc"

# Check if .bashrc exists
if [[ ! -f "$bashrc_file" ]]; then
    echo ".bashrc not found in $HOME"
    exit 1
fi

# Extract aliases and functions
# Aliases will be matched with 'alias' keyword
aliases=$(grep '^alias ' "$bashrc_file")

# Functions will be matched with a more flexible regex for 'function' or simple 'name()'
functions=$(grep -E '^[a-zA-Z0-9_]+\(\)\s*\{' "$bashrc_file")

# Sort if -s or -sort is passed
if [[ "$sort" == true ]]; then
    # Sort aliases first, then functions
    echo "Aliases in .bashrc:"
    echo "=========="
    echo "$aliases" | sort
    echo
    echo "Functions in .bashrc:"
    echo "=========="
    echo "$functions" | sort
    echo
else
    # Just show as they appear
    echo "Aliases in .bashrc:"
    echo "=========="
    echo "$aliases"
    echo
    echo "Functions in .bashrc:"
    echo "=========="
    echo "$functions"
    echo
    echo "The above are unsorted, just listed by how they appear in .bashrc"
    echo "use '${0##*/} -s' to sort them alphabetically."
fi

