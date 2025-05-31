#!/usr/bin/env bash
# Author: Roy Wiseman 2025-01
# shell-conflicts.sh - Scan for shell command conflicts under ~/syskit

set -euo pipefail
shopt -s nullglob

SEARCH_DIR="${1:-$HOME/syskit}"
echo "🔍 Scanning directory: $SEARCH_DIR"

# Colors
RED=$'\e[31m'
GREEN=$'\e[32m'
YELLOW=$'\e[33m'
BOLD=$'\e[1m'
RESET=$'\e[0m'

# Collect all candidate scripts
mapfile -t script_files < <(find "$SEARCH_DIR" -type f \( -executable -o -name '*.sh' \)) # Corrected find logic slightly

printf "\n%-11s | %-20s | %s\n" "STATUS" "COMMAND" "SOURCE" # Adjusted STATUS width for "IDENTICAL"
printf -- "------------|----------------------|------------------------------\n"

for script in "${script_files[@]}"; do
  cmdname="$(basename "$script")"

  # Only test plausible shell commands (no extensions or very long names that don't match regex)
  [[ "$cmdname" =~ ^[a-zA-Z0-9_-]{1,20}$ ]] || continue

  status=""
  where=""
  # Use type -a to look for all instances
  mapfile -t matches < <(type -a "$cmdname" 2>/dev/null || true)

  if [[ ${#matches[@]} -eq 0 ]]; then
    status="${GREEN}SAFE${RESET}"
    where="not found in shell"
  else
    # Check if it's something problematic, iterating through `type -a` output
    # (which is ordered by shell's precedence)
    for m in "${matches[@]}"; do
      if [[ "$m" == *"is a shell builtin"* ]]; then
        status="${RED}BUILTIN${RESET}"
        where="$m"
        break # Builtin found, highest precedence after aliases/functions for this check
      elif [[ "$m" == *"is a function"* ]]; then
        status="${YELLOW}FUNCTION${RESET}"
        where="$m"
        break # Function found
      elif [[ "$m" == *"is an alias"* ]]; then # Aliases often take precedence
        status="${YELLOW}ALIAS${RESET}"
        where="$m"
        break # Alias found
      elif [[ "$m" == *"$script"* ]]; then
        # `type -a` resolved the command to the script file itself
        status="${GREEN}OK (yours)${RESET}"
        where="resolved to your script: $script"
        break # This script is what would be run
      else
        # Potential CLASH with an external command or other scenario.
        # $m is the line from `type -a`.
        # Examples: "cmdname is /path/to/other/cmdname"
        #           "cmdname is hashed (/path/to/other/cmdname)"

        path_from_type=""
        # Try to extract path like "/path/to/cmd" from "cmd is /path/to/cmd"
        if [[ "$m" =~ is\ (/[^[:space:]]+)$ ]]; then
            path_from_type="${BASH_REMATCH[1]}"
        # Try to extract path like "/path/to/cmd" from "cmd is hashed (/path/to/cmd)"
        elif [[ "$m" =~ is\ hashed\ \((/[^[:space:]()]+)\)$ ]]; then # Avoid matching ')', ensure path starts with /
            path_from_type="${BASH_REMATCH[1]}"
        fi

        if [[ -n "$path_from_type" && -f "$path_from_type" && -r "$path_from_type" ]]; then
          # A resolvable, readable file path was found for the conflicting command.
          # Now compare $script (our script) with $path_from_type (the one found by `type`)
          if cmp -s "$script" "$path_from_type"; then
            status="${YELLOW}IDENTICAL${RESET}"
            where="identical to $path_from_type"
          else
            status="${RED}CLASH${RESET}"
            where="$path_from_type (conflicts)"
          fi
        else
          # No comparable file path found (e.g., "is a shell keyword", path extraction failed, or not a readable file)
          # This is a generic conflict with what `type -a` reported.
          status="${RED}CLASH${RESET}"
          where="$m"
        fi
        break # Decision made based on the first conflicting entry from `type -a`
      fi
    done
  fi

  printf "%-18s | %-20s | %s\n" "$status" "$cmdname" "$where" # Adjusted width for color codes in status
done
