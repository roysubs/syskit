#!/bin/bash
# Author: Roy Wiseman 2025-05

# Git Status Explainer Script
# This script demonstrates different ways to view Git repository status
# and explains what different terms and indicators mean.

# Function to create a section header
section() {
    echo -e "\n\033[1;36m═══════════════════════════════════════════════════════════════════════════\033[0m"
    echo -e "\033[1;36m   $1\033[0m"
    echo -e "\033[1;36m═══════════════════════════════════════════════════════════════════════════\033[0m"
}

# Function to display a command, then run it
run_command() {
    echo -e "\n\033[1;33m$ $1\033[0m"
    eval "$1"
}

# Function to explain a concept
explain() {
    echo -e "\n\033[1;32m🔍 $1\033[0m"
    echo -e "\033[0;37m$2\033[0m"
}

clear -x
echo -e "\033[1;35m"
cat << "EOF"
  ____ _ _     ____  _        _
 / ___(_) |_  / ___|| |_ __ _| |_ _   _ ___
| |  _| | __| \___ \| __/ _` | __| | | / __|
| |_| | | |_   ___) | || (_| | |_| |_| \__ \
 \____|_|\__| |____/ \__\__,_|\__|\__,_|___/
EOF
echo -e "\033[0m"

section "Understanding Git Repository Status"

# Explanation of file states in Git
explain "Git File States" "In Git, files can be in several different states:

1. Tracked: Files that Git knows about.
   - Unmodified: Tracked files with no changes since the last commit.
   - Modified: Tracked files with changes that haven't been staged.
   - Staged: Modified files that have been marked for the next commit.

2. Untracked: Files that are new and Git doesn't know about yet.

3. Ignored: Files that Git has been explicitly told to ignore (via .gitignore)."

read -n1 -rsp $'Press any key to continue...\n'

# Standard Git Status
section "1. Standard Git Status Command"
explain "git status" "The standard, verbose status command. Shows detailed information about the current state of the repository."
run_command "git status"

read -n1 -rsp $'Press any key to continue...\n'

# Short Status Format
section "2. Short Status Format"
explain "git status --short (or -s)" "A more concise status display. Each line shows a file with status indicators:
- Left column: staging area status 
- Right column: working tree status
- ?? = untracked files
- A = added file
- M = modified file
- D = deleted file"
run_command "git status --short"

read -n1 -rsp $'Press any key to continue...\n'

# Porcelain Format
section "3. Porcelain Status Format"
explain "git status --porcelain" "Machine-readable format designed for scripts. Similar to --short but with guaranteed stable output format across Git versions. It uses the same status codes as the short format."
run_command "git status --porcelain"

read -n1 -rsp $'Press any key to continue...\n'

# Branch Status
section "4. Branch Status Information"
explain "git status -sb (short with branch info)" "Shows the short status format, but includes the branch name and tracking information."
run_command "git status -sb"

read -n1 -rsp $'Press any key to continue...\n'

# Verbose Status
section "5. Verbose Status Format"
explain "git status -v (verbose)" "Shows the standard status information plus the actual text diff of what has been modified. (Note: This can produce a lot of output, so we're just describing it rather than running it.)"
echo -e "\n\033[1;33m$ git status -v\033[0m"
echo -e "(Command not run - would show standard status with the full diff of changes)"

read -n1 -rsp $'Press any key to continue...\n'

# Showing Ignored Files
section "6. Showing Ignored Files"
explain "git status --ignored" "Shows files that are being ignored (via .gitignore) in addition to regular status information."
run_command "git status --ignored"

read -n1 -rsp $'Press any key to continue...\n'

# Showing Only Ignored Files
explain "git status --ignored --porcelain | grep '^!!'" "Shows only ignored files in porcelain format - this is the most reliable method."
run_command "git status --ignored --porcelain | grep '^!!' || echo 'No ignored files found'"

read -n1 -rsp $'Press any key to continue...\n'

# Different ways to see ignored files
section "7. Other Ways To See Ignored Files"
explain "git check-ignore *" "Tests which files are being ignored by Git."
echo -e "\n\033[1;33m$ find . -type f -not -path '*/\.git/*' | git check-ignore --stdin\033[0m"
find . -type f -not -path '*/\.git/*' | git check-ignore --stdin 2>/dev/null || echo 'No ignored files found or command failed'

read -n1 -rsp $'Press any key to continue...\n'

# Stashed Changes
section "8. Working with Stashed Changes"
explain "git stash list" "Shows all stashed changes in the repository."
run_command "git stash list || echo 'No stashes found'"

explain "git stash show" "Shows the changes recorded in the stash as a diff."
run_command "git stash show 2>/dev/null || echo 'No stashes to show or empty stash'"

read -n1 -rsp $'Press any key to continue...\n'

# Ensure proper error handling for both commands
echo -e "\n\033[1;32m🔍 Testing if stash exists:\033[0m"
if git stash list | grep -q .; then
    echo "Stashes found above"
else
    echo "No stashes found in this repository"
fi

read -n1 -rsp $'Press any key to continue...\n'

# Merge Conflicts
section "9. Detecting Merge Conflicts"
explain "git diff --name-only --diff-filter=U" "Lists files with merge conflicts (during a merge)."
run_command "git diff --name-only --diff-filter=U 2>/dev/null || echo 'No merge conflicts found'"

explain "Finding merge conflicts in files" "You can search for conflict markers (<<<<<<, ======, >>>>>>) in files."
echo -e "\n\033[1;33m$ grep -l -r \"<<<<<<\" .\033[0m"
# Actually run the command - it's harmless, just searches for conflict markers
grep -l -r "<<<<<<" . 2>/dev/null || echo "No conflict markers found in files"

read -n1 -rsp $'Press any key to continue...\n'

# Explaining status symbols in prompt
section "10. Understanding Status Symbols in Git Prompts"
cat << "EOF"
Common status indicators in Git-enabled prompts:

   (N+)  Staged files (green) - Files added to the index, ready to be committed
   (N-)  Unstaged changes (red) - Modified tracked files not yet staged
   (N?)  Untracked files (yellow) - New files not yet tracked by Git
    ▲N   Ahead of upstream by N commits (cyan) - Local commits not pushed yet
    ▼M   Behind upstream by M commits (magenta) - Remote commits not pulled yet

Additional symbols you might see:
    ≡   Stashed changes exist
    ✘   Merge conflicts present
    ...  Repository is dirty (has changes)
EOF

# Git Diff commands
section "10. Using Git Diff to See Changes"
explain "git diff" "Shows unstaged changes (difference between working directory and staging area)."
run_command "git diff --stat"

explain "Understanding diff statistics" "In the output above:
- The +/- signs show the relative amount of changes:
  - Green '+' signs represent added lines
  - Red '-' signs represent deleted lines
- The numbers show how many lines were added/deleted in each file
- The graph gives a visual representation of the proportion of changes"

explain "git diff --staged (or --cached)" "Shows staged changes (difference between staging area and last commit)."
run_command "git diff --staged --stat || echo 'No staged changes'"

# Checking repository status
section "11. Checking If Repository Is 'Dirty'"
explain "git status --porcelain" "If this produces any output, the repository is considered 'dirty' (has changes)."
run_command "git status --porcelain | grep -q . && echo 'Repository is dirty (has changes)' || echo 'Repository is clean (no changes)'"

# Summary
section "12. Git Status Cheatsheet"
cat << "EOF"
┌─────────────────────────────────────────────────────────────────────────────┐
│ Command                              │ Purpose                              │
├──────────────────────────────────────┼──────────────────────────────────────┤
│ git status                           │ Detailed status                      │
│ git status -s (--short)              │ Concise status                       │
│ git status --porcelain               │ Script-friendly status               │
│ git status -sb                       │ Short status with branch info        │
│ git status --ignored                 │ Show ignored files                   │
│ git status --ignored --porcelain     │ grep '^!!' │ List only ignored files │
│ git check-ignore [file]              │ Test if file is ignored              │
│ git diff                             │ Show unstaged changes                │
│ git diff --staged                    │ Show staged changes                  │
│ git stash list                       │ Show stashed changes                 │
│ git diff --name-only --diff-filter=U │ List files with conflicts            │
│ grep -r "<<<<<<" .                   │ Find conflict markers in files       │
└─────────────────────────────────────────────────────────────────────────────┘

File Status Symbols (for --short and --porcelain):
┌──────────────────────────────────────────────────────────────────┐
│ Symbol │ Meaning                                                 │
├────────┼─────────────────────────────────────────────────────────┤
│ ??     │ Untracked file                                          │
│ A      │ Added to staging area                                   │
│ M      │ Modified                                                │
│ D      │ Deleted                                                 │
│ R      │ Renamed                                                 │
│ C      │ Copied                                                  │
│ U      │ Updated but unmerged (conflict)                         │
│ !!     │ Ignored file (when using --ignored)                     │
└──────────────────────────────────────────────────────────────────┘
EOF

echo -e "\n\033[1;35mGit Status Script completed.\033[0m\n"

