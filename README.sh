#!/bin/bash
# Author: Roy Wiseman 2025-02

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"       # Directory where this script is
SCRIPT_FILENAME_WITH_EXT="${0##*/}"               # This script's filename without path
SCRIPT_BASENAME="${SCRIPT_FILENAME_WITH_EXT%.*}"  # Remove the extension
MARKDOWN_FILE_PATH="${SCRIPT_DIR}/${SCRIPT_BASENAME}.md"  # Full path to .md file in same dir as this script

# Ensure mdcat-get.sh is also called relative to script dir if needed
command -v mdcat &>/dev/null || "${SCRIPT_DIR}/0-install/mdcat-get.sh"; hash -r # Assuming mdcat-get.sh is with README.sh
command -v mdcat &>/dev/null || { echo "Error: mdcat required but not available." >&2; exit 1; }

if [[ ! -f "${MARKDOWN_FILE_PATH}" ]]; then
    echo "Error: Markdown file not found at ${MARKDOWN_FILE_PATH}" >&2
    # You can add a 'pwd' here for more debugging if you want:
    # echo "Current working directory: $(pwd)" >&2
    exit 1
fi

WIDTH=$(if [ $(tput cols) -ge 105 ]; then echo 100; else echo $(( $(tput cols) - 5 )); fi)
mdcat --columns="$WIDTH" <(cat "${MARKDOWN_FILE_PATH}") | less -R
