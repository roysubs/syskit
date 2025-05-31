#!/usr/bin/env bash
# Author: Roy Wiseman 2025-05

# git-powerline-tmux.sh
# Outputs a detailed git status string, suitable for tmux status bars or shell prompts,
# using tmux color codes.

# --- Configuration ---
# Set to true to enable colors, false to disable
USE_COLORS=true

# !!! CHOOSE YOUR GIT SEGMENT BACKGROUND COLOR HERE !!!
# Examples: "black", "colour237" (dark grey), "blue", "default" (to use tmux default status bg)
# If you leave this empty (GIT_SEGMENT_BG_COLOR=""), no specific background will be set by this script
# for the git segment, and it will likely inherit Dracula's default segment background.
GIT_SEGMENT_BG_COLOR="colour237"

# Symbols (feel free to change these to icons if your font supports them)
SYM_BRANCH="" # Git branch icon (U+E0A0 from Powerline Extra Symbols) or "BR:"
SYM_AHEAD="↑"
SYM_BEHIND="↓"
SYM_STAGED="●"    # Staged changes (dot) or "S:"
SYM_UNSTAGED="✚"  # Unstaged changes (plus) or "M:"
SYM_UNTRACKED="?" # Untracked files or "U:"
SYM_CONFLICT="✘"  # Conflicts (cross) or "X:"
SYM_STASH="⚑"     # Stashes (flag) or "H:" # H for Hidden/Stashed

# Construct the background string part for tmux color codes
_TMUX_BG_STRING=""
if [[ -n "$GIT_SEGMENT_BG_COLOR" ]]; then
    _TMUX_BG_STRING=",bg=${GIT_SEGMENT_BG_COLOR}"
fi

# Tmux Color Definitions (now including the background)
# Format: #[fg=color,bg=color,attributes]
_TMUX_COLOR_BRANCH="#[fg=green${_TMUX_BG_STRING}]"
_TMUX_COLOR_AHEAD="#[fg=yellow${_TMUX_BG_STRING}]"
_TMUX_COLOR_BEHIND="#[fg=red${_TMUX_BG_STRING}]"
_TMUX_COLOR_STAGED="#[fg=cyan${_TMUX_BG_STRING}]"
_TMUX_COLOR_UNSTAGED="#[fg=colour210${_TMUX_BG_STRING}]"
_TMUX_COLOR_UNTRACKED="#[fg=white${_TMUX_BG_STRING}]"
_TMUX_COLOR_CONFLICT="#[fg=red,bold${_TMUX_BG_STRING}]"
_TMUX_COLOR_STASH="#[fg=blue${_TMUX_BG_STRING}]"
_TMUX_COLOR_SEPARATOR="#[fg=brightblack${_TMUX_BG_STRING}]" # For separators like '|'

# Shell variables to hold the color codes (or be empty if USE_COLORS=false)
COLOR_BRANCH=""
COLOR_AHEAD=""
COLOR_BEHIND=""
COLOR_STAGED=""
COLOR_UNSTAGED=""
COLOR_UNTRACKED=""
COLOR_CONFLICT=""
COLOR_STASH=""
COLOR_SEPARATOR=""
COLOR_DEFAULT="#[default]" # Tmux default reset

if $USE_COLORS; then
    COLOR_BRANCH=$_TMUX_COLOR_BRANCH
    COLOR_AHEAD=$_TMUX_COLOR_AHEAD
    COLOR_BEHIND=$_TMUX_COLOR_BEHIND
    COLOR_STAGED=$_TMUX_COLOR_STAGED
    COLOR_UNSTAGED=$_TMUX_COLOR_UNSTAGED
    COLOR_UNTRACKED=$_TMUX_COLOR_UNTRACKED
    COLOR_CONFLICT=$_TMUX_COLOR_CONFLICT
    COLOR_STASH=$_TMUX_COLOR_STASH
    COLOR_SEPARATOR=$_TMUX_COLOR_SEPARATOR
else
    COLOR_DEFAULT="" # No reset needed if no colors used
fi

# --- Main Logic ---

# 1. Check if inside a git repository
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    exit 0 # Not a git repo, output nothing
fi

# 2. Get Branch and Ahead/Behind Information
branch_name=""
ahead_count=0
behind_count=0

current_branch_or_sha=$(git symbolic-ref --short HEAD 2>/dev/null)
if [[ -z "$current_branch_or_sha" ]]; then # Detached HEAD
    current_branch_or_sha=$(git rev-parse --short HEAD 2>/dev/null || echo "DETACHED")
    branch_name="$current_branch_or_sha"
else
    branch_name="$current_branch_or_sha"
    upstream_branch=$(git rev-parse --abbrev-ref "@{upstream}" 2>/dev/null)
    if [[ -n "$upstream_branch" ]]; then
        ahead_count=$(git rev-list --count "@{upstream}..HEAD" 2>/dev/null || echo 0)
        behind_count=$(git rev-list --count "HEAD..@{upstream}" 2>/dev/null || echo 0)
    fi
fi

