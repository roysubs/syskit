#!/bin/bash
# Author: Roy Wiseman 2025-04

# --- ANSI Color Codes ---
YELLOW='\033[1;33m'
GREEN='\033[1;32m'
CYAN='\033[0;36m'
MAGENTA='\033[1;35m'
BLUE_BG='\033[44;1;37m' # White text on Blue background for section titles
RED='\033[0;31m'
NC='\033[0m' # No Color

SCRIPT_NAME="${0##*/}" # Get the script's basename

# --- Helper Functions for Scenario Guides ---

print_delete_modify_conflict_guide() {
  echo -e "${YELLOW}--- Scenario: Modify/Delete Conflict ---${NC}"
  echo ""
  echo "This conflict occurs when one branch has modified a file, and another branch has deleted that same file."
  echo "You'll typically see a message like:"
  echo -e "  ${RED}CONFLICT (modify/delete): <filename> deleted in <commit_A> and modified in <commit_B (or HEAD during rebase)>.${NC}"
  # ... (rest of the function from previous version, ensuring all echos with variables use -e)
  echo -e "${CYAN}What Git Does:${NC}"
  echo "  - If the conflict happens during a ${MAGENTA}rebase${NC}: Git usually leaves the modified version from the branch you are rebasing onto (referred to as 'HEAD' in the conflict message) in your working directory."
  echo "  - If the conflict happens during a ${MAGENTA}merge${NC}: Git might also leave the modified version. Check ${GREEN}git status${NC}."
  echo "  - The operation (rebase or merge) is paused, waiting for you to resolve the conflict."
  echo ""
  echo -e "${YELLOW}How to Resolve:${NC}"
  echo "You need to decide if the file should ultimately be ${MAGENTA}kept (with its modifications)${NC} or ${MAGENTA}deleted${NC}."
  echo -e "${CYAN}1. Check Status:${NC} (${GREEN}git status${NC})"
  echo -e "${CYAN}2. Decide the Outcome:${NC}"
  echo -e "   ${MAGENTA}OPTION A: File to be DELETED:${NC}"
  echo -e "     a. Ensure file is gone: ${GREEN}git rm <filename>${NC} (this also stages the resolution)"
  echo -e "        (If you used ${GREEN}rm <filename>${NC} manually, then ${GREEN}git add <filename>${NC} to stage the deletion)"
  echo -e "   ${MAGENTA}OPTION B: File to be KEPT (modified version):${NC}"
  echo -e "     a. Ensure modified version is present. If not, you might need ${GREEN}git checkout --theirs <filename>${NC} (merge) or manually restore."
  echo -e "     b. Stage it: ${GREEN}git add <filename>${NC}"
  echo -e "${CYAN}3. Continue the Operation:${NC}"
  echo -e "   - Rebase: ${GREEN}git rebase --continue${NC}"
  echo -e "   - Merge: ${GREEN}git commit${NC} (or ${GREEN}git merge --continue${NC})"
  echo -e "${CYAN}Abort: ${NC} Rebase: ${GREEN}git rebase --abort${NC}. Merge: ${GREEN}git merge --abort${NC}."
}

print_modify_modify_conflict_guide() {
  echo -e "${YELLOW}--- Scenario: Modify/Modify Conflict (Content Conflict) ---${NC}"
  echo ""
  echo "Both branches changed the same lines in a file. Git inserts conflict markers:"
  echo -e "  ${RED}CONFLICT (content): Merge conflict in <filename>${NC}"
  echo -e "  <<<<<<< HEAD\n  (Your changes)\n  =======\n  (Their changes)\n  >>>>>>> other_branch_ref"
  # ... (rest of the function from previous version, ensuring all echos with variables use -e)
  echo ""
  echo -e "${YELLOW}How to Resolve:${NC}"
  echo -e "${CYAN}1. Check Status:${NC} (${GREEN}git status${NC}) to see conflicted files."
  echo -e "${CYAN}2. Edit the Conflicted File(s):${NC}"
  echo "   - Open each file. Look for markers (\`<<<<<<<\`, \`=======\`, \`>>>>>>>\`)."
  echo "   - Edit the content to the desired final state. ${MAGENTA}Remove all conflict marker lines.${NC}"
  echo -e "${CYAN}Tip - Quick Picks (Merge Context):${NC}"
  echo -e "   - Keep your version entirely: ${GREEN}git checkout --ours <filename>${NC} (then ${GREEN}git add <filename>${NC})"
  echo -e "   - Keep their version entirely: ${GREEN}git checkout --theirs <filename>${NC} (then ${GREEN}git add <filename>${NC})"
  echo "     (For ${MAGENTA}rebase${NC}, manual editing is often clearer unless you're certain about 'ours'/'theirs' meaning in that context)."
  echo -e "${CYAN}3. Stage the Resolved File:${NC} ${GREEN}git add <filename>${NC}"
  echo -e "${CYAN}4. Continue the Operation:${NC}"
  echo -e "   - Rebase: ${GREEN}git rebase --continue${NC}"
  echo -e "   - Merge: ${GREEN}git commit${NC} (or ${GREEN}git merge --continue${NC})"
  echo -e "${CYAN}Abort: ${NC} Rebase: ${GREEN}git rebase --abort${NC}. Merge: ${GREEN}git merge --abort${NC}."
}

