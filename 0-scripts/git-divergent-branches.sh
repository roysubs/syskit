#!/bin/bash

# git-divergent-branches - A handholding tool for resolving divergent branches
# This script helps you understand what diverged and decide how to proceed

# Don't exit on error - we want to handle errors gracefully
set -u  # Exit on undefined variables
set -o pipefail  # Catch errors in pipes

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Function to print colored output
print_header() {
    echo -e "\n${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${CYAN}$1${NC}"
    echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

# Function to prompt for user input
ask_user() {
    local prompt="$1"
    # Output prompts to stderr so they show up even when stdout is captured
    echo "" >&2
    echo -e "${BOLD}${YELLOW}QUESTION:${NC} ${BOLD}$prompt${NC}" >&2
    echo -e "${CYAN}Type your answer below and press Enter:${NC}" >&2
    echo -n "> " >&2
    # Read the response
    read -r response
    # Echo response to stdout for capture
    echo "$response"
}

# Function to wait for user to press Enter
press_enter() {
    echo -e "\n${CYAN}Press Enter to continue...${NC}"
    read -r
}

# Check if we're in a git repository
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    print_error "Not a git repository!"
    exit 1
fi

# Get the git repository root and change to it
GIT_ROOT=$(git rev-parse --show-toplevel)
ORIGINAL_DIR=$(pwd)

if [ "$ORIGINAL_DIR" != "$GIT_ROOT" ]; then
    print_info "Detected you're in a subdirectory. Moving to repository root..."
    cd "$GIT_ROOT" || exit 1
    print_info "Now working from: ${GREEN}$GIT_ROOT${NC}"
    echo ""
fi

# Get current branch name
CURRENT_BRANCH=$(git branch --show-current)
if [ -z "$CURRENT_BRANCH" ]; then
    print_error "Unable to determine current branch. Are you in detached HEAD state?"
    exit 1
fi

print_header "Git Divergent Branches Helper"

echo -e "Repository: ${GREEN}$GIT_ROOT${NC}"
echo -e "Current branch: ${GREEN}$CURRENT_BRANCH${NC}"
echo -e "Remote: ${GREEN}origin/$CURRENT_BRANCH${NC}\n"

# Explain the situation
print_header "Understanding the Situation"

echo -e "${BOLD}What happened?${NC}"
echo ""
echo -e "Your local branch and the remote branch have ${YELLOW}diverged${NC}. This usually happens when:"
echo ""
echo "  1. Someone force-pushed to the remote (rewriting history)"
echo "  2. You have local commits that aren't on the remote"
echo "  3. The remote has commits that aren't in your local branch"
echo ""
echo "This creates a \"fork in the road\" that Git can't automatically resolve."
echo ""
echo -e "${BOLD}What we'll do:${NC}"
echo ""
echo "  1. First, create a safety backup of your current state"
echo "  2. Check what uncommitted changes you have (these are NOT the cause)"
echo "  3. Compare your local commits vs remote commits (THIS is the divergence)"
echo "  4. Show you exactly which files differ between branches"
echo "  5. Help you decide what to keep"
echo "  6. Resolve the divergence"
echo ""

press_enter

# Step 1: Create a backup
print_header "Step 1: Creating Safety Backup"

BACKUP_BRANCH="backup-$(date +%Y%m%d-%H%M%S)-$CURRENT_BRANCH"
git branch "$BACKUP_BRANCH"
print_success "Created backup branch: ${GREEN}$BACKUP_BRANCH${NC}"
print_info "You can always return to this state with: git checkout $BACKUP_BRANCH"

press_enter

# Step 2: Check for uncommitted changes
print_header "Step 2: Checking for Uncommitted Changes"

echo -e "${BLUE}Note:${NC} Uncommitted changes are ${BOLD}NOT${NC} the cause of branch divergence."
echo -e "They're just local edits you haven't committed yet."
echo -e "The divergence is caused by different ${BOLD}commit histories${NC} (we'll check that next)."
echo -e ""

if ! git diff-index --quiet HEAD --; then
    print_warning "You have uncommitted changes in your working directory:"
    echo ""
    git status --short
    echo ""
    echo -e "${BOLD}What are uncommitted changes?${NC}"
    echo "  • Modified files (M) - files you've edited but not committed"
    echo "  • Untracked files (??) - new files Git doesn't know about yet"
    echo ""
    echo "These won't interfere with comparing branches, but we can stash them"
    echo "temporarily to make things cleaner (you can restore them later)."
    echo ""
    
    response=$(ask_user "Would you like to temporarily stash these changes? (y/n)")
    if [[ "$response" =~ ^[Yy] ]]; then
        STASH_NAME="divergent-branches-$(date +%Y%m%d-%H%M%S)"
        git stash push -u -m "$STASH_NAME"
        print_success "Stashed changes as: $STASH_NAME"
        print_info "You can restore them later with: git stash pop"
        CHANGES_STASHED=true
    else
        print_info "OK, keeping uncommitted changes in your working directory."
        print_info "They won't affect our branch comparison."
        CHANGES_STASHED=false
    fi
else
    print_success "No uncommitted changes - working tree is clean"
    CHANGES_STASHED=false
fi

press_enter

# Step 3: Analyze commits
print_header "Step 3: Analyzing Commit Differences"

# Get the merge base
if ! MERGE_BASE=$(git merge-base HEAD origin/$CURRENT_BRANCH 2>&1); then
    print_error "Unable to find common ancestor between branches."
    print_info "This might mean the branches have completely different histories."
    echo ""
    echo "This can happen when:"
    echo "  • The remote was completely rewritten from scratch"
    echo "  • You're comparing unrelated branches"
    echo ""
    print_info "You can still compare the branches, but there's no shared history."
    MERGE_BASE=""
fi

if [ -n "$MERGE_BASE" ]; then
    # Count commits
    LOCAL_COMMITS=$(git rev-list --count $MERGE_BASE..HEAD)
    REMOTE_COMMITS=$(git rev-list --count $MERGE_BASE..origin/$CURRENT_BRANCH)

    echo -e "${BOLD}Commit Analysis:${NC}"
    echo -e "  • Common ancestor: ${CYAN}${MERGE_BASE:0:8}${NC}"
    echo -e "  • Your local commits: ${YELLOW}$LOCAL_COMMITS${NC}"
    echo -e "  • Remote commits: ${YELLOW}$REMOTE_COMMITS${NC}"
    echo ""

    if [ "$LOCAL_COMMITS" -gt 0 ]; then
        echo -e "${BOLD}Your local commits (not on remote):${NC}"
        git log --oneline --graph --decorate $MERGE_BASE..HEAD | head -20
        if [ "$LOCAL_COMMITS" -gt 20 ]; then
            echo "  ... and $((LOCAL_COMMITS - 20)) more commits"
        fi
        echo ""
    fi

    if [ "$REMOTE_COMMITS" -gt 0 ]; then
        echo -e "${BOLD}Remote commits (not in your local):${NC}"
        git log --oneline --graph --decorate $MERGE_BASE..origin/$CURRENT_BRANCH | head -20
        if [ "$REMOTE_COMMITS" -gt 20 ]; then
            echo "  ... and $((REMOTE_COMMITS - 20)) more commits"
        fi
        echo ""
    fi
else
    echo -e "${BOLD}Showing recent commits on each branch:${NC}"
    echo ""
    echo -e "${BOLD}Your local commits:${NC}"
    git log --oneline --graph --decorate HEAD | head -10
    echo ""
    echo -e "${BOLD}Remote commits:${NC}"
    git log --oneline --graph --decorate origin/$CURRENT_BRANCH | head -10
    echo ""
fi

press_enter

# Step 4: Show file differences
print_header "Step 4: Files That Differ Between Local and Remote"

echo -e "${BOLD}Comparing files...${NC}\n"

# Get list of files that differ
DIFF_FILES=$(git diff --name-only HEAD origin/$CURRENT_BRANCH | sort)

if [ -z "$DIFF_FILES" ]; then
    print_success "Good news! No files actually differ in content."
    print_info "The branches diverged in commit history, but the files are the same."
    echo ""
    echo "This usually means the remote was rebased or history was rewritten"
    echo "but the end result is identical to your local version."
else
    FILE_COUNT=$(echo "$DIFF_FILES" | wc -l)
    print_warning "Found $FILE_COUNT file(s) with differences:"
    echo ""
    echo -e "${BOLD}Legend:${NC}"
    echo -e "  ${YELLOW}[MODIFIED]${NC}        - File exists in both but with different content"
    echo -e "  ${GREEN}[NEW ON REMOTE]${NC}   - File exists on remote but not in your local version"
    echo -e "  ${RED}[DELETED ON REMOTE]${NC} - File exists locally but was deleted on remote"
    echo ""
    
    # Color code the files by type of change
    while IFS= read -r file; do
        if ! git cat-file -e origin/$CURRENT_BRANCH:"$file" 2>/dev/null; then
            echo -e "  ${RED}[DELETED ON REMOTE]${NC} $file"
        elif ! git cat-file -e HEAD:"$file" 2>/dev/null; then
            echo -e "  ${GREEN}[NEW ON REMOTE]${NC} $file"
        else
            echo -e "  ${YELLOW}[MODIFIED]${NC} $file"
        fi
    done <<< "$DIFF_FILES"
fi

echo ""
press_enter

# Step 5: Detailed file comparison
if [ -n "$DIFF_FILES" ]; then
    print_header "Step 5: Detailed File Comparison"
    
    response=$(ask_user "Would you like to compare the files one by one? (y/n)")
    
    if [[ "$response" =~ ^[Yy] ]]; then
        while IFS= read -r file; do
            echo -e "\n${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo -e "${BOLD}File: ${YELLOW}$file${NC}"
            echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
            
            # Check if file exists in both versions
            LOCAL_EXISTS=true
            REMOTE_EXISTS=true
            
            if ! git cat-file -e HEAD:"$file" 2>/dev/null; then
                LOCAL_EXISTS=false
            fi
            
            if ! git cat-file -e origin/$CURRENT_BRANCH:"$file" 2>/dev/null; then
                REMOTE_EXISTS=false
            fi
            
            if [ "$LOCAL_EXISTS" = false ]; then
                print_warning "This file doesn't exist in your local version (it's NEW on remote)"
                echo ""
                echo "Preview of remote version:"
                git show origin/$CURRENT_BRANCH:"$file" | head -30
            elif [ "$REMOTE_EXISTS" = false ]; then
                print_warning "This file doesn't exist on remote (it's DELETED there or NEW locally)"
                echo ""
                echo "Preview of your local version:"
                head -30 "$file"
            else
                echo "Showing differences (- is remote, + is your local):"
                echo ""
                git diff origin/$CURRENT_BRANCH HEAD -- "$file" | head -100
            fi
            
            echo ""
            echo -e "${BOLD}Options for this file:${NC}"
            echo "  1) Open in diff tool (if available)"
            echo "  2) View full local version"
            echo "  3) View full remote version"
            echo "  4) Skip to next file"
            echo "  5) Stop comparing files"
            
            read -p "> " file_choice
            
            case "$file_choice" in
                1)
                    if command -v vimdiff &> /dev/null; then
                        vimdiff "$file" <(git show origin/$CURRENT_BRANCH:"$file")
                    elif command -v meld &> /dev/null; then
                        git difftool -y -t meld origin/$CURRENT_BRANCH HEAD -- "$file"
                    else
                        print_warning "No diff tool found. Install vimdiff or meld."
                        git diff origin/$CURRENT_BRANCH HEAD -- "$file" | less
                    fi
                    ;;
                2)
                    if [ "$LOCAL_EXISTS" = true ]; then
                        less "$file"
                    else
                        print_error "File doesn't exist locally"
                    fi
                    ;;
                3)
                    if [ "$REMOTE_EXISTS" = true ]; then
                        git show origin/$CURRENT_BRANCH:"$file" | less
                    else
                        print_error "File doesn't exist on remote"
                    fi
                    ;;
                4)
                    continue
                    ;;
                5)
                    break
                    ;;
            esac
            
        done <<< "$DIFF_FILES"
    fi
