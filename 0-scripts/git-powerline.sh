#!/usr/bin/env bash
# Author: Roy Wiseman 2025-03

# git-powerline.sh
# Outputs a detailed git status string, suitable for tmux status bars or shell prompts.

# --- Configuration ---
# Set to true to enable colors, false to disable
USE_COLORS=true

# Symbols (feel free to change these to icons if your font supports them)
SYM_BRANCH="" # Git branch icon (U+E0A0 from Powerline Extra Symbols) or "BR:"
SYM_AHEAD="↑"
SYM_BEHIND="↓"
SYM_STAGED="●"    # Staged changes (dot) or "S:"
SYM_UNSTAGED="✚"  # Unstaged changes (plus) or "M:"
SYM_UNTRACKED="?" # Untracked files or "U:"
SYM_CONFLICT="✘"  # Conflicts (cross) or "X:"
SYM_STASH="⚑"     # Stashes (flag) or "H:" # H for Hidden/Stashed

# Colors (adjust as needed, or set USE_COLORS=false to disable)
# Ensure your terminal supports these ANSI codes
COLOR_BRANCH='\033[0;32m'    # Green
COLOR_AHEAD='\033[0;33m'     # Yellow
COLOR_BEHIND='\033[0;31m'    # Red
COLOR_STAGED='\033[0;36m'    # Cyan
COLOR_UNSTAGED='\033[0;35m'  # Magenta
COLOR_UNTRACKED='\033[0;90m' # Dark Gray / Bright Black
COLOR_CONFLICT='\033[1;31m'  # Bold Red
COLOR_STASH='\033[0;34m'     # Blue
COLOR_SEPARATOR='\033[0;90m' # Dark Gray for separators
NC='\033[0m'                # No Color / Reset

if ! $USE_COLORS; then
    COLOR_BRANCH="" COLOR_AHEAD="" COLOR_BEHIND="" COLOR_STAGED=""
    COLOR_UNSTAGED="" COLOR_UNTRACKED="" COLOR_CONFLICT="" COLOR_STASH=""
    COLOR_SEPARATOR="" NC=""
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

# Get current branch name
current_branch_or_sha=$(git symbolic-ref --short HEAD 2>/dev/null)
if [[ -z "$current_branch_or_sha" ]]; then # Detached HEAD
    current_branch_or_sha=$(git rev-parse --short HEAD 2>/dev/null || echo "DETACHED")
    branch_name="$current_branch_or_sha"
    # Ahead/behind doesn't apply directly to detached HEAD vs a specific upstream
else
    branch_name="$current_branch_or_sha"
    # Check for upstream and get ahead/behind counts
    upstream_branch=$(git rev-parse --abbrev-ref "@{upstream}" 2>/dev/null)
    if [[ -n "$upstream_branch" ]]; then
        # Use rev-list for accurate counts
        ahead_count=$(git rev-list --count "@{upstream}..HEAD" 2>/dev/null || echo 0)
        behind_count=$(git rev-list --count "HEAD..@{upstream}" 2>/dev/null || echo 0)
    fi
fi

# 3. Get File Status Counts (Staged, Unstaged/Modified, Untracked, Conflicts)
staged_changes=0
unstaged_changes=0 # Includes modified, deleted in worktree
untracked_files=0
conflicted_files=0

# Get status for each file, one per line (porcelain v1 format)
# Exclude the header line if using 'git status --porcelain -b'
# Simpler: just use 'git status --porcelain' for file statuses
porcelain_file_statuses=$(git status --porcelain 2>/dev/null)

