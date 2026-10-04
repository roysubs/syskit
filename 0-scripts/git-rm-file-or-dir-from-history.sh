#!/usr/bin/env bash
if ((BASH_VERSINFO[0] < 4)); then echo "This script needs bash 4+. On macOS: brew install bash" >&2; return 1 2>/dev/null || exit 1; fi
# Author: Roy Wiseman (rewritten by Gemini 2025-09-12; safety checks hardened 2026-10-04)

# --- 🚦 Configuration & Setup ---
set -e # Exit immediately if a command exits with a non-zero status.

# ANSI color codes for formatted output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# --- 📝 Help & Usage Functions ---

show_simple_help() {
  echo "Usage: ${0##*/} [command] <argument> [options]"
  echo ""
  echo "A tool to safely find and purge files from your Git repository's history."
  echo ""
  echo "Commands:"
  echo "  --search <string>    Find files in history whose path contains the string."
  echo "  --path <path>        Purge a file or directory from all of history."
  echo ""
  echo "Options (with --path):"
  echo "  --dry-run            Run every safety check and show what would happen. Changes nothing."
  echo "  --yes                Skip the 'type the path to confirm' prompt. The push prompt is never skipped."
  echo ""
  echo "Run with --detail for more comprehensive examples and explanations."
}

show_detailed_help() {
  echo -e "${YELLOW}Detailed Help & Examples:${NC}"
  echo ""
  echo "This script rewrites your Git history to completely remove traces of unwanted files,"
  echo "then force-pushes the rewritten history to 'origin'. That is destructive and"
  echo "shared-state-affecting, so the script refuses to run unless all of these hold:"
  echo "  - the working tree is clean (no uncommitted changes)"
  echo "  - there are no stashes"
  echo "  - 'origin' is a real remote, not a local filesystem path"
  echo "  - the path actually exists in history"
  echo "It makes a zip backup of the project first, and restores .git/config even if the"
  echo "rewrite fails partway. The push needs you to type PUSH, even with --yes."
  echo ""
  echo -e "${YELLOW}Recommended workflow${NC}"
  echo "  1. Commit or stash everything, and make sure 'origin' is up to date."
  echo "  2. Run --search to confirm what matches."
  echo "  3. Run --path <path> --dry-run to see what would happen."
  echo "  4. Run --path <path> for real."
  echo ""
  echo -e "${YELLOW}--- Common Diagnostic Commands ---${NC}"
  echo ""
  echo "🔍 To view the 20 largest objects in your repository's history:"
  echo -e "${GREEN}git rev-list --objects --all | \\"
  echo -e "  git cat-file --batch-check='%(objecttype) %(objectname) %(objectsize) %(rest)' | \\"
  echo -e "  grep '^blob' | \\"
  echo -e "  sort -k3 -n -r | \\"
  echo -e "  head -n 20 | \\"
  echo -e "  awk '{path=\\\$4; for(i=5;i<=NF;i++){path=path \" \" \\\$i}; printf \"%.2f MB\\t%s\\t%s\\n\", \\\$3/1048576, \\\$2, path}'${NC}"
  echo ""
  echo "📰 To search the *contents* of all historical files for a string (e.g., 'API_KEY'):"
  echo -e "${YELLOW}Warning: This can be very slow on large repositories.${NC}"
  echo -e "${GREEN}git rev-list --objects --all | git cat-file --batch-check='%(objectname)' | \\"
  echo -e "  while read hash; do \\"
  echo -e "    if git cat-file -p \"\$hash\" 2>/dev/null | grep -q 'API_KEY'; then \\"
  echo -e "      echo \"Found 'API_KEY' in blob \$hash\"; \\"
  echo -e "    fi; \\"
  echo -e "  done${NC}"
  echo ""
}

# ---  core Logic Functions ---

