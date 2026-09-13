#!/usr/bin/env bash
if ((BASH_VERSINFO[0] < 4)); then echo "This script needs bash 4+. On macOS: brew install bash" >&2; return 1 2>/dev/null || exit 1; fi
# Author: Roy Wiseman 2025-03

echo "A transport and business simulation game inspired by the classic Transport Tycoon Deluxe."
echo "Works well on WSL in Windows (with WSLg)"

sudo apt install openttd

