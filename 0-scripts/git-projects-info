#!/bin/bash
# ~/bin/gsummaryall.sh

echo "📊 Git Summary for all repos in ~/projects"
find ~ -type d -name ".git" | while read d; do
  repo_dir="$(dirname "$d")"
  echo -e "\n🔹 $(basename "$repo_dir")"
  (cd "$repo_dir" && onefetch || echo "  Onefetch failed")
done

