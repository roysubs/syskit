#!/bin/bash
# Author: Roy Wiseman 2025-05

# Check if the input .swp file is provided
if [[ -z "$1" ]]; then
    echo "Usage: $0 <.file.swp>"
    exit 1
fi

SWP_FILE="$1"

# Ensure the file exists and is a .swp file
if [[ ! -f "$SWP_FILE" || "${SWP_FILE##*.}" != "swp" ]]; then
    echo "Error: Please provide a valid .swp file."
    exit 1
fi

# Extract the base name by removing the leading dot and the .swp extension
BASE_NAME=$(basename "$SWP_FILE" | sed 's/^\.//; s/\.swp$//')

# Construct the recovered filename with "-recovered" added before the extension
RECOVERED_FILE="${BASE_NAME%.*}-recovered.${BASE_NAME##*.}"

# Recover the contents of the swap file
vim -n -r "$SWP_FILE" -c "wq! $RECOVERED_FILE" >/dev/null 2>&1

# Check if the recovery was successful
if [[ -f "$RECOVERED_FILE" ]]; then
    echo "Recovered file created: $RECOVERED_FILE"
    echo
    echo "To compare the files, you can use:"
    echo "  vimdiff ${BASE_NAME} $RECOVERED_FILE"
    echo "  diff ${BASE_NAME} $RECOVERED_FILE"
else
    echo "Error: Failed to recover the .swp file."
    exit 1
fi

