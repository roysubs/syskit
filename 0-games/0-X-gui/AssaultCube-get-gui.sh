#!/usr/bin/env bash
if ((BASH_VERSINFO[0] < 4)); then echo "This script needs bash 4+. On macOS: brew install bash" >&2; return 1 2>/dev/null || exit 1; fi
# Author: Roy Wiseman 2025-05

echo "A lightweight, fast-paced first-person shooter with both single-player and multiplayer modes."
echo "Works well on WSL in Windows (with WSLg)"

if command -v apt &>/dev/null; then
  sudo apt install assaultcube
elif command -v zypper &>/dev/null; then
  echo "AssaultCube is not packaged for openSUSE by this script; see https://assault.cubers.net/ for downloads." >&2
  exit 0
else
  echo "No supported package manager found (need apt or zypper)." >&2; exit 1
fi