fi

# Step 6: Decision time
print_header "Step 6: Making Your Decision"

echo -e "${BOLD}Now you need to decide how to resolve the divergence.${NC}"
echo ""
echo "You have several options:"
echo ""

echo -e "${BOLD}${GREEN}Option 1: Keep the Remote Version${NC} (Discard your local changes)"
echo -e "  Command: ${CYAN}git reset --hard origin/$CURRENT_BRANCH${NC}"
echo ""
echo "  Choose this if:"
echo "  • The remote has the correct version"
echo "  • Someone else fixed issues and force-pushed"
echo "  • You want to abandon your local work"
echo ""
echo -e "  ⚠  This will ${RED}DISCARD${NC} your local commits!"
echo -e "  ✓  Your backup is safe in branch: ${GREEN}$BACKUP_BRANCH${NC}"
echo ""

echo -e "${BOLD}${YELLOW}Option 2: Keep Your Local Version${NC} (Override the remote)"
echo -e "  Command: ${CYAN}git push --force origin $CURRENT_BRANCH${NC}"
echo ""
echo "  Choose this if:"
echo "  • Your local version is the correct one"
echo "  • You need to override bad changes on remote"
echo "  • You have permission to force-push"
echo ""
echo -e "  ⚠  This will ${RED}OVERWRITE${NC} the remote! Coordinate with your team!"
echo ""

