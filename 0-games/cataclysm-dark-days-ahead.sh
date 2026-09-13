#!/usr/bin/env bash
if ((BASH_VERSINFO[0] < 4)); then echo "This script needs bash 4+. On macOS: brew install bash" >&2; return 1 2>/dev/null || exit 1; fi
# Author: Roy Wiseman 2025-03

# We just need to get the right console package name, which is 'cataclysm-dda-curses'

sudo apt install cataclysm-dda-curses