# 3. Get File Status Counts
staged_changes=0
unstaged_changes=0
untracked_files=0
conflicted_files=0

porcelain_file_statuses=$(git status --porcelain 2>/dev/null)
if [[ -n "$porcelain_file_statuses" ]]; then
    while IFS= read -r line; do
        status_xy="${line:0:2}"
        idx_status="${status_xy:0:1}"
        wt_status="${status_xy:1:1}"

        if [[ "$idx_status" == "U" || "$wt_status" == "U" || \
              "$idx_status$wt_status" == "AA" || "$idx_status$wt_status" == "DD" ]]; then
            ((conflicted_files++))
            continue
        fi
        if [[ "$idx_status$wt_status" == "??" ]]; then
            ((untracked_files++))
            continue
        fi
        if [[ "$idx_status" =~ [MADRC] ]]; then
            ((staged_changes++))
        fi
        if [[ "$wt_status" =~ [MD] ]]; then # M=modified, D=deleted in worktree
            ((unstaged_changes++))
        fi
    done <<< "$porcelain_file_statuses"
fi

# 4. Get Stash Count
stash_count=$(git rev-list --walk-reflogs refs/stash --count 2>/dev/null || echo 0)
stash_count=${stash_count##* } # Trim potential leading spaces from command output

# 5. Assemble the Output String
output_array=()

# Branch Name
if [[ -n "$branch_name" ]]; then
    output_array+=("${COLOR_BRANCH}${SYM_BRANCH}${branch_name}")
fi

# Ahead/Behind
if [[ $ahead_count -gt 0 ]]; then
    output_array+=("${COLOR_AHEAD}${SYM_AHEAD}${ahead_count}")
fi
if [[ $behind_count -gt 0 ]]; then
    output_array+=("${COLOR_BEHIND}${SYM_BEHIND}${behind_count}")
fi

# Separator for file stats (only if branch/remote stats exist AND file stats exist)
if [[ ( -n "$branch_name" || $ahead_count -gt 0 || $behind_count -gt 0 ) && \
      ( $staged_changes -gt 0 || $unstaged_changes -gt 0 || $untracked_files -gt 0 || $conflicted_files -gt 0 ) ]]; then
    output_array+=("${COLOR_SEPARATOR}|")
fi

# File Statuses
if [[ $staged_changes -gt 0 ]]; then
    output_array+=("${COLOR_STAGED}${SYM_STAGED}${staged_changes}")
fi
if [[ $unstaged_changes -gt 0 ]]; then
    output_array+=("${COLOR_UNSTAGED}${SYM_UNSTAGED}${unstaged_changes}")
fi
if [[ $untracked_files -gt 0 ]]; then
    output_array+=("${COLOR_UNTRACKED}${SYM_UNTRACKED}${untracked_files}")
fi
if [[ $conflicted_files -gt 0 ]]; then
    output_array+=("${COLOR_CONFLICT}${SYM_CONFLICT}${conflicted_files}")
fi

# Stash Count (add separator if needed)
if [[ $stash_count -gt 0 ]]; then
    # Add separator if any previous segment was added AND there wasn't already a separator just before file stats
    # This logic ensures a separator before stashes if stashes are present and *any* other info is present.
    add_stash_separator=false
    if [[ ${#output_array[@]} -gt 0 ]]; then # If anything is already in the array
        # Check if the last element was already the file stats separator
        # This is a bit tricky; simpler to just add if output_array is not empty and last char isn't "|"
        # For simplicity here: add separator if other file stats were present, or if only branch info was present.
        if [[ $staged_changes -gt 0 || $unstaged_changes -gt 0 || $untracked_files -gt 0 || $conflicted_files -gt 0 ]]; then
             add_stash_separator=true
        elif [[ ( -n "$branch_name" || $ahead_count -gt 0 || $behind_count -gt 0 ) ]]; then
             add_stash_separator=true
        fi
    fi
    if $add_stash_separator && [[ ! " ${output_array[*]} " =~ " ${COLOR_SEPARATOR}| " ]]; then # Avoid double separator if file stats sep was already added
         # More robustly, check if last element is already a separator if more fine-grained logic is needed.
         # For now, if there were file stats OR branch stats, and we have stashes, ensure a separator.
         # This specific separator logic before stash might need refinement based on desired aesthetics.
         # The original script had a complex condition. Let's simplify to: if output_array is not empty, add separator.
         if [[ ${#output_array[@]} -gt 0 && "${output_array[-1]}" != "${COLOR_SEPARATOR}|" ]]; then # Check last element
            output_array+=("${COLOR_SEPARATOR}|")
         fi
    fi
    output_array+=("${COLOR_STASH}${SYM_STASH}${stash_count}")
fi

# Join array elements with a space
if [[ ${#output_array[@]} -gt 0 ]]; then
    output_string=$(IFS=" "; echo "${output_array[*]}")
    # The COLOR_* variables already contain the full #[...] tags including background.
    # The COLOR_DEFAULT will reset fg/bg to tmux defaults.
    echo -n "${output_string}${COLOR_DEFAULT}"
fi

exit 0
