# `f` - Enhanced Find and Grep Wrapper

`f` is a powerful, simplified wrapper for standard Linux `find` and `grep` commands. It provides short, intuitive commands for common operations like finding the largest files, searching by age, or recursively grepping for text without remembering complex syntax.

---

## 🚀 Simple Search (Quick Start)

The default behavior of `f` is a case-insensitive filename search.

*   **Contains Search**: `f mything`  
    Automatically wraps the pattern in wildcards: `find . -iname "*mything*"`
*   **Explicit Wildcards**: `f "my*"` or `f "*.log"`  
    If you provide `*`, `?`, or `[]`, it uses your pattern exactly but keeps it case-insensitive.
*   **Specify Path**: `f config /etc`  
    Searches for "config" inside `/etc`.

---

## 🛠️ General Options

These options can be combined with any find or grep action.

| Option | Long Form | Description |
| :--- | :--- | :--- |
| `-c` | `--cmd` | **Show the executed command** and time taken after running. Great for learning `find` syntax. |
| `-s` | `--sudo` | Run the generated command with `sudo`. |
| `-e DIR` | `--exclude` | Exclude a directory (e.g., `-e .git -e node_modules`). Can be used multiple times. |
| `-L N` | `--level` | Limit search depth (e.g., `-L 1` for current directory only). |
| `f` | `fast` | Add `-xdev` to skip other filesystems (faster on root `/`). |

---

## 🔍 Find Operations

Use these tokens to trigger specific search behaviors.

### 📊 Size & Age
*   **`b`, `big`, `biggest [N]`**: Find the `N` largest files (default 10).
*   **`n`, `new`, `newest [N]`**: Find the `N` most recently modified files.
*   **`o`, `old`, `oldest [N]`**: Find the oldest files.
*   **`m`, `modified N`**: Find files modified in the last `N` days.
*   **`a`, `accessed N`**: Find files accessed in the last `N` days.
*   **`s`, `size SIZE`**: Find by specific size (e.g., `+100M`, `-1G`).

### 📂 Types & State
*   **`e`, `empty`**: Find empty files.
*   **`ed`, `empty-dirs`**: Find empty directories.
*   **`t`, `type [f\|d\|l]`**: Find by type (file, directory, or symlink).
*   **`l`, `symlinks`**: Find broken symlinks.
*   **`d`, `duplicates`**: Find duplicate files by content (uses md5sum).

### ⚙️ Advanced Find
*   **`p`, `permissions MODE`**: Find by octal permissions (e.g., `777`).
*   **`x`, `exec 'CMD'`**: Run a command on every file found. Use `{}` as the filename placeholder.
*   **`r`, `regex PATTERN`**: Find files matching a Posix-extended regex.
*   **`g`, `grep PATTERN`**: Find files containing the specified text (lists filenames).
*   **`hf`, `h-find`**: Open a built-in "cheat sheet" page for `find` syntax.

---

## 📝 Grep Operations (Content Search)

These options bypass `find` and use `grep` recursively on the target path.

*   **`gl`, `grep-lines PATTERN`**: Standard recursive grep (shows matching lines).
*   **`gli`, `grep-lines-i PATTERN`**: Case-insensitive line search.
*   **`glw`, `grep-lines-w PATTERN`**: Match whole words only.
*   **`gf`, `grep-files PATTERN`**: List filenames only (no lines).
*   **`gfi`, `grep-files-i PATTERN`**: Case-insensitive filename listing.
*   **`hg`, `h-grep`**: Open a built-in "cheat sheet" page for `grep` syntax.

---

## 💡 Example Gallery

### Housekeeping
```bash
# Find 5 biggest files in home directory
f b 5 ~

# Find and delete empty folders
f ed -x 'rmdir {}'

# Find files modified in the last 2 days
f m 2
```

### Development
```bash
# Search for "TODO" in all files, showing line numbers
f gl "TODO"

# Find all .js files, excluding node_modules
f "*.js" -e node_modules

# Find files containing "apiKey" case-insensitively, list names only
f gfi "apiKey" .
```

### System Administration
```bash
# Find files larger than 500MB with sudo and show the exact command
f -s -c s +500M /var/log

# Find 777 permissions in /tmp
f p 777 /tmp
```