print_general_overview_guide() {
  echo -e "${YELLOW}--- Guide: Understanding Git Commands for Divergence & Conflicts ---${NC}"
  echo ""
  echo "Divergence means your local branch and a remote branch have both moved forward with different commits since they last shared a common history. Conflicts can occur when Git tries to combine these histories."
  # ... (rest of the function from previous version, ensuring all echos with variables use -e)
  echo ""
  echo -e "${CYAN}Key Concepts & Commands:${NC}"
  echo -e "  - ${GREEN}git status${NC}: Your primary tool! Tells you the current branch, if you're ahead/behind, and lists conflicted files."
  echo -e "  - ${GREEN}git fetch <remote_name>${NC}: Downloads remote changes (e.g., from 'origin') but ${MAGENTA}does not change your local branch${NC}. Essential before checking divergence or merging/rebasing."
  echo -e "  - ${GREEN}git log --oneline --graph --decorate <remote_branch>..HEAD${NC}: Shows commits unique to your local branch."
  echo -e "  - ${GREEN}git log --oneline --graph --decorate HEAD..<remote_branch>${NC}: Shows commits unique to the remote branch."
  echo ""
  echo -e "${MAGENTA}Primary Strategies to Integrate Divergent Changes (after fetch):${NC}"
  echo ""
  echo -e "  ${YELLOW}1. Merge Strategy${NC} (e.g., ${GREEN}git merge <remote_tracking_branch>${NC} or ${GREEN}git pull --no-rebase${NC})"
  echo "     - ${CYAN}How it works:${NC} Creates a new 'merge commit' that joins the two histories. The original commit histories of both branches are preserved."
  echo "     - ${CYAN}Pros:${NC} Non-destructive (doesn't rewrite your existing local commits). Clearly shows merge points in history."
  echo "     - ${CYAN}Cons:${NC} Can lead to a more cluttered commit graph with many merge commits."
  echo "     - ${CYAN}Conflict Resolution:${NC}"
  echo "       1. Git pauses and lists conflicted files (check ${GREEN}git status${NC})."
  echo "       2. Edit files to resolve (remove markers, choose desired content)."
  echo -e "       3. ${GREEN}git add <resolved_file>${NC}"
  echo -e "       4. ${GREEN}git commit${NC} (Git often prepares a merge commit message) or ${GREEN}git merge --continue${NC}."
  echo -e "     - ${CYAN}Abort:${NC} ${GREEN}git merge --abort${NC} (if the merge commit hasn't been made yet)."
  echo ""
  echo -e "  ${YELLOW}2. Rebase Strategy${NC} (e.g., ${GREEN}git rebase <remote_tracking_branch>${NC} or ${GREEN}git pull --rebase${NC})"
  echo "     - ${CYAN}How it works:${NC} Takes your unique local commits, temporarily sets them aside, updates your branch to the remote's latest state, then re-applies your local commits one by one on top."
  echo "     - ${CYAN}Pros:${NC} Creates a linear, cleaner commit history (as if you did your work after the remote changes)."
  echo "     - ${CYAN}Cons:${NC} ${RED}Rewrites your local commits${NC} (they get new SHA-1 IDs). ${RED}Dangerous if you've already pushed these commits and others might have pulled them.${NC} Conflicts are resolved per-commit, which can be repetitive if many commits touch the same area."
  echo "     - ${CYAN}Conflict Resolution:${NC}"
  echo "       1. Git pauses on the first commit that causes a conflict."
  echo "       2. Edit files to resolve."
  echo -e "       3. ${GREEN}git add <resolved_file>${NC}"
  echo -e "       4. ${GREEN}git rebase --continue${NC}."
  echo -e "       5. Repeat for any subsequent conflicting commits."
  echo -e "     - ${CYAN}Abort/Skip:${NC} ${GREEN}git rebase --abort${NC} (reverts to state before rebase). ${GREEN}git rebase --skip${NC} (discards the problematic local commit entirely - use with caution!)."
  echo ""
  echo -e "${CYAN}Inspecting Differences during Conflicts:${NC}"
  echo -e "  - ${GREEN}git diff${NC}: Shows differences in conflicted files with markers."
  echo -e "  - ${GREEN}git diff --ours <filename>${NC}: Diff against 'our' version (depends on merge/rebase context)."
  echo -e "  - ${GREEN}git diff --theirs <filename>${NC}: Diff against 'their' version."
  echo -e "  - ${GREEN}git mergetool${NC}: Opens a GUI tool to help resolve conflicts if configured."
  echo ""
  echo -e "${YELLOW}General Advice:${NC}"
  echo "  - ${MAGENTA}Commit or stash local changes${NC} before running ${GREEN}git pull${NC} or other integrating commands."
  echo "  - ${MAGENTA}Fetch often, integrate often${NC} to keep divergences small and easier to manage."
  echo "  - When in doubt during a conflict, ${GREEN}git status${NC} is your best friend."
  echo -e "  - For shared branches, prefer ${MAGENTA}merge${NC}. For local cleanup before pushing a feature branch you own, ${MAGENTA}rebase${NC} is often fine."
  echo -e "  - Set a default pull strategy: ${GREEN}git config pull.rebase true${NC} (for rebase) or ${GREEN}git config pull.rebase false${NC} (for merge), or ${GREEN}git config pull.ff only${NC} (to prevent merge/rebase unless fast-forward is possible)."
}

