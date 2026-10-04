#!/usr/bin/env bash
if ((BASH_VERSINFO[0] < 4)); then echo "This script needs bash 4+. On macOS: brew install bash" >&2; return 1 2>/dev/null || exit 1; fi
# Author: Roy Wiseman 2025-03

echo "A high-speed arena shooter with advanced graphics and active online play."
echo "Works well on WSL in Windows (with WSLg)"

if command -v apt &>/dev/null; then
  sudo apt install xonotic
elif command -v zypper &>/dev/null; then
  echo "Xonotic is not packaged for openSUSE by this script; see https://xonotic.org/ for downloads." >&2
  exit 0
else
  echo "No supported package manager found (need apt or zypper)." >&2; exit 1
fi

