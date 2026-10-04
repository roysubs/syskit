#!/usr/bin/env bash
if ((BASH_VERSINFO[0] < 4)); then echo "This script needs bash 4+. On macOS: brew install bash" >&2; return 1 2>/dev/null || exit 1; fi
# Author: Roy Wiseman 2025-03

echo "A transport and business simulation game inspired by the classic Transport Tycoon Deluxe."
echo "Works well on WSL in Windows (with WSLg)"

if command -v apt &>/dev/null; then
  sudo apt install openttd
elif command -v zypper &>/dev/null; then
  # openSUSE package name not verified on a live box; see https://www.openttd.org/ if this fails
  sudo zypper install -y openttd
else
  echo "No supported package manager found (need apt or zypper)." >&2; exit 1
fi

