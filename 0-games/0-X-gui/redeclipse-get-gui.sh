#!/usr/bin/env bash
if ((BASH_VERSINFO[0] < 4)); then echo "This script needs bash 4+. On macOS: brew install bash" >&2; return 1 2>/dev/null || exit 1; fi
# Author: Roy Wiseman 2025-04

echo "A modern FPS with parkour elements and a variety of game modes."
echo "Works well on WSL in Windows (with WSLg)"

sudo apt install redeclipse

