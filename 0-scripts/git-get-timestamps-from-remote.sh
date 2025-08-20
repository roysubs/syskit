#!/bin/bash
# Author: Roy Wiseman 2025-02
set -e

echo "When you close a repo, every timestamp locally is that of the moment of the clone."
echo "Usually, it's more useful to see the modified date as they exist on the remote repo."
echo "This script will fetch the correct timestamps from the remote repo (e.g., GitHub) so"
echo "that the local copies will show when they were last modified and apply to every file"
echo "in the local repo."

# Ensure we are in the root of a Git project
if [[ ! -d .git ]]; then
  echo
  echo "Error: This script must be run in the root of a Git repository."
  exit 1
fi

# Check if the local repo differs from the remote
REMOTE_STATUS=$(git remote update >/dev/null 2>&1 && git status -uno --porcelain=v2)

if [[ -n "$REMOTE_STATUS" ]]; then
  echo "Warning: Your local repository differs from the remote."
  echo "Changes:"
  git status -s
  echo
  read -p "Do you want to continue updating timestamps? (y/n) " -r
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborting."
    exit 1
  fi
fi

# Restore timestamps
echo "Updating file timestamps..."
git ls-files -z | while IFS= read -r -d '' file; do
  touch -d "$(git log -1 --format="@%ct" -- "$file")" "$file"
done

echo "Timestamps updated successfully."
