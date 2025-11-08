# Console Diff Tools Reference

A guide to modern alternatives and complements to `vimdiff` for comparing files in the terminal.

---

## Modern TUI (Terminal UI) Tools

### 1. **delta** - Syntax-highlighting pager for diffs
A beautiful syntax-highlighting pager primarily for git diff output, but can also compare files directly.

**Features:**
- Side-by-side or unified diffs with syntax highlighting
- Great for reviewing git diffs
- Highly configurable
- Works as a git pager

**Installation:**
```bash
# Via cargo
cargo install git-delta

# Debian/Ubuntu
apt install git-delta

# macOS
brew install git-delta
```

**Usage:**
```bash
# As git pager (configure in .gitconfig)
git diff | delta

# Direct file comparison
delta file1.txt file2.txt
```

**Configuration:**
Add to `~/.gitconfig`:
```ini
[core]
    pager = delta

[delta]
    side-by-side = true
    line-numbers = true
```

---

### 2. **difftastic** - Structural diff tool
Compares code by syntax tree rather than line-by-line. Understands what actually changed semantically.

**Features:**
- Syntax-aware diffing (understands code structure)
- Much better at identifying meaningful changes
- Supports 30+ programming languages
- Color-coded by syntax element

**Installation:**
```bash
# Via cargo
cargo install difftastic

# macOS
brew install difftastic
```

**Usage:**
```bash
# Basic comparison
difft file1.py file2.py

# With git
GIT_EXTERNAL_DIFF=difft git diff

# Set as default git diff tool
git config --global diff.external difft
```

**Why it's great:** Moves a function? Renames a variable? Difftastic understands these as structural changes, not hundreds of line deletions/additions.

---

### 3. **diff-so-fancy** - Enhanced git diff output
Makes standard git diff output more readable with better colors and formatting.

**Features:**
- Cleaner, more readable git diffs
- Highlights changed words within lines
- Strips unnecessary noise
- Less invasive than full alternatives

**Installation:**
```bash
# Via npm
npm install -g diff-so-fancy

# macOS
brew install diff-so-fancy
```

**Usage:**
```bash
# As git pager
git diff | diff-so-fancy

# Configure in .gitconfig
git config --global core.pager "diff-so-fancy | less --tabs=4 -RFX"
```

---

## Interactive Console Tools

### 4. **icdiff** - Side-by-side color diff (RECOMMENDED FOR BEGINNERS)
Simple, straightforward side-by-side color diff tool. No learning curve required.

**Features:**
- Clean side-by-side view with colors
- Works like `diff` but much more readable
- No vim knowledge needed
- Great for quick comparisons

**Installation:**
```bash
# Via pip
pip install icdiff

# Debian/Ubuntu
apt install icdiff

# macOS
brew install icdiff
```

**Usage:**
```bash
# Basic comparison
icdiff file1.txt file2.txt

# Show line numbers
icdiff --line-numbers file1.txt file2.txt

# Wider display
icdiff --cols=200 file1.txt file2.txt

# Use as git difftool
git difftool --extcmd icdiff
```

**Why it's great:** Zero learning curve. Just works. Perfect for quick file comparisons.

---

### 5. **ydiff** - Side-by-side viewer with incremental diff
Another side-by-side viewer, similar to icdiff but with different feature set.

**Features:**
- Side-by-side color output
- Incremental diff (shows character-level changes)
- Pager mode for scrolling through large diffs
- Column wrapping for wide lines

**Installation:**
```bash
# Via pip
pip install ydiff
```

**Usage:**
```bash
# Basic comparison
ydiff file1.txt file2.txt

# With git
git diff | ydiff

# Side-by-side with width control
ydiff -s -w 80 file1.txt file2.txt
```

---

## For Interactive Merging/Editing

### 6. **meld** - Visual diff/merge tool (requires GUI)
Graphical three-way merge tool. Excellent for resolving merge conflicts.

**Features:**
- Visual three-way merge
- Directory comparison
- Point-and-click editing
- Great for resolving git conflicts
- Requires X11/Wayland (GUI)

**Installation:**
```bash
# Debian/Ubuntu
apt install meld

# Fedora
dnf install meld

# macOS
brew install meld
```

**Usage:**
```bash
# Compare two files
meld file1.txt file2.txt

# Compare directories
meld dir1/ dir2/

# Three-way merge
meld file1.txt base.txt file2.txt

# As git mergetool
git config --global merge.tool meld
git mergetool
```

---

## Traditional Console Tools (for reference)

### Standard `diff` command
The classic Unix diff tool - always available.

```bash
# Unified format (most readable)
diff -u file1.txt file2.txt

# Side-by-side
diff -y file1.txt file2.txt

# Colored output (with colordiff)
diff -u file1.txt file2.txt | colordiff
```

### `colordiff`
Wrapper around diff that adds color.

```bash
apt install colordiff
colordiff -u file1.txt file2.txt
```

---

## Quick Comparison Table

| Tool | Learning Curve | Best For | GUI Required |
|------|---------------|----------|--------------|
| **icdiff** | None | Quick file comparisons | No |
| **delta** | Low | Git diffs, code review | No |
| **difftastic** | Low | Code structure changes | No |
| **vimdiff** | Medium | In-place editing while comparing | No |
| **ydiff** | Low | Reading diffs with paging | No |
| **meld** | Low | Visual merging, conflicts | Yes |
| **diff-so-fancy** | None | Enhancing existing git diffs | No |

---

## Recommendations by Use Case

**Just want to see differences quickly:**
→ Use `icdiff` - zero learning curve, clear output

**Working with git diffs:**
→ Use `delta` or `diff-so-fancy` as your git pager

**Comparing code and want to understand structural changes:**
→ Use `difftastic` - it understands syntax

**Need to edit while comparing:**
→ Use `vimdiff` (your current script)

**Resolving merge conflicts:**
→ Use `meld` (if GUI available) or `vimdiff`

**Want something familiar to standard diff:**
→ Use `colordiff` or `ydiff`

---

## Integration with Your Workflow

You can create wrapper scripts for different scenarios:

```bash
# Quick visual diff
alias qdiff='icdiff --line-numbers'

# Structural code diff
alias cdiff='difftastic'

# Git with better diffs
git config --global core.pager "delta --side-by-side"

# Keep your vimdiff script for editing
alias vdiff='~/syskit/0-scripts/diff-files.sh'
```

---

## Notes

- Most tools support both file and directory comparison
- Many integrate seamlessly with git as diff/merge tools
- Python-based tools (icdiff, ydiff) require Python installed
- Rust-based tools (delta, difftastic) are single binaries after compilation
- For editing capabilities, vimdiff remains one of the best console options

---

**Last Updated:** November 2025
