#!/bin/bash
# Author: Roy Wiseman 2025-03

# Function to check if gh is installed
check_gh_installed() {
  if ! command -v gh >/dev/null 2>&1; then
    echo "GitHub CLI (gh) is not installed."
    echo "Visit https://cli.github.com/ or use your package manager to install it."
    read -p "Try to install gh with apt/brew now? [y/N]: " INSTALL_CHOICE
    if [[ "$INSTALL_CHOICE" =~ ^[Yy]$ ]]; then
      if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        sudo apt install gh
      elif [[ "$OSTYPE" == "darwin"* ]]; then
        brew install gh
      else
        echo "Please install gh manually for your platform."
        exit 1
      fi
    else
      echo "Cannot continue without gh. Exiting."
      exit 1
    fi
  fi
}

# Function to check GitHub auth
check_gh_auth() {
  if ! gh auth status >/dev/null 2>&1; then
    echo "You are not authenticated with GitHub CLI."
    echo "Starting authentication..."
    gh auth login
  fi
}

# Check and install/authenticate
check_gh_installed
check_gh_auth

echo "Fetching your repositories..."

# Get repos as JSON
REPOS=$(gh repo list --limit 1000 --json name,owner,updatedAt,visibility)

# Loop through each repo
echo "$REPOS" | jq -c '.[]' | while read -r repo; do
  NAME=$(echo "$repo" | jq -r '.name')
  OWNER=$(echo "$repo" | jq -r '.owner.login')
  UPDATED=$(echo "$repo" | jq -r '.updatedAt')
  VISIBILITY=$(echo "$repo" | jq -r '.visibility')

  # Optional: get size (slow if you have many repos)
  SIZE=$(gh api "repos/$OWNER/$NAME" --jq '.size') 2>/dev/null
  SIZE_KB=$((SIZE * 1))  # Size is in KB

  echo "$OWNER/$NAME"
  echo "  Last Updated: $UPDATED"
  echo "  Size: ${SIZE_KB} KB"
  echo "  Visibility: $VISIBILITY"
  echo ""
done

