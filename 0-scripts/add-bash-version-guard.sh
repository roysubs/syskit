#!/usr/bin/env bash
if ((BASH_VERSINFO[0] < 4)); then echo "This script needs bash 4+. On macOS: brew install bash" >&2; return 1 2>/dev/null || exit 1; fi
# Author: Roy Wiseman 2025-01
# add-bash-version-guard.sh - Idempotently make sure every bash script in the repo has:
#   line 1: #!/usr/bin/env bash
#   line 2: a bash-4+ version guard (see README note below)
#
# Why: macOS ships an ancient bash 3.2 (Apple froze it over the GPLv3 switch) at /bin/bash.
# `#!/usr/bin/env bash` picks up a newer Homebrew bash IF one is ahead in $PATH, but that's a
# PATH-ordering hope, not a guarantee. The version guard turns a silent PATH miss into a clear
# error instead of a cryptic mid-script syntax failure on bash4+ features (declare -A, mapfile, etc).
#
# Usage: 0-scripts/add-bash-version-guard.sh [--dry-run]
# Safe to re-run any time: files that already have both lines are left untouched.

GUARD='if ((BASH_VERSINFO[0] < 4)); then echo "This script needs bash 4+. On macOS: brew install bash" >&2; return 1 2>/dev/null || exit 1; fi'

DRY_RUN=0
[[ "$1" == "--dry-run" ]] && DRY_RUN=1

repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "Not inside a git repo." >&2; exit 1; }
cd "$repo_root" || exit 1

changed=0
skipped=0

while IFS= read -r -d '' f; do
    grep -qI '' "$f" 2>/dev/null || continue   # skip binary files (avoids null-byte warnings below)
    first_line=$(head -n1 "$f" 2>/dev/null)
    [[ "$first_line" == "#!"*bash* ]] || continue

    second_line=$(sed -n '2p' "$f" 2>/dev/null)

    needs_shebang_fix=0
    [[ "$first_line" != "#!/usr/bin/env bash" ]] && needs_shebang_fix=1

    needs_guard=1
    [[ "$second_line" == *BASH_VERSINFO* ]] && needs_guard=0

    if [[ $needs_shebang_fix -eq 0 && $needs_guard -eq 0 ]]; then
        skipped=$((skipped + 1))
        continue
    fi

    echo "Fixing: $f"
    changed=$((changed + 1))
    [[ $DRY_RUN -eq 1 ]] && continue

    was_exec=0
    [ -x "$f" ] && was_exec=1

    {
        if [[ $needs_shebang_fix -eq 1 ]]; then
            echo "#!/usr/bin/env bash"
        else
            printf '%s\n' "$first_line"
        fi
        [[ $needs_guard -eq 1 ]] && printf '%s\n' "$GUARD"
        tail -n +2 "$f"
    } > "$f.bvg.tmp" && mv "$f.bvg.tmp" "$f"

    [ "$was_exec" -eq 1 ] && chmod +x "$f"
done < <(git ls-files -z)

echo
if [[ $DRY_RUN -eq 1 ]]; then
    echo "Dry run: $changed file(s) would be updated, $skipped already OK."
else
    echo "Done: $changed file(s) updated, $skipped already OK."
fi
