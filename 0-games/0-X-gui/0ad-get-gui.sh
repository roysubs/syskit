#!/usr/bin/env bash
if ((BASH_VERSINFO[0] < 4)); then echo "This script needs bash 4+. On macOS: brew install bash" >&2; return 1 2>/dev/null || exit 1; fi
# Author: Roy Wiseman 2025-03

echo "An open-source real-time strategy game focused on historical warfare and resource management."
echo "Works well on WSL in Windows (with WSLg)"

sudo apt install 0ad

