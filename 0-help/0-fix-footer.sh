#!/bin/bash
# Author: Roy Wiseman 2025-03

# Look for EOF on a line by itself, delete that line and everything below, and replace it by the new footer
# Includes a **dry run** mode showing which files would be changed and what lines would be removed

set -euo pipefail
shopt -s nullglob

# Colors
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
RESET=$(tput sgr0)

FILES=(./h-*)

echo -e "\nScanning ${#FILES[@]} files..."

for file in "${FILES[@]}"; do
  lineno=$(grep -n -x "EOF" "$file" | head -n1 | cut -d: -f1 || true)

  if [[ -z "$lineno" ]]; then
      echo -e "${GREEN}$file${RESET} — no 'EOF' found"
      continue
  fi

  echo -e "${RED}$file${RESET}"
  echo "--- Removing lines $lineno to end ---"
  tail -n +"$lineno" "$file"
done

echo
read -p "Proceed with these changes? [y/N] " -r
[[ $REPLY =~ ^[Yy]$ ]] || { echo "Aborted."; exit 1; }

# Do the changes
for file in "${FILES[@]}"; do
  lineno=$(grep -n -x "EOF" "$file" | head -n1 | cut -d: -f1 || true)

  [[ -z "$lineno" ]] && continue

  # Remove from "EOF" to end
  head -n $((lineno - 1)) "$file" > "${file}.tmp"

  # Append new footer
  {
      echo "EOF"
      echo ") | less -R"
  } >> "${file}.tmp"

  mv "${file}.tmp" "$file"
done

echo "Footer fix applied to all matching files."