if [[ -n "$porcelain_file_statuses" ]]; then
    while IFS= read -r line; do
        status_xy="${line:0:2}" # First two characters define the status

        # Based on git status --porcelain documentation:
        # X shows the status of the index
        # Y shows the status of the working tree

        idx_status="${status_xy:0:1}"
        wt_status="${status_xy:1:1}"

        # Conflicts (UU, AA, DD, AU, UA, DU, UD)
        if [[ "$idx_status" == "U" || "$wt_status" == "U" || \
              "$idx_status$wt_status" == "AA" || "$idx_status$wt_status" == "DD" ]]; then
            ((conflicted_files++))
            continue # Conflicted files are not also counted as staged/unstaged in this logic
        fi

        # Untracked
        if [[ "$idx_status$wt_status" == "??" ]]; then
            ((untracked_files++))
            continue
        fi

        # Staged changes (X is M, A, D, R, C)
        # These are changes added to the index.
        if [[ "$idx_status" =~ [MADRC] ]]; then
            ((staged_changes++))
        fi

        # Unstaged changes (Y is M or D)
        # These are changes in the working tree not yet staged (or modified after staging).
        if [[ "$wt_status" =~ [MD] ]]; then
            ((unstaged_changes++))
        fi

    done <<< "$porcelain_file_statuses"
fi

# 4. Get Stash Count
stash_count=$(git rev-list --walk-reflogs refs/stash --count 2>/dev/null || echo 0)
stash_count=${stash_count##* } # Trim potential leading spaces if wc was used

# 5. Assemble the Output String
output_string=""
output_array=()

# Branch Name
if [[ -n "$branch_name" ]]; then
    output_array+=("${COLOR_BRANCH}${SYM_BRANCH}${branch_name}${NC}")
fi

# Ahead/Behind
if [[ $ahead_count -gt 0 ]]; then
    output_array+=("${COLOR_AHEAD}${SYM_AHEAD}${ahead_count}${NC}")
fi
if [[ $behind_count -gt 0 ]]; then
    output_array+=("${COLOR_BEHIND}${SYM_BEHIND}${behind_count}${NC}")
fi

# Separator if there are ahead/behind and also file stats
if [[ ( $ahead_count -gt 0 || $behind_count -gt 0 ) && \
      ( $staged_changes -gt 0 || $unstaged_changes -gt 0 || $untracked_files -gt 0 || $conflicted_files -gt 0 ) ]]; then
    output_array+=("${COLOR_SEPARATOR}|${NC}")
fi


# File Statuses
if [[ $staged_changes -gt 0 ]]; then
    output_array+=("${COLOR_STAGED}${SYM_STAGED}${staged_changes}${NC}")
fi
if [[ $unstaged_changes -gt 0 ]]; then
    output_array+=("${COLOR_UNSTAGED}${SYM_UNSTAGED}${unstaged_changes}${NC}")
fi
if [[ $untracked_files -gt 0 ]]; then
    output_array+=("${COLOR_UNTRACKED}${SYM_UNTRACKED}${untracked_files}${NC}")
fi
if [[ $conflicted_files -gt 0 ]]; then
    output_array+=("${COLOR_CONFLICT}${SYM_CONFLICT}${conflicted_files}${NC}")
fi

# Stash Count (add separator if other file stats were present)
if [[ $stash_count -gt 0 ]]; then
    if [[ $staged_changes -gt 0 || $unstaged_changes -gt 0 || $untracked_files -gt 0 || $conflicted_files -gt 0 ]]; then
        output_array+=("${COLOR_SEPARATOR}|${NC}")
    # If only branch & ahead/behind were shown, but we have stashes, add a separator if needed
    elif [[ ( ${#output_array[@]} -gt 0 ) && ! ( $staged_changes -gt 0 || $unstaged_changes -gt 0 || $untracked_files -gt 0 || $conflicted_files -gt 0 ) ]]; then
         output_array+=("${COLOR_SEPARATOR}|${NC}")
    fi
    output_array+=("${COLOR_STASH}${SYM_STASH}${stash_count}${NC}")
fi

# Join array elements with a space
if [[ ${#output_array[@]} -gt 0 ]]; then
    output_string=$(IFS=" "; echo "${output_array[*]}")
    echo -e "$output_string"
fi

exit 0
