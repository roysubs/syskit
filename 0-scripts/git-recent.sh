#!/bin/bash
# Author: Roy Wiseman 2025-05

RED='\e[0;31m'
GREEN='\e[0;32m'
YELLOW='\e[0;33m'
BLUE='\e[0;34m'
BOLD='\e[1m'
NC='\e[0m'

# Set default number of commits to show (5)
num_commits=${1:-5}
echo -e "${YELLOW}=== Files Modified/New/Deleted in the Last $num_commits Commits ===${NC}"
for commit in $(git log -n $num_commits --pretty=format:"%h"); do
    echo "Commit: $commit"
    # Get the diff status of files (new, modified, deleted)
    git show --name-status --pretty=format:"" $commit | while read status file; do
        case $status in
            A)
                echo -e "${GREEN}A${NC}: $file"
                ;;
            M)
                echo -e "${RED}M${NC}: $file"
                ;;
            D)
                echo -e "${RED}D${NC}: $file"
                ;;
            *)
                echo -e "${YELLOW}Unknown status${NC} for: $file"
                ;;
        esac
    done
    echo
done
echo -e "M (modified), A (added / new), D (deleted)"

echo -e "${YELLOW}=== Last $num_commits Commits ===${NC}"
git log -n $num_commits --pretty=format:"%cd %h - %s" --date=iso
echo
echo -e "${BOLD}Usage: ${0##*/} <NUM> (by default, shows last 5)${NC}"



