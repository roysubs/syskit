#!/usr/bin/env bash
if ((BASH_VERSINFO[0] < 4)); then echo "This script needs bash 4+. On macOS: brew install bash" >&2; return 1 2>/dev/null || exit 1; fi
# Author: Roy Wiseman 2025-01

echo "A strategy game inspired by Sid Meier's Colonization."
echo "Works well on WSL in Windows (with WSLg)"

pkg_install() {
    if command -v zypper &>/dev/null; then
        echo "freecol is not in openSUSE's default repositories. It is in the OBS 'games' project:"
        echo "  https://software.opensuse.org/package/freecol"
        echo "Add that repository, then run: sudo zypper install freecol"
        return 0
    else sudo apt install "$@"
    fi
}
pkg_install freecol

