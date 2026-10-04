#!/usr/bin/env bash
if ((BASH_VERSINFO[0] < 4)); then echo "This script needs bash 4+. On macOS: brew install bash" >&2; return 1 2>/dev/null || exit 1; fi
# Author: Roy Wiseman 2025-03

echo "A realistic and open-source flight simulator."
echo "Works well on WSL in Windows (with WSLg)"

if command -v zypper &>/dev/null; then sudo zypper install -y FlightGear
else sudo apt install flightgear
fi