print_detached_head_guidance() {
  echo -e "${YELLOW}--- Scenario: Help! I'm in a 'Detached HEAD' state (especially after a merge/rebase attempt) ---${NC}"
  echo ""
  echo -e "The script detected you're in a 'Detached HEAD' state. This means your current position (${GREEN}HEAD${NC}) points directly to a specific commit, not a local branch name. It's like being on a specific page of a book, not at a chapter marker."
  echo -e "If this happened after trying to resolve divergence (e.g., after a ${GREEN}git pull --rebase${NC} or ${GREEN}git merge${NC} that had conflicts), it can be confusing."
  echo ""
  echo -e "${YELLOW}Why might you be here now, and what to do?${NC}"
  echo -e "The crucial first step is to determine if the Git operation (like rebase or merge) is still active."
  echo -e "  ➡️ Run a full ${GREEN}git status${NC} (not just ${GREEN}--short${NC})."
  echo ""
  echo -e "${CYAN}Possibility 1: The Git operation (rebase/merge) IS STILL ACTIVE${NC}"
  echo -e "  ${MAGENTA}How to tell from 'git status':${NC} You'll see messages like:"
  echo -e "    - \"rebasing branch 'X' onto 'Y'\""
  echo -e "    - \"interactive rebase in progress...\" or \"You are currently editing a commit...\""
  echo -e "    - \"All conflicts fixed but you are still merging.\""
  echo -e "    - It might list files as \"unmerged paths\" if conflicts still exist for the current step, or \"changes to be committed\" if you've staged resolutions."
  echo -e "  ${MAGENTA}What your current uncommitted changes might be (from your 'git status --short' output):${NC}"
  echo "    - Your resolutions for conflicts on the *current* commit Git is trying to process."
  echo "    - Changes you made if the operation paused for an 'edit' (interactive rebase)."
  echo -e "  ${MAGENTA}What to do if the operation IS active:${NC}"
  echo -e "    1. Ensure all your intended changes for the current step are made and saved."
  echo -e "    2. Stage these changes: ${GREEN}git add -A${NC} (or specific files: ${GREEN}git add <file1> <file2>...${NC})"
  echo -e "    3. Continue the operation:"
  echo -e "       - For ${MAGENTA}rebase${NC}: ${GREEN}git rebase --continue${NC}"
  echo -e "         (If it was an 'edit' stop and you changed the commit's content/message, you might need ${GREEN}git commit --amend${NC} *before* ${GREEN}git rebase --continue${NC}. Git often guides you.)"
  echo -e "       - For ${MAGENTA}merge${NC} (if it paused mid-merge): ${GREEN}git commit${NC} (Git usually pre-fills the merge message) or ${GREEN}git merge --continue${NC} (if prompted)."
  echo -e "    ${RED}Important:${NC} Do NOT typically make a new, separate commit with ${GREEN}git commit -m \"new message\"${NC} when trying to resolve a step in an ongoing rebase/merge. You're usually amending or completing the current step."
  echo ""
  echo -e "${CYAN}Possibility 2: The Git operation is NOT ACTIVE (it finished, was aborted, or something went wrong)${NC}"
  echo -e "  ${MAGENTA}How to tell from 'git status':${NC} It will say something like \"HEAD detached at <commit_hash>\" but will ${RED}NOT${NC} mention an ongoing rebase or merge."
  echo -e "  ${MAGENTA}What your current uncommitted changes mean (from your 'git status --short' output):${NC}"
  echo "    - These are simply modifications you've made to your working files based on the specific commit you're detached on."
  echo -e "  ${MAGENTA}What to do if the operation is NOT active (and you want to save these changes):${NC}"
  echo -e "    Your instinct to ${GREEN}git add -A${NC} and ${GREEN}git commit${NC} is about *creating* the commit, which is fine. The key is to ensure this new commit isn't lost."
  echo -e "    1. ${RED}CRITICAL: Secure your work on a new branch FIRST:${NC}"
  echo -e "       ${GREEN}git checkout -b my-recovered-work${NC} (or a more descriptive branch name)"
  echo "       (This creates a new branch from your current detached HEAD state and switches to it. Your uncommitted changes come with you.)"
  echo -e "    2. Now that you are on this new branch, stage your changes:"
  echo -e "       ${GREEN}git add -A${NC}"
  echo -e "    3. Commit your work:"
  echo -e "       ${GREEN}git commit -m \"Saving changes made while HEAD was detached\"${NC}"
  echo -e "    4. Your work is now safe on the branch ${CYAN}my-recovered-work${NC}. You can then decide how to integrate this branch with your main work (e.g., ${GREEN}git checkout main; git merge my-recovered-work${NC})."
  echo ""
  echo -e "${YELLOW}If you're unsure which scenario you're in:${NC}"
  echo -e "  - The full ${GREEN}git status${NC} output is your best guide."
  echo -e "  - If still unsure, it's often safer to assume Scenario 2: create a new branch (${GREEN}git checkout -b temp-branch${NC}) to save your current file changes. If a complex operation *was* indeed active, you can abort it (${GREEN}git rebase --abort${NC} or ${GREEN}git merge --abort${NC}) and then decide how to proceed with ${CYAN}temp-branch${NC} and your main branch. This is less risky than potentially making an active rebase/merge more complicated."
  echo ""
  echo -e "Remember, the general advice in the main script output for 'Detached HEAD' (about creating a new branch if you've made commits you want to keep) also applies if you were to make commits before creating a branch in Scenario 2."
}