echo -e "${BOLD}${BLUE}Option 3: Merge the Changes${NC} (Combine both versions)"
echo -e "  Command: ${CYAN}git merge origin/$CURRENT_BRANCH${NC}"
echo ""
echo "  Choose this if:"
echo "  • You want to keep both sets of changes"
echo "  • You can resolve any conflicts manually"
echo "  • Both versions have valuable work"
echo ""
echo "  ⚠  May require resolving merge conflicts"
echo ""

echo -e "${BOLD}${CYAN}Option 4: Rebase Your Changes${NC} (Replay your commits on top of remote)"
echo -e "  Command: ${CYAN}git rebase origin/$CURRENT_BRANCH${NC}"
echo ""
echo "  Choose this if:"
echo "  • You want to keep your local commits"
echo "  • You want a linear history"
echo "  • Your commits should come after the remote changes"
echo ""
echo "  ⚠  May require resolving conflicts; rewrites your local history"
echo ""

echo -e "${BOLD}${BLUE}Option 5: Do Nothing Yet${NC} (Exit and think about it)"
echo -e "  Your backup is safe in: ${GREEN}$BACKUP_BRANCH${NC}"
echo "  You can run this script again anytime"
echo ""

echo -e "${BOLD}${GREEN}Option 6: Backup Modified Files & Take Remote${NC} (Safest option!)"
echo -e "  1. Copy all your modified files to ${CYAN}${GIT_ROOT}-divergent-$(date +%Y-%m-%d_%H-%M)/${NC}"
echo -e "  2. Then run: ${CYAN}git reset --hard origin/$CURRENT_BRANCH${NC}"
echo ""
echo "  Choose this if:"
echo "  • You want to keep the remote version"
echo "  • But want to save your local modifications for reference"
echo "  • You're not sure if you'll need the local changes later"
echo ""
echo -e "  ✓  ${GREEN}Safest option${NC} - keeps everything backed up!"
echo ""

