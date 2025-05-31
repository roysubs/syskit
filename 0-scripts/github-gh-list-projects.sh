#!/bin/bash
# Author: Roy Wiseman 2025-04

# Check if gh CLI is installed
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

# Check GitHub authentication
check_gh_auth() {
  if ! gh auth status >/dev/null 2>&1; then
    echo "You are not authenticated with GitHub CLI."
    echo "Starting authentication..."
    gh auth login
  fi
}

# Main logic
check_gh_installed
check_gh_auth

TARGET_USER="$1"

if [[ -z "$TARGET_USER" ]]; then
  # No username provided; get authenticated user
  TARGET_USER=$(gh api user --jq '.login')
  echo "No username provided. Using authenticated user: $TARGET_USER"
else
  echo "Listing public repositories for user: $TARGET_USER"
fi

# Fetch repos for the target user
# REPOS=$(gh repo list "$TARGET_USER" --limit 1000 --json name,owner,updatedAt,isPrivate)
REPOS=$(gh repo list "$TARGET_USER" --limit 1000 --json name,owner,updatedAt,isPrivate,description,stargazerCount,forkCount,isArchived,primaryLanguage)

# Check if jq is installed
if ! command -v jq >/dev/null 2>&1; then
  echo "The 'jq' tool is required but not installed. Please install it."
  exit 1
fi

# Display repo info
echo "$REPOS" | jq -c '.[]' | while read -r repo; do
  NAME=$(echo "$repo" | jq -r '.name')
  OWNER=$(echo "$repo" | jq -r '.owner.login')
  UPDATED=$(echo "$repo" | jq -r '.updatedAt')
  IS_PRIVATE=$(echo "$repo" | jq -r '.isPrivate')
  VISIBILITY=$([[ "$IS_PRIVATE" == "true" ]] && echo "Private" || echo "Public")
  DESCRIPTION=$(echo "$repo" | jq -r '.description // "No description"')
  STARS=$(echo "$repo" | jq -r '.stargazerCount')
  FORKS=$(echo "$repo" | jq -r '.forkCount')
  ARCHIVED=$(echo "$repo" | jq -r '.isArchived')
  LANGUAGE=$(echo "$repo" | jq -r '.primaryLanguage.name // "Unknown"')

  # Get size (only if authenticated and accessing own repos)
  SIZE="?"
  if [[ "$OWNER" == "$TARGET_USER" ]] && [[ -z "$1" ]]; then
    SIZE=$(gh api "repos/$OWNER/$NAME" --jq '.size' 2>/dev/null || echo "?")
  fi

  SIZE_KB=$([[ "$SIZE" =~ ^[0-9]+$ ]] && echo "$((SIZE * 1))" || echo "?")

  echo "$OWNER/$NAME"
  echo "  Description : $DESCRIPTION"
  echo "  Language    : $LANGUAGE"
  echo "  Stars       : $STARS   Forks: $FORKS"
  echo "  Last Updated: $UPDATED"
  echo "  Archived    : $ARCHIVED"
  echo "  Size        : ${SIZE_KB} KB"
  echo "  Visibility  : $VISIBILITY"
  echo ""

  echo ""
done

