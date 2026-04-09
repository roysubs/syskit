# Syskit macOS Compatibility & Setup Guide

While Syskit is designed to be highly portable across Linux distributions (Debian, Ubuntu, Red Hat, Arch, etc.), **macOS** presents unique challenges due to its aging shell version and BSD-based command-line utilities.

This guide outlines the core issues and provides a "Best Practice" setup to make your Mac behave like a modern Linux system.

### Summary A: "Vanilla" macOS Script Compatibility (Defensive Coding)
*Use these rules when writing scripts that must run "out of the box" on any Mac without extra tools.*
*   **Use `printf` instead of `echo`**: This is the #1 way to avoid broken formatting and escape sequence bugs.
*   **Avoid Bash 4+ Features**: No associative arrays (`declare -A`), mapfiles, or lowercase operators (`${var,,}`).
*   **Portable `sed -i`**: Use the `[[ "$OSTYPE" == "darwin"* ]]` check or pipe to a temp file and `mv`.
*   **Quoting**: Always use `"$VAR"` to handle the frequent spaces in macOS paths (e.g., `OneDrive`, `Application Support`).
*   **Shebang**: Use `#!/usr/bin/env bash` to find the best available Bash in the user's path.

### Summary B: The "Pro Linux" Environment (Homebrew & GNUtools Integration)
*Use these steps when you want to make your local Mac environment behave like a standard Linux machine.*
*   **Install `coreutils`**: Provides the GNU versions of `ls`, `cp`, `mv`, etc. (plus `find`, `sed`, `grep`).
*   **Install Modern Bash**: Use `brew install bash` to get Bash 5.x and set it as your default.
*   **Path Hijacking**: Add the `gnubin` directories to the *start* of your `PATH` so `grep` calls GNU grep instead of BSD.
*   **Shebang Mapping**: Map `/bin/bash` calls to your new Homebrew version where possible.

---

## 1. The Core Challenges

### A. The "Ancient" Bash Version
macOS ships with **Bash 3.2** (released in 2007). Apple stops at this version because newer versions of Bash moved to the **GPLv3 license**, which Apple avoids.
*   **The Problem**: Many modern shell features (like associative arrays, improved regex, and certain process substitution behaviors) work differently or fail entirely on Bash 3.2.
*   **Example**: We recently saw that Bash 3.2 cannot correctly parse single quotes inside a process substitution `<(cat <<'EOF' ...)`, which is a staple of the `h-` help scripts.

### B. BSD vs. GNU Utilities
Linux systems use **GNU Coreutils**, while macOS uses **BSD Utilities**. They share names but often disagree on syntax:
*   **`sed`**: On Linux, `sed -i` works directly. On Mac, it requires an extension (e.g., `sed -i ''`).
*   **`grep`**: GNU grep has powerful recursive and perl-regex features that BSD grep lacks.
*   **`echo`**: `echo -e` behavior can vary wildly between versions, leading to broken formatting in menus.
*   **`find`**: The arguments for time, depth, and execution differ slightly.

### C. Zsh as the Default Shell
Since macOS Catalina, **Zsh** is the default interactive shell. 
*   **Globbing**: Zsh is much "stricter" with globs. If you type `ls h-*` and no files match, Zsh will throw an error (`zsh: no matches found`) and stop, whereas Bash would just pass the literal string `h-*` to the command.
*   **NullGlob**: To make Zsh behave like Bash, you often need `setopt NULL_GLOB`.

---

## 2. The Solution: The "Pro Linux" Setup for Mac

To run Syskit (and most modern DevOps tools) reliably on a Mac, you should bridge the gap by installing the GNU suite via **Homebrew**.

### Step 1: Install Modern Bash
Don't use the ancient system Bash.
```bash
brew install bash
```
*   **Path**: This installs Bash 5.x at `/usr/local/bin/bash` (Intel) or `/opt/homebrew/bin/bash` (Apple Silicon).
*   **Best Practice**: Update your terminal to use this newer Bash as the default.

### Step 2: Install GNU Core Utilities (GNUutils)
Install the tools that make a Mac feel like Linux:
```bash
brew install coreutils grep gnu-sed gawk findutils
```
These tools are installed with a `g` prefix (e.g., `gsed`, `gawk`, `ggrep`) to avoid breaking macOS system internals.

### Step 3: Align the PATH
To use these tools without the `g` prefix (so Syskit scripts just work), add them to your PATH in `~/.bashrc` (or `~/.zshrc`):

```bash
# GNU Tools for macOS Compatibility
if [[ "$OSTYPE" == "darwin"* ]]; then
    # Add GNU coreutils to PATH (without 'g' prefix)
    # Check both potential Homebrew locations
    if [[ -d "/opt/homebrew/opt/coreutils/libexec/gnubin" ]]; then
        # Apple Silicon (M1/M2/M3)
        export PATH="/opt/homebrew/opt/coreutils/libexec/gnubin:$PATH"
        export PATH="/opt/homebrew/opt/gnu-sed/libexec/gnubin:$PATH"
        export PATH="/opt/homebrew/opt/grep/libexec/gnubin:$PATH"
        export PATH="/opt/homebrew/opt/findutils/libexec/gnubin:$PATH"
    elif [[ -d "/usr/local/opt/coreutils/libexec/gnubin" ]]; then
        # Intel Macs
        export PATH="/usr/local/opt/coreutils/libexec/gnubin:$PATH"
        export PATH="/usr/local/opt/gnu-sed/libexec/gnubin:$PATH"
        export PATH="/usr/local/opt/grep/libexec/gnubin:$PATH"
        export PATH="/usr/local/opt/findutils/libexec/gnubin:$PATH"
    fi
fi
```

---

## 3. Best Practices for Script Writing

If you want your scripts to be truly cross-platform without forcing the user to install Homebrew, follow these rules:

1.  **Avoid Process Substitution for Heredocs**: 
    *   **Bad**: `cmd <(cat <<EOF ...)` (Fails on Mac Bash 3.2 if quotes are present).
    *   **Good**: `cat <<EOF | cmd` (Pipe is universal).
2.  **Use `[[` instead of `[`**: The double-bracket test is more robust across shell versions.
3.  **Standardize `sed`**: If you must use `sed -i`, detect the OS:
    ```bash
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' 's/old/new/g' file
    else
        sed -i 's/old/new/g' file
    fi
    ```
4.  **Zsh Glob Compatibility**: If running in Zsh, add `unsetopt NOMATCH` at the top of the script so that empty globs don't crash the execution.
5.  **Use `tr` for Case Transformation**: Since `${var,,}` is Bash 4 only, use `echo "$var" | tr '[:upper:]' '[:lower:]'`.
6.  **Always use `printf`**: Replace `echo -e` or `echo -n` with `printf` for bulletproof results.
    ```bash
    # Instead of echo -e "\033[32mSuccess\033[0m"
    printf "\033[32m%%s\033[0m\n" "Success"
    ```

---

## 4. Summary Table

| Feature | Linux (GNU) | macOS (BSD) | Fix / Workaround |
| :--- | :--- | :--- | :--- |
| **Bash Version** | 5.0+ | 3.2 | `brew install bash` |
| **sed -i** | `sed -i '...'` | `sed -i '' '...'` | Use GNU Sed via Brew |
| **Globbing** | Forgiving | Strict (Zsh) | `unsetopt NOMATCH` (Zsh) |
| **xargs** | `--no-run-if-empty`| Not supported | Remove flag or use GNU xargs |
| **echo** | `-e` usually works | `-e` usually fails | Use `printf` instead |
