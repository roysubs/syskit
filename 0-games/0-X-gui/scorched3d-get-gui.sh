#!/usr/bin/env bash
if ((BASH_VERSINFO[0] < 4)); then echo "This script needs bash 4+. On macOS: brew install bash" >&2; return 1 2>/dev/null || exit 1; fi
# Author: Roy Wiseman 2025-02

echo "A 3D artillery game with destructible terrain and multiplayer support."
echo "Works well on WSL in Windows (with WSLg)"

pkg_install() {
    if command -v zypper &>/dev/null; then
        echo "scorched3d is not in openSUSE's default repositories. It is in the OBS 'games' project:"
        echo "  https://software.opensuse.org/package/scorched3d"
        echo "Add that repository, then run: sudo zypper install scorched3d"
        return 0
    else sudo apt install "$@"
    fi
}
pkg_install scorched3d

