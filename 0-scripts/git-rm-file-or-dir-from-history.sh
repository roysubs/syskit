#!/bin/bash
# Author: Roy Wiseman 2025-01

set -e  # Exit on error

# ---- 🛠️ Config ----
TARGET_PATH="$1"

# We must cd back to the root of the project for gitleaks detect to prevent rebase problems
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"   # Gets directory of this script
PROJECT_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
# Change to the project root directory
if [ -n "$PROJECT_ROOT" ] && [ -d "$PROJECT_ROOT" ]; then
    cd "$PROJECT_ROOT" || { echo "Error: Could not change to project root."; exit 1; }
    # echo "Changed directory to project root: $(pwd)"
else
    echo "Error: Could not determine project root. Run the script from within the repo."
    exit 1
fi

if [[ -z "$TARGET_PATH" ]]; then
    echo "
Usage: ${0##*/} <path-to-remove-from-history>

Sometimes, unwanted zip files or files containing secrets, or personal files will get trapped
in the git history due to a commit. These will bloat the size of .git in the project root, and,
if secrets are involved, GitHub Push Protection will prevent a push. You can't just undo the
commit as the commit action has embedded the unwanted file in the git history. This script will
prune any unwanted files from the repository history to help manage the size of the .git dir in
the project root and to avoid issues with GitHub Push Protection.

To view largest objects in history:

git rev-list --objects --all | \\
  git cat-file --batch-check='%(objecttype) %(objectname) %(objectsize) %(rest)' | \\
  grep '^blob' | \\
  sort -k3 -n -r | \\
  head -n 20 | \\
  awk '{printf \"%.2f MB\\t%s\\t%s\\n\", \$3/1048576, \$2, \$4}'

To view blobs that contain 'string' in the name of the file:

function git_search_name_history() { echo \"Searching history for filename: '\$1'...\"; git rev-list --objects --all | git cat-file --batch-check='%(objecttype) %(objectname) %(rest)' | awk -v search_string=\"\$1\" '/^blob/ && \$3 ~ search_string { print \"Found in path: \" \$3 \" Blob hash: \" \$2 }'; echo \"Search complete.\"; }

To view blobs that contain 'string' in the contents of the file:

function git_search_content_history() { echo "Searching history for content: '$1' \(This may take a while\)..."; git rev-list --objects --all | git cat-file --batch-check='%(objecttype) %(objectname) %(rest)' | grep '^blob' | while read type hash path; do if git cat-file -p \"\$hash\" | grep -q \"\$1\"; then echo \"Found in blob: \$hash Path(s): \$path\"; fi; done; echo \"Search complete.\"; }

"
    exit 1
fi

if ! command -v git-filter-repo &> /dev/null; then
    echo "❌ git-filter-repo is not installed."
    echo "Install it via: sudo apt install git-filter-repo"
    exit 1
fi

if [ ! -d .git ]; then
    echo "❌ This is not a Git repository."
    exit 1
fi

# ---- 📦 Backup Git config ----
echo "📦 Backing up .git/config..."
cp .git/config .git/config.backup

# ---- 🧼 Remove path from history ----
echo "🧹 Removing '$TARGET_PATH' from Git history..."
git filter-repo --path "$TARGET_PATH" --invert-paths

# ---- 🔄 Restore remote config ----
echo "♻️ Restoring Git remote config..."
cp .git/config.backup .git/config

# ---- 🧽 Cleanup ----
echo "🧽 Cleaning up reflog and garbage..."
rm -rf .git/refs/original/
git reflog expire --expire=now --all
git gc --prune=now --aggressive

# ---- ☁️ Force Push ----
echo "🚀 Force pushing to remote..."
git push origin --force --all
git push origin --force --tags

echo "✅ Done. '$TARGET_PATH' has been removed from Git history."

# git filter-repo --path "$TARGET_PATH" --invert-paths: This specific command to git filter-repo
# rewrites your Git history, excluding any commits that modify the files or directories specified
# by $TARGET_PATH. This will work for any large file, or file containing a secret, noting that it
# has to work with the full path from the root of the project (this tool will cd back to the root
# before starting, so the path might be '0-docker/bigfile.zip' or '0-scripts/file-with-secret.sh'
# would effectively remove all traces of that file from your repository's history.

# How it works: git filter-repo iterates through all commits, and for each one, it checks if the
# provided path(s) were involved. --invert-paths means "exclude any commit touching these paths."
# Thus, new commits are generated that omit any modifications to 0-new-system/hhh.txt, essentially
# making it as if the file never existed.

# The key difference: Current state vs. history: Remember, removing the file using regular Git
# commands like git rm only removes it from the current state of your branch, not from the
# historical record. git filter-repo, on the other hand, rewrites history.

# Therefore, this script can prevent all of the problems of a rebase as long as it is run before
# going part way down the rebase route. As soon as you hit a secrets issue, run this script to
# eliminate the large-file/file-with-secret-in-it, from your Git history. The GitHub Push
# Protection would then not find a secret in any subsequet push because the secret would no longer
# be present in any of the commits in the git history to be pushed.

# However, if you already had a Push Protection and have potentially modified history in other ways,
# it is crucial to verify that the file has indeed been removed from all branches and tags. After
# using this script, always double-check with commands like the above examples in this script to
# ensure that the offending file has been removed.

# function git_search_name_history() { echo "Searching history for filename: '$1'..."; git rev-list --objects --all | git cat-file --batch-check='%(objecttype) %(objectname) %(rest)' | awk -v search_string="$1" '/^blob/ && $3 ~ search_string { print "Found in path: " $3 " Blob hash: " $2 }'; echo "Search complete."; }

# function git_search_content_history() { echo "Searching history for content: '$1' (This may take a while)..."; git rev-list --objects --all | git cat-file --batch-check='%(objecttype) %(objectname) %(rest)' | grep '^blob' | while read type hash path; do if git cat-file -p "$hash" | grep -q "$1"; then echo "Found in blob: $hash Path(s): $path"; fi; done; echo "Search complete."; }

