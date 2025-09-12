#!/bin/bash
# Author: Roy Wiseman (rewritten by Gemini 2025-09-12)

# --- 🚦 Configuration & Setup ---
set -e # Exit immediately if a command exits with a non-zero status.

# ANSI color codes for formatted output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# --- 📝 Help & Usage Functions ---

show_simple_help() {
  echo "Usage: ${0##*/} [command] <argument>"
  echo ""
  echo "A tool to safely find and purge files from your Git repository's history."
  echo ""
  echo "Commands:"
  echo "  --search <string>    Find files in history where the path contains the string."
  echo "  --path <path>        Purge a file or directory from all of history."
  echo "  --force              Bypass safety checks when using --path (use with caution)."
  echo ""
  echo "Run with --detail for more comprehensive examples and explanations."
}

show_detailed_help() {
  echo -e "${YELLOW}Detailed Help & Examples:${NC}"
  echo ""
  echo "This script rewrites your Git history to completely remove traces of unwanted files."
  echo "This is a destructive operation, which is why this script includes safety checks and"
  echo "automatic backups."
  echo -e "${YELLOW}Note${NC}: For solo projects with a simple workflow, using '--force' is low-risk; the safety"
  echo "check primarily protects complex projects from losing local-only data like stashes or"
  echo "unpushed branches."
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
  echo "🔎 To find files in history by a partial name (handles paths with spaces):"
  echo -e "${GREEN}git rev-list --objects --all | git cat-file --batch-check='%(objecttype) %(objectname) %(rest)' | \\"
  echo -e "  awk '/^blob/ {path=\\\$3; for(i=4;i<=NF;i++){path=path \" \" \\\$i}; if(path ~ /debug\\.log/) {print \"Found: \" path \" (Blob: \" \\\$2 \")\"}}'${NC}"
  echo ""
  echo "📰 To search the *contents* of all historical files for a string (e.g., 'API_KEY'):"
  echo -e "${YELLOW}Warning: This can be very slow on large repositories.${NC}"
  echo -e "${GREEN}git rev-list --objects --all -- | git cat-file --batch-check='%(objectname)' | \\"
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
  
  # Using a tab as a field separator is robust for file paths that contain spaces.
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
      $1 == "blob" && $4 ~ search {
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

purge_history() {
  local target_path="$1"
  local force_mode="$2"

  # Heuristic check for a "fresh clone"
  if [ -f ".git/logs/HEAD" ] && [ "$force_mode" = "false" ]; then
    echo -e "${RED}Error: This does not appear to be a fresh clone.${NC}"
    echo -e "${YELLOW}Rewriting history is a destructive operation. It is highly recommended to perform this on a fresh clone of the repository."
    echo ""
    echo "  1. Finish your current work and push it."
    echo "  2. Clone the repository again into a new, temporary directory."
    echo "  3. Run this command again from within the new directory."
    echo ""
    echo -e "If you are certain you want to proceed, run the command again with the ${GREEN}--force${YELLOW} flag."
    echo -e "${YELLOW}Note${NC}: For solo projects with a simple workflow, using '--force' is low-risk; the safety"
    echo "check primarily protects complex projects from losing local-only data like stashes or"
    echo "unpushed branches."
    exit 1
  fi

  # --- 📦 Backup ---
  local project_name
  project_name=$(basename "$PROJECT_ROOT")
  local timestamp
  timestamp=$(date +'%Y-%m-%d_%H-%M-%S')
  local backup_file
  backup_file=~/"$project_name-backup-$timestamp.zip"
  
  echo "📦 This is a destructive operation. Creating a full backup of the project..."
  echo "   Source: $PROJECT_ROOT"
  echo "   Destination: $backup_file"
  
  zip -r "$backup_file" . > /dev/null
  echo -e "${GREEN}✅ Backup complete.${NC}"

  # --- 🧼 Purge Operation ---
  echo "🧹 Removing '$target_path' from Git history. This may take a while..."
  
  cp .git/config .git/config.backup
  git filter-repo --path "$target_path" --invert-paths --force
  mv .git/config.backup .git/config

  echo "🧽 Cleaning up repository..."
  rm -rf .git/refs/original/
  git reflog expire --expire=now --all
  git gc --prune=now --aggressive

  echo "🚀 Force pushing rewritten history to all remotes and tags..."
  git push origin --force --all
  git push origin --force --tags

  echo -e "${GREEN}✅ Done! All traces of '$target_path' have been removed from the repository history.${NC}"
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
  echo "Please install it (e.g., 'sudo apt install git-filter-repo')."
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
FORCE_FLAG=false

while [ "$#" -gt 0 ]; do
  case "$1" in
    --search)
      MODE="search"
      TARGET="$2"
      shift 2
      ;;
    --path)
      MODE="path"
      TARGET="$2"
      shift 2
      ;;
    --force)
      FORCE_FLAG=true
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
    purge_history "$TARGET" "$FORCE_FLAG"
    ;;
  *)
    echo -e "${RED}Error: No valid command provided.${NC}"
    show_simple_help
    exit 1
    ;;
esac
