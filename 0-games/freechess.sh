#!/usr/bin/env bash
if ((BASH_VERSINFO[0] < 4)); then echo "This script needs bash 4+. On macOS: brew install bash" >&2; return 1 2>/dev/null || exit 1; fi
# Author: Roy Wiseman 2025-03

echo "

How to play:
==========

Type 'guest' in the login section.
Then type 'getgame' to play, and type 'quit' to exit.
For more information go to:   freechess.org/QuickGuide

==========

"

telnet freechess.org 5000


