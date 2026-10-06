#!/usr/bin/env bash
if ((BASH_VERSINFO[0] < 4)); then echo "This script needs bash 4+. On macOS: brew install bash" >&2; return 1 2>/dev/null || exit 1; fi
# Read-only health check for the syskit setup. Changes nothing, needs no sudo.
# Reports whether the modules, shell profile, PATH and help commands are in place.
# Exit 0 if there are no FAIL lines, 1 otherwise.

SYSKIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NEW_SYSTEM="$SYSKIT_DIR/0-new-system"
FAILS=0
WARNS=0
shopt -s nullglob

pass() { printf '  \033[1;32mPASS\033[0m %s\n' "$1"; }
warn() { printf '  \033[1;33mWARN\033[0m %s\n' "$1"; WARNS=$((WARNS + 1)); }
fail() { printf '  \033[1;31mFAIL\033[0m %s\n' "$1"; FAILS=$((FAILS + 1)); }

echo "== Modules"
# Sourced modules only need to be readable. Run modules need to be executable.
for f in new1-vimrc.sh new1-update-h-scripts.sh; do
    if [[ -x "$NEW_SYSTEM/$f" ]]; then pass "$f"; elif [[ -e "$NEW_SYSTEM/$f" ]]; then warn "$f is not executable"; else fail "$f is missing"; fi
done
if [[ "$(uname)" == "Darwin" ]]; then
    if [[ -x "$NEW_SYSTEM/new1-vimrc-macos.sh" ]]; then pass "new1-vimrc-macos.sh"; else fail "new1-vimrc-macos.sh is missing or not executable"; fi
fi
for f in new1-bashrc.sh new1-zshrc.sh new1-add-paths.sh; do
    if [[ -f "$NEW_SYSTEM/$f" ]]; then pass "$f"; else fail "$f is missing"; fi
done

echo "== Shell profile (login shell: ${SHELL:-unknown})"
case "$(basename "${SHELL:-}")" in
    zsh)  RC="$HOME/.zshrc";  SETUP="setup-syskit-zsh.sh" ;;
    bash) RC="$HOME/.bashrc"; SETUP="setup-syskit.sh" ;;
    *)    RC="" ; warn "syskit sets up bash and zsh only; your login shell is ${SHELL:-unknown}" ;;
esac
if [[ -n "$RC" ]]; then
    if [[ -f "$RC" ]] && grep -qF "# syskit definitions" "$RC"; then
        pass "$RC has the syskit block"
    else
        fail "$RC has no syskit block (source $SETUP)"
    fi
fi

echo "== PATH (this shell)"
for d in "$SYSKIT_DIR/0-scripts" "$SYSKIT_DIR/0-help"; do
    case ":$PATH:" in
        *":$d:"*) pass "$d" ;;
        *)        warn "$d is not on PATH here (open a new shell, or source the setup script)" ;;
    esac
done

echo "== Help commands"
help_files=("$SYSKIT_DIR"/0-help/h-*)
nonexec=0
for f in "${help_files[@]}"; do [[ -x "$f" ]] || nonexec=$((nonexec + 1)); done
if (( ${#help_files[@]} == 0 )); then
    warn "no h-* files in 0-help"
elif (( nonexec )); then
    warn "$nonexec of ${#help_files[@]} h-* files are not executable (run new1-update-h-scripts.sh)"
else
    pass "${#help_files[@]} h-* help files, all executable"
fi

echo "== Vim"
if [[ -f "$HOME/.vimrc" || -f "$HOME/.config/nvim/init.vim" ]]; then
    pass "vim or neovim config present"
else
    warn "no ~/.vimrc or nvim init.vim (run new1-vimrc.sh)"
fi

echo
if (( FAILS )); then
    echo "$FAILS failure(s), $WARNS warning(s)"
    exit 1
fi
echo "No failures, $WARNS warning(s)"
exit 0