# --- Main Report Function ---
print_main_report() {
  echo -e "${BLUE_BG} Git Divergence & Status Report ${NC}"
  echo ""

  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo -e "${RED}Error: Not a Git repository. Aborting.${NC}"
    exit 1
  fi

  CURRENT_BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null)
  if [ -z "$CURRENT_BRANCH" ]; then
    if [ "$(git rev-parse --abbrev-ref HEAD)" = "HEAD" ]; then
      CURRENT_HEAD_COMMIT=$(git rev-parse --short HEAD)
      echo -e "${YELLOW}ℹ️ You are currently in a 'detached HEAD' state at commit ${CURRENT_HEAD_COMMIT}.${NC}"
      echo -e "  ${CYAN}What this means:${NC} Your 'HEAD' (current working position) points directly to a commit, not a local branch name."
      echo -e "  This is like having a bookmark on a specific page of a book, rather than at the end of a chapter."
      echo -e "  ${CYAN}Common ways to get here:${NC} Checking out a commit hash (${GREEN}git checkout <hash>${NC}), a tag, or a remote branch directly (${GREEN}git checkout origin/main${NC})."
      echo -e "  ${CYAN}What to know:${NC}"
      echo -e "    - It's safe for inspecting old code or making temporary experiments."
      echo -e "    - ${RED}If you make new commits now, they won't belong to any branch yet.${NC}"
      echo -e "      If you then switch to another branch (e.g., ${GREEN}git checkout main${NC}), these new commits might get lost!"
      echo -e "  ${CYAN}What to do (general advice):${NC}"
      echo -e "    - ${MAGENTA}If you just wanted to look around:${NC} Switch back to your working branch (e.g., ${GREEN}git checkout main${NC})."
      echo -e "    - ${MAGENTA}If you made new commits you want to keep:${NC} Create a new branch for them ${RED}before${NC} switching away:"
      echo -e "      ${GREEN}git branch my-new-feature ${CURRENT_HEAD_COMMIT}${NC} (creates a branch at your current commit)"
      echo -e "      ${GREEN}git checkout my-new-feature${NC} (switches to it)"
      echo -e "      (Or, in one step from detached HEAD: ${GREEN}git checkout -b my-new-feature-branch${NC})"
      echo ""
      echo -e "  ${YELLOW}If you arrived here after a merge/rebase conflict or operation:${NC}"
      echo -e "    Run a full ${GREEN}git status${NC} to check if the operation is still active."
      echo -e "    For detailed steps on what to do next in this specific situation, see:"
      echo -e "    ➡️   ${GREEN}$SCRIPT_NAME detached-head-guidance${NC}"
      echo ""
      echo -e "  This script primarily analyzes branch divergence. For that, please checkout a local branch."
      return # Skips the rest of divergence analysis
    else
      echo -e "${RED}Error: Could not determine the current branch. HEAD is not symbolic.${NC}"
      echo -e "  Please ensure you are on a local branch."
      exit 1
    fi
  fi

  # ... (rest of print_main_report from previous version, ensuring all echos with variables use -e) ...
  REMOTE_TRACKING_BRANCH=$(git for-each-ref --format='%(upstream:short)' "refs/heads/$CURRENT_BRANCH" 2>/dev/null)
  if [ -z "$REMOTE_TRACKING_BRANCH" ]; then
    echo -e "${YELLOW}Warning: No remote tracking branch configured for local branch '$CURRENT_BRANCH'.${NC}"
    echo -e "  Cannot determine divergence from a remote. You can set one using, for example:"
    echo -e "  ${GREEN}git branch $CURRENT_BRANCH --set-upstream-to=origin/$CURRENT_BRANCH${NC}"
    echo -e "  Attempting to use 'origin/$CURRENT_BRANCH' as a fallback for comparison..."
    POTENTIAL_REMOTE="origin/$CURRENT_BRANCH"
    if git show-ref --verify --quiet "refs/remotes/$POTENTIAL_REMOTE"; then
        REMOTE_TRACKING_BRANCH=$POTENTIAL_REMOTE
        echo -e "${CYAN}Found '$POTENTIAL_REMOTE'. Will use it for comparison.${NC}"
    else
        echo -e "${YELLOW}Could not find a default remote counterpart like 'origin/$CURRENT_BRANCH'.${NC}"
        echo "  Divergence analysis will be skipped. You can still use scenario guides."
        return # Skips divergence analysis
    fi
  fi

  REMOTE_NAME=$(echo "$REMOTE_TRACKING_BRANCH" | cut -d'/' -f1)

  echo -e "${CYAN}🌳 Current local branch:${NC} $CURRENT_BRANCH"
  echo -e "${CYAN}📡 Tracking remote branch:${NC} $REMOTE_TRACKING_BRANCH"
  echo ""

  echo -e "${MAGENTA}🔄 Fetching latest changes from remote '$REMOTE_NAME'...${NC}"
  if ! git fetch "$REMOTE_NAME"; then
    echo -e "${RED}Error: Failed to fetch from remote '$REMOTE_NAME'. Please check your connection and remote configuration.${NC}"
    echo -e "${YELLOW}Warning: Proceeding with potentially stale remote data for analysis.${NC}"
  fi
  echo ""

  LOCAL_SHA=$(git rev-parse HEAD 2>/dev/null)
  REMOTE_SHA=$(git rev-parse "$REMOTE_TRACKING_BRANCH" 2>/dev/null)

  if [ -z "$LOCAL_SHA" ] || [ -z "$REMOTE_SHA" ]; then
      echo -e "${RED}Error: Could not get commit IDs for local or remote branch after fetch.${NC}"
      echo -e "  Remote tracking branch '$REMOTE_TRACKING_BRANCH' might not exist on remote '$REMOTE_NAME' or is not yet fetched."
      return
  fi

  if [ "$LOCAL_SHA" = "$REMOTE_SHA" ]; then
    echo -e "${GREEN}✅ Branches '$CURRENT_BRANCH' and '$REMOTE_TRACKING_BRANCH' are in sync. No divergence.${NC}"
    echo ""
  else
    MERGE_BASE=$(git merge-base HEAD "$REMOTE_TRACKING_BRANCH" 2>/dev/null)
    if [ -z "$MERGE_BASE" ]; then
        echo -e "${RED}Error: Could not find a common ancestor between $CURRENT_BRANCH and $REMOTE_TRACKING_BRANCH.${NC}"
        echo "  This might indicate unrelated histories."
        return
    fi

    LOCAL_AHEAD_COUNT=$(git rev-list --count "$REMOTE_TRACKING_BRANCH"..HEAD)
    REMOTE_AHEAD_COUNT=$(git rev-list --count HEAD.."$REMOTE_TRACKING_BRANCH")

    if [ "$LOCAL_AHEAD_COUNT" -gt 0 ] && [ "$REMOTE_AHEAD_COUNT" -gt 0 ]; then
      echo -e "${YELLOW}⚠️ Your local branch '$CURRENT_BRANCH' has diverged from '$REMOTE_TRACKING_BRANCH'.${NC}"
      echo "  This means both branches have unique commits. A 'git pull' will require a merge or rebase."
      echo ""
      echo -e "${CYAN}🔗 Common Ancestor:${NC} $(git show --oneline -s "$MERGE_BASE")"
      echo ""
      echo -e "${YELLOW}--- Divergent Commits ---${NC}"
      echo -e "${CYAN}Local commits on '$CURRENT_BRANCH' (not on '$REMOTE_TRACKING_BRANCH'):${NC}"
      git log --oneline --decorate --color=always "$REMOTE_TRACKING_BRANCH"..HEAD
      echo ""
      echo -e "${CYAN}Remote commits on '$REMOTE_TRACKING_BRANCH' (not on '$CURRENT_BRANCH'):${NC}"
      git log --oneline --decorate --color=always HEAD.."$REMOTE_TRACKING_BRANCH"
      echo ""

      echo -e "${YELLOW}--- Affected Files (Compared to Common Ancestor) ---${NC}"
      echo -e "${CYAN}Files changed LOCALLY (in '$CURRENT_BRANCH' since common ancestor):${NC}"
      LOCAL_CHANGED_FILES=$(git diff --name-status "$MERGE_BASE"...HEAD)
      if [ -n "$LOCAL_CHANGED_FILES" ]; then echo "$LOCAL_CHANGED_FILES"; else echo "No unique local changes affecting files."; fi
      echo ""

      echo -e "${CYAN}Files changed REMOTELY (in '$REMOTE_TRACKING_BRANCH' since common ancestor):${NC}"
      REMOTE_CHANGED_FILES=$(git diff --name-status "$MERGE_BASE"...$REMOTE_TRACKING_BRANCH)
      if [ -n "$REMOTE_CHANGED_FILES" ]; then echo "$REMOTE_CHANGED_FILES"; else echo "No unique remote changes affecting files."; fi
      echo ""

      echo -e "${CYAN}Files potentially in CONFLICT or needing review (changed on both sides or overlapping):${NC}"
      CONFLICT_FILES=$( (git diff --name-only "$MERGE_BASE"...HEAD; git diff --name-only "$MERGE_BASE"...$REMOTE_TRACKING_BRANCH) | LC_ALL=C sort | uniq -d)
      if [ -n "$CONFLICT_FILES" ]; then echo "$CONFLICT_FILES"; else echo "No files directly changed on both sides according to this simple check."; fi
      echo ""
    elif [ "$LOCAL_AHEAD_COUNT" -gt 0 ]; then
      echo -e "${CYAN}ℹ️ Your local branch '$CURRENT_BRANCH' is ${LOCAL_AHEAD_COUNT} commit(s) ahead of '$REMOTE_TRACKING_BRANCH'.${NC}"
      echo -e "  Consider using ${GREEN}git push${NC} to share your changes."
      echo ""
    elif [ "$REMOTE_AHEAD_COUNT" -gt 0 ]; then
      echo -e "${CYAN}ℹ️ Your local branch '$CURRENT_BRANCH' is ${REMOTE_AHEAD_COUNT} commit(s) behind '$REMOTE_TRACKING_BRANCH'.${NC}"
      echo -e "  Consider using ${GREEN}git pull${NC} to update your local branch."
      echo "  (This will likely be a fast-forward if you have no unpushed local changes)."
      echo ""
    else
      echo -e "${GREEN}✅ Branches '$CURRENT_BRANCH' and '$REMOTE_TRACKING_BRANCH' appear to be in sync after checking commit counts.${NC}"
      echo ""
    fi
  fi

  echo -e "${YELLOW}--- Git Pull: Reconciling Divergence (Generic Advice) ---${NC}"
  echo "When 'git pull' encounters divergence (local and remote have unique commits), you must choose a strategy:"
  echo -e "  1. ${MAGENTA}Merge:${NC} (${GREEN}git pull --no-rebase${NC} or set ${GREEN}git config pull.rebase false${NC})"
  echo "     Preserves history, creates a merge commit. Safer for shared branches."
  echo -e "  2. ${MAGENTA}Rebase:${NC} (${GREEN}git pull --rebase${NC} or set ${GREEN}git config pull.rebase true${NC})"
  echo "     Linear history. Rewrites local commits. Good for unpushed changes or solo work."
  echo -e "  3. ${MAGENTA}Fast-Forward Only:${NC} (${GREEN}git pull --ff-only${NC} or set ${GREEN}git config pull.ff only${NC})"
  echo "     Safest; only updates if no divergence, otherwise fails and lets you decide."
  echo ""
}

