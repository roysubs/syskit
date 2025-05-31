#!/bin/bash
# Author: Roy Wiseman 2025-01

# --- Git-aware Bash prompt ---
CYAN=$(tput setaf 6)
GREEN=$(tput setaf 2)
RED=$(tput setaf 1)
YELLOW=$(tput setaf 3)
MAGENTA=$(tput setaf 5)
RESET=$(tput sgr0)
BOLD=$(tput bold)
NC=$RESET

Is_Sourced() {
    [[ "${BASH_SOURCE[0]}" != "${0}" ]]
}

print_intro() {
    echo "=== Git-Aware Bash Prompt ==="
    echo
    echo "USAGE:"
    echo "  To activate: source $0"
    echo "  To restore:  source $0 restore"
    echo "  For help:    source $0 --help"
    echo
    echo "WHAT IT SHOWS:"
    echo "  When in a git repository, displays: (branch) [normal prompt]"
    echo
    echo "GIT STATUS INDICATORS:"
    echo "  • Branch name appears in cyan"
    echo "  • Numbers show file counts:"
    echo "    - Green numbers (e.g. 2+) = staged files ready to commit"
    echo "    - Red numbers (e.g. 3-) = modified files not yet staged"
    echo "    - Yellow numbers (e.g. 1?) = untracked files"
    echo "  • Remote sync status:"
    echo "    - Cyan ▲2 = 2 commits ahead of remote"
    echo "    - Magenta ▼1 = 1 commit behind remote"
    echo
    echo "EXAMPLES:"
    echo "  (main) [user@host dir]#           - Clean main branch"
    echo "  (feature 2+ 1-) [user@host dir]#  - Feature branch: 2 staged, 1 modified"
    echo "  (main 1? ▲1) [user@host dir]#     - Main branch: 1 untracked, 1 ahead"
    echo
}

parse_git_branch() {
    git rev-parse --is-inside-work-tree &>/dev/null || return

    local branch dirty="" staged unstaged untracked ahead behind output

    branch=$(git symbolic-ref --short HEAD 2>/dev/null || git describe --tags --exact-match 2>/dev/null || git rev-parse --short HEAD)
    output=$(git status --porcelain --untracked-files=normal 2>/dev/null)

    if [ -z "${output}" ] && git rev-parse --is-inside-work-tree &>/dev/null ; then
        staged="0"
        unstaged="0"
        untracked="0"
    elif [ -n "${output}" ]; then
        staged=$(echo "${output}" | command grep -c '^[AMDRCU]')
        unstaged=$(echo "${output}" | command grep -c '^.[MD]')
        untracked=$(echo "${output}" | command awk '/^\?\?/{c++} END{print c+0}')
    else
        staged="0"
        unstaged="0"
        untracked="0"
    fi

    staged=${staged:-0}
    unstaged=${unstaged:-0}
    untracked=${untracked:-0}

    [[ "${staged}" -gt 0 ]] && dirty+=" \[\e[32m\]${staged}+\[\e[0m\]"
    [[ "${unstaged}" -gt 0 ]] && dirty+=" \[\e[31m\]${unstaged}-\[\e[0m\]"
    [[ "${untracked}" -gt 0 ]] && dirty+=" \[\e[33m\]${untracked}?\[\e[0m\]"

    if git rev-parse --abbrev-ref @{u} &>/dev/null; then
        ahead=$(git rev-list --count @{u}..HEAD 2>/dev/null)
        behind=$(git rev-list --count HEAD..@{u} 2>/dev/null)

        [[ "$ahead" -gt 0 ]] && dirty+=" \[\e[36m\]▲$ahead\[\e[0m\]"
        [[ "$behind" -gt 0 ]] && dirty+=" \[\e[35m\]▼$behind\[\e[0m\]"
    fi

    echo "(\[\e[36m\]${branch}\[\e[0m\]${dirty})"
}

# --- Store original PS1 and PROMPT_COMMAND logic ---
if ! Is_Sourced; then
    print_intro
    echo
    echo "${RED}Error: Must be sourced, not executed${NC}"
    echo
    exit 1
fi

if [ -z "${__git_aware_prompt_original_ps1+x}" ]; then
    __git_aware_prompt_original_ps1="$PS1"
fi
if [ -z "${__git_aware_prompt_original_prompt_command+x}" ]; then
    __git_aware_prompt_original_prompt_command="$PROMPT_COMMAND"
fi

restore_prompt() {
    if [ -n "${__git_aware_prompt_original_ps1+x}" ]; then
        PS1="$__git_aware_prompt_original_ps1"
        echo "Prompt restored."
    fi
    if [ -n "${__git_aware_prompt_original_prompt_command+x}" ]; then
        if [ -z "$__git_aware_prompt_original_prompt_command" ]; then
            unset PROMPT_COMMAND
        else
            PROMPT_COMMAND="$__git_aware_prompt_original_prompt_command"
        fi
    else
        unset PROMPT_COMMAND
    fi
    unset __git_aware_prompt_original_ps1 __git_aware_prompt_original_prompt_command
    unset -f parse_git_branch update_ps1 restore_prompt Is_Sourced show_usage print_intro
}

show_usage() {
    print_intro
    echo "NOTE: This script must be sourced (not executed) to modify your prompt."
    echo "The git information will appear before your normal prompt when in git repos."
}

update_ps1() {
    local git_info
    git_info="$(parse_git_branch)"

    if [[ -n "$git_info" ]]; then
        # Simple approach: find the pattern and replace it directly
        # This preserves the exact original escaping
        local new_ps1
        new_ps1="${__git_aware_prompt_original_ps1}"
        
        # Replace the pattern: \[user@host \W\]\ with \[user@host \W\] (git_info) 
        if [[ "$new_ps1" =~ ^(.*\\W\\])\\(.*) ]]; then
            local prefix="${BASH_REMATCH[1]}"
            local rest="${BASH_REMATCH[2]}"
            PS1="${prefix} ${git_info} ${rest}"
        else
            # Fallback if regex doesn't match
            PS1="${git_info} ${__git_aware_prompt_original_ps1}"
        fi
    else
        PS1="$__git_aware_prompt_original_ps1"
    fi
}

# --- Main script logic for sourcing ---
if [ "$1" = "restore" ]; then
    restore_prompt
    return 0
fi

if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    show_usage
    return 0
fi

if [ "$#" -gt 0 ] && [ "$1" != "" ]; then
    echo "Unknown option: $1" >&2
    show_usage
    return 1
fi

# If no arguments or only empty argument, activate the prompt
PROMPT_COMMAND="update_ps1${__git_aware_prompt_original_prompt_command:+;}${__git_aware_prompt_original_prompt_command}"
echo -e "Git-aware prompt ${BOLD}activated${RESET}."