search_history() {
  local search_string="$1"
  echo "🔎 Searching history for file paths containing '$search_string'..."

  # Tab-separated so paths with spaces survive. Fixed-string match (index), not regex.
  local matches
  matches=$(git rev-list --objects --all | git cat-file --batch-check='%(objecttype)	%(objectname)	%(objectsize)	%(rest)' | \
    awk -F'\t' -v search="$search_string" '
      function human_readable(bytes,     ret) {
          if (bytes < 1024) return bytes " B";
          if (bytes < 1024*1024) return sprintf("%.2f KB", bytes/1024);
          if (bytes < 1024*1024*1024) return sprintf("%.2f MB", bytes/(1024*1024));
          return sprintf("%.2f GB", bytes/(1024*1024*1024));
      }
      # $1=type, $2=hash, $3=size, $4=path
      $1 == "blob" && index($4, search) > 0 {
        size_str = human_readable($3);
        print "  - Path: " $4 " (Size: " size_str ", Hash: " $2 ")";
      }
    ')

  if [[ -n "$matches" ]]; then
    echo -e "${GREEN}Found one or more matches:${NC}"
    echo "$matches"
  else
    echo -e "${YELLOW}No files found in history matching that path.${NC}"
  fi
  echo "✅ Search complete."
}

# Refuse anything that could damage work or push somewhere unintended.
check_safe_to_purge() {
  if [[ -n "$(git status --porcelain)" ]]; then
    echo -e "${RED}Refusing: the working tree has uncommitted changes.${NC}"
    echo "Commit or stash them first, then run this again."
    exit 1
  fi
  if [[ -n "$(git stash list)" ]]; then
    echo -e "${RED}Refusing: there are stashes. They would be lost or rewritten.${NC}"
    echo "Apply or drop them first (git stash list), then run this again."
    exit 1
  fi
  local origin_url
  origin_url="$(git remote get-url origin 2>/dev/null || true)"
  if [[ -z "$origin_url" ]]; then
    echo -e "${RED}Refusing: no 'origin' remote is configured, so there is nothing to push the rewrite to.${NC}"
    exit 1
  fi
  case "$origin_url" in
    /*|./*|../*|file://*)
      echo -e "${RED}Refusing: 'origin' is a local path ($origin_url).${NC}"
      echo "Pushing the rewrite there would rewrite that other repository too."
      exit 1
      ;;
  esac
}

purge_history() {
  local target_path="$1"
  local dry_run="$2"
  local assume_yes="$3"

  check_safe_to_purge

  if [[ -z "$(git log --all --oneline -- "$target_path" | head -n 1)" ]]; then
    echo -e "${YELLOW}Nothing to do: '$target_path' does not appear anywhere in history.${NC}"
    exit 0
  fi

  local origin_url
  origin_url="$(git remote get-url origin)"
  echo "📋 Plan:"
  echo "   Remove from ALL history: $target_path"
  echo "   Then force-push the rewritten history to: $origin_url"
  echo "   Project: $PROJECT_ROOT"

  if [[ "$dry_run" == "true" ]]; then
    echo -e "${GREEN}Dry run: all checks passed. Nothing was changed.${NC}"
    exit 0
  fi

  if [[ "$assume_yes" != "true" ]]; then
    read -r -p "Type the path exactly to confirm the local rewrite ('$target_path'): " confirm_path
    if [[ "$confirm_path" != "$target_path" ]]; then
      echo -e "${YELLOW}Confirmation did not match. Nothing was changed.${NC}"
      exit 1
    fi
  fi

  # --- 📦 Backup ---
  local project_name timestamp backup_file
  project_name=$(basename "$PROJECT_ROOT")
  timestamp=$(date +'%Y-%m-%d_%H-%M-%S')
  backup_file="$HOME/$project_name-backup-$timestamp.zip"

  echo "📦 Creating a full backup first: $backup_file"
  (cd "$PROJECT_ROOT" && zip -r "$backup_file" . > /dev/null)
  echo -e "${GREEN}✅ Backup complete.${NC}"

  # --- 🧼 Purge operation (config restored on any exit, even a failed rewrite) ---
  cp .git/config .git/config.backup
  trap 'if [ -f .git/config.backup ]; then mv -f .git/config.backup .git/config; fi' EXIT

  echo "🧹 Removing '$target_path' from history. This may take a while..."
  git filter-repo --path "$target_path" --invert-paths --force

  if [ -f .git/config.backup ]; then mv -f .git/config.backup .git/config; fi
  trap - EXIT

  echo "🧽 Cleaning up repository..."
  rm -rf .git/refs/original/
  git reflog expire --expire=now --all
  git gc --prune=now --aggressive

  # --- 🚀 Push (always confirmed, even with --yes) ---
  echo -e "${RED}About to FORCE-PUSH the rewritten history to: $origin_url${NC}"
  echo "Everyone else who has this repo must re-clone or reset afterwards."
  read -r -p "Type PUSH to continue: " confirm_push
  if [[ "$confirm_push" != "PUSH" ]]; then
    echo -e "${YELLOW}Not pushed. The local history is rewritten; push later with:${NC}"
    echo "  git push --force-with-lease origin --all && git push --force-with-lease origin --tags"
    exit 0
  fi
  git push --force-with-lease origin --all
  git push --force-with-lease origin --tags

  echo -e "${GREEN}✅ Done. '$target_path' has been removed from history and the remote updated.${NC}"
  echo "Backup kept at: $backup_file"
}

# --- 🚀 Main Execution Logic ---

# 1. Navigate to Project Root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
PROJECT_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null)"

if [ -z "$PROJECT_ROOT" ]; then
  echo -e "${RED}Error: This script must be run from within a Git repository.${NC}"
  exit 1
fi
cd "$PROJECT_ROOT"

# 2. Check Dependencies
if ! command -v git-filter-repo &> /dev/null; then
  echo -e "${RED}Error: 'git-filter-repo' is not installed.${NC}"
  echo "Install it: brew install git-filter-repo (macOS) or sudo apt/zypper install git-filter-repo"
  exit 1
fi
if ! command -v zip &> /dev/null; then
  echo -e "${RED}Error: 'zip' is not installed.${NC}"
  echo "Please install it to create backups (e.g., 'sudo apt install zip')."
  exit 1
fi

# 3. Parse Arguments
if [ "$#" -eq 0 ]; then
  show_simple_help
  exit 0
fi

MODE=""
TARGET=""
DRY_RUN=false
ASSUME_YES=false

while [ "$#" -gt 0 ]; do
  case "$1" in
    --search)
      MODE="search"
      TARGET="${2:-}"
      shift 2 || shift $#
      ;;
    --path)
      MODE="path"
      TARGET="${2:-}"
      shift 2 || shift $#
      ;;
    --dry-run)
      DRY_RUN=true
      shift 1
      ;;
    --yes)
      ASSUME_YES=true
      shift 1
      ;;
    --detail|-h|--help)
      show_detailed_help
      exit 0
      ;;
    *)
      echo -e "${RED}Error: Unknown option '$1'${NC}"
      show_simple_help
      exit 1
      ;;
  esac
done

# 4. Execute Selected Mode
if [ -z "$TARGET" ]; then
  echo -e "${RED}Error: The --search and --path commands require an argument.${NC}"
  show_simple_help
  exit 1
fi

case "$MODE" in
  search)
    search_history "$TARGET"
    ;;
  path)
    purge_history "$TARGET" "$DRY_RUN" "$ASSUME_YES"
    ;;
  *)
    echo -e "${RED}Error: No valid command provided.${NC}"
    show_simple_help
    exit 1
    ;;
esac