# --- Main Script Logic ---
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo -e "${RED}Error: This script must be run from within a Git repository.${NC}"
  exit 1
fi

if [ -z "$1" ]; then
  print_main_report
else
  case "$1" in
    delete-modify)
      print_delete_modify_conflict_guide
      ;;
    modify-modify)
      print_modify_modify_conflict_guide
      ;;
    general-overview)
      print_general_overview_guide
      ;;
    detached-head-guidance)
      print_detached_head_guidance
      ;;
    *)
      echo -e "${RED}Error: Unknown scenario guide '$1'.${NC}"
      # Fall through to show available guides, so this error isn't the last thing they see.
      ;;
  esac
fi

echo "" # Add a little space before the final guide list
echo -e "${BLUE_BG} Common Conflict Resolution Scenario Guides ${NC}"
echo -e "This script helps analyze branch divergence. If you encounter a conflict after a merge or rebase,"
echo -e "or want to understand Git states and commands, you can get specific advice using these options:"
echo ""
echo -e "  ${GREEN}$SCRIPT_NAME general-overview${NC}"
echo -e "    ${CYAN}Explains:${NC} Core Git commands for divergence (fetch, log, merge, rebase) and conflict resolution basics."
echo ""
echo -e "  ${GREEN}$SCRIPT_NAME detached-head-guidance${NC}"
echo -e "    ${CYAN}Explains:${NC} What to do if you're in a 'Detached HEAD' state, especially after a merge/rebase attempt."
echo ""
echo -e "  ${GREEN}$SCRIPT_NAME delete-modify${NC}"
echo -e "    ${CYAN}Explains:${NC} How to handle when one side deletes a file and the other modifies it."
echo ""
echo -e "  ${GREEN}$SCRIPT_NAME modify-modify${NC}"
echo -e "    ${CYAN}Explains:${NC} How to resolve conflicts when both sides changed the same lines in a file (<<<<<, ======, >>>>> markers)."
echo ""
