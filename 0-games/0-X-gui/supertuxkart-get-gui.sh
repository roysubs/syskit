#!/usr/bin/env bash
if ((BASH_VERSINFO[0] < 4)); then echo "This script needs bash 4+. On macOS: brew install bash" >&2; return 1 2>/dev/null || exit 1; fi
# Author: Roy Wiseman 2025-04

echo "A fun, kart-racing game similar to Mario Kart, with a variety of tracks and characters from open-source projects."
echo "Works well on WSL in Windows (with WSLg)"

sudo apt install supertuxkart