response=$(ask_user "Which option do you choose? (1/2/3/4/5/6)")

case "$response" in
    1)
        print_header "Option 1: Keeping Remote Version"
        print_warning "This will discard your local commits and match the remote exactly."
        confirm=$(ask_user "Are you absolutely sure? Type 'yes' to confirm")
        
        if [ "$confirm" = "yes" ]; then
            git reset --hard origin/$CURRENT_BRANCH
            print_success "Reset to remote version successfully!"
            print_info "Your old version is still available in: $BACKUP_BRANCH"
            
            if [ "$CHANGES_STASHED" = true ]; then
                echo ""
                stash_response=$(ask_user "Do you want to restore your stashed changes? (y/n)")
                if [[ "$stash_response" =~ ^[Yy] ]]; then
                    if git stash pop; then
                        print_success "Stashed changes restored"
                    else
                        print_error "Conflicts while restoring stash. Use 'git stash show' to see them."
                    fi
                fi
            fi
        else
            print_info "Aborted. No changes made."
        fi
        ;;
        
    2)
        print_header "Option 2: Keeping Your Local Version"
        print_warning "This will OVERWRITE the remote with your local version!"
        print_warning "Make sure you have permission and have coordinated with your team!"
        confirm=$(ask_user "Are you absolutely sure? Type 'YES I KNOW WHAT I AM DOING' to confirm")
        
        if [ "$confirm" = "YES I KNOW WHAT I AM DOING" ]; then
            print_info "Force pushing to remote..."
            git push --force origin $CURRENT_BRANCH
            print_success "Force pushed successfully!"
            print_warning "Other team members will need to reset their branches with:"
            echo "  git fetch origin"
            echo "  git reset --hard origin/$CURRENT_BRANCH"
        else
            print_info "Aborted. No changes made."
        fi
        ;;
        
    3)
        print_header "Option 3: Merging Changes"
        print_info "Attempting to merge remote changes..."
        
        if git merge origin/$CURRENT_BRANCH; then
            print_success "Merge completed successfully!"
            print_info "You can now push your changes with: git push"
        else
            print_warning "Merge conflicts detected!"
            echo ""
            echo "Files with conflicts:"
            git diff --name-only --diff-filter=U
            echo ""
            print_info "To resolve:"
            echo "  1. Edit each conflicting file"
            echo "  2. Look for <<<<<<< HEAD markers"
            echo "  3. Decide which changes to keep"
            echo "  4. Remove the conflict markers"
            echo "  5. Run: git add <file>"
            echo "  6. Run: git commit"
            echo ""
            print_info "Or to abort the merge: git merge --abort"
        fi
        ;;
        
    4)
        print_header "Option 4: Rebasing Your Changes"
        print_info "Attempting to rebase your changes onto remote..."
        
        if git rebase origin/$CURRENT_BRANCH; then
            print_success "Rebase completed successfully!"
            print_info "Your commits have been replayed on top of the remote changes"
            print_warning "You'll need to force-push: git push --force"
        else
            print_warning "Rebase conflicts detected!"
            echo ""
            echo "Files with conflicts:"
            git diff --name-only --diff-filter=U
            echo ""
            print_info "To resolve:"
            echo "  1. Edit each conflicting file"
            echo "  2. Look for <<<<<<< HEAD markers"
            echo "  3. Decide which changes to keep"
            echo "  4. Remove the conflict markers"
            echo "  5. Run: git add <file>"
            echo "  6. Run: git rebase --continue"
            echo ""
            print_info "Or to abort the rebase: git rebase --abort"
        fi
        ;;
        
    5)
        print_header "Exiting Without Changes"
        print_info "No changes were made to your repository."
        print_info "Your backup branch: $BACKUP_BRANCH"
        echo ""
        print_info "When you're ready to resolve this, run this script again or use:"
        echo "  • git reset --hard origin/$CURRENT_BRANCH  (use remote)"
        echo "  • git merge origin/$CURRENT_BRANCH         (merge both)"
        echo "  • git rebase origin/$CURRENT_BRANCH        (rebase local)"
        ;;
    
    6)
        print_header "Option 6: Backup Modified Files & Take Remote"
        
        # Create backup directory name based on repo root
        REPO_NAME=$(basename "$GIT_ROOT")
        PARENT_DIR=$(dirname "$GIT_ROOT")
        BACKUP_DIR="${PARENT_DIR}/${REPO_NAME}-divergent-$(date +%Y-%m-%d_%H-%M)"
        
        print_info "Creating backup directory: $BACKUP_DIR"
        print_info "This will backup modified files from the entire repository"
        echo ""
        mkdir -p "$BACKUP_DIR"
        
        # Get list of modified and deleted files (not new remote files)
        echo -e "${BOLD}Backing up your modified files...${NC}"
        echo ""
        
        BACKED_UP_COUNT=0
        
        # Get all files that differ
        while IFS= read -r file; do
            # Check if file exists locally (skip files that are new on remote)
            if [ -f "$file" ] || [ -d "$file" ]; then
                # Create directory structure
                FILE_DIR=$(dirname "$file")
                mkdir -p "$BACKUP_DIR/$FILE_DIR"
                
                # Copy the file
                if [ -f "$file" ]; then
                    cp "$file" "$BACKUP_DIR/$file"
                    print_success "Backed up: $file"
                    ((BACKED_UP_COUNT++))
                elif [ -d "$file" ]; then
                    cp -r "$file" "$BACKUP_DIR/$file"
                    print_success "Backed up: $file/ (directory)"
                    ((BACKED_UP_COUNT++))
                fi
            fi
        done < <(git diff --name-only HEAD origin/$CURRENT_BRANCH)
        
        # Also backup any uncommitted changes
        if ! git diff-index --quiet HEAD --; then
            echo ""
            echo -e "${BOLD}Also backing up uncommitted changes...${NC}"
            while IFS= read -r file; do
                if [ -f "$file" ]; then
                    FILE_DIR=$(dirname "$file")
                    mkdir -p "$BACKUP_DIR/$FILE_DIR"
                    cp "$file" "$BACKUP_DIR/$file"
                    print_success "Backed up uncommitted: $file"
                    ((BACKED_UP_COUNT++))
                fi
            done < <(git diff --name-only)
        fi
        
        echo ""
        print_success "Backed up $BACKED_UP_COUNT file(s) to:"
        echo -e "  ${GREEN}$BACKUP_DIR${NC}"
        echo ""
        print_info "The backup preserves the full directory structure from:"
        echo -e "  ${CYAN}$GIT_ROOT${NC}"
        echo ""
        
        # Now offer to reset
        confirm=$(ask_user "Ready to reset to remote version? Type 'yes' to confirm")
        
        if [ "$confirm" = "yes" ]; then
            git reset --hard origin/$CURRENT_BRANCH
            print_success "Reset to remote version successfully!"
            echo ""
            print_info "Your files are backed up in two places:"
            echo -e "  1. Git branch backup: ${GREEN}$BACKUP_BRANCH${NC}"
            echo -e "  2. File system backup: ${GREEN}$BACKUP_DIR${NC}"
            echo ""
            print_info "You can compare files anytime with:"
            echo "  diff $BACKUP_DIR/path/to/file path/to/file"
            echo ""
            print_info "Or browse the backed up files:"
            echo "  cd $BACKUP_DIR"
        else
            print_info "Aborted reset. Your files are backed up in: $BACKUP_DIR"
            print_info "No changes were made to your repository."
        fi
        ;;
        
    *)
        print_error "Invalid option. Exiting without changes."
        ;;
esac

echo ""
print_header "Summary"

echo -e "${BOLD}Backup Information:${NC}"
echo -e "  Backup branch: ${GREEN}$BACKUP_BRANCH${NC}"
echo -e "  View backup: ${CYAN}git log $BACKUP_BRANCH${NC}"
echo -e "  Return to backup: ${CYAN}git checkout $BACKUP_BRANCH${NC}"

if [ "$CHANGES_STASHED" = true ]; then
    echo ""
    echo -e "${BOLD}Stashed Changes:${NC}"
    echo -e "  View stash: ${CYAN}git stash list${NC}"
    echo -e "  Restore stash: ${CYAN}git stash pop${NC}"
fi

echo ""
print_success "Done! Check 'git status' to see your current state."

exit 0

