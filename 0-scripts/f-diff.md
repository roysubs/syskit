# f-diff - A Better Console Diff Tool

A compact, colorful, and powerful diff tool with merge capabilities.

## Features

### 1. Compact Block Summary
Shows differences grouped into blocks with helpful statistics.

```bash
f-diff file1.txt file2.txt
```

**Output includes:**
- File timestamps (shows which file is newer)
- Colored change types:
  - **CHANGE** (yellow): Lines exist in both but differ
  - **ADD** (green): Lines only in file2
  - **DELETE** (red): Lines only in file1
  - **no-diff** (gray): Identical lines
- Line ranges and character counts

**Example:**
```
File 1: demo1.txt (2025-11-12 22:13:29)
File 2: demo2.txt (2025-11-12 22:13:36)
→ File 2 is newer

Line    1 to    3 : no-diff (3 lines, 65 chars)
Line    4 to    5 : DELETE (2 lines, 44 chars in file1 only)
Line    6 to    7 : no-diff (2 lines, 35 chars)
Line    8 to   10 : CHANGE (3 lines, ~43 chars, ~0 chars differ)
```

### 2. Detailed Block Inspection
View the actual content of any block.

```bash
f-diff file1.txt file2.txt 8
```

Shows side-by-side comparison with line numbers:
```
Block: Lines 8 to 10 (CHANGE)
======================================================================

*** demo1.txt ***
   8 | Modified line in file 1
   9 | Same content again
  10 | 

*** demo2.txt ***
   8 | Modified line in file 2
   9 | Same content again
  10 |
```

### 3. Merge/Resolve Conflicts
Copy lines from one file to another with automatic backup.

**Merge entire block by line number:**
```bash
f-diff file1.txt file2.txt 8 >    # Copy block at line 8 from file1 to file2
f-diff file1.txt file2.txt 8 <    # Copy block at line 8 from file2 to file1
```

**Merge specific line range:**
```bash
f-diff file1.txt file2.txt 8-15 >    # Copy lines 8-15 from file1 to file2
f-diff file1.txt file2.txt 8-15 <    # Copy lines 8-15 from file2 to file1
```

**Safety features:**
- Creates `.bak` backup before modifying
- Shows preview of what will be copied and replaced
- Clear confirmation messages

## Change Types Explained

1. **CHANGE**: Lines exist at the same position in both files but have different content
2. **DELETE**: Lines exist in file1 but not in file2 (file2 is missing these lines)
3. **ADD**: Lines exist in file2 but not in file1 (new lines in file2)

## Installation

```bash
chmod +x f-diff
sudo mv f-diff /usr/local/bin/
```

Or just run it directly: `./f-diff file1 file2`

## Requirements

- Python 3.6+
- GNU diff (standard on all Unix-like systems)

## Tips

- Colors automatically disable when piping output
- The tool works best with text files
- Line numbers are always from file1's perspective in the summary
- Backups are created with `.bak` extension during merges

## Why f-diff?

Traditional diff tools show you *every* line difference, which can be overwhelming for large files. f-diff gives you a bird's-eye view first, then lets you drill down to the details you care about. The merge capability makes it easy to selectively apply changes without manual copy-paste.

Perfect for:
- Comparing configuration files
- Reviewing code changes
- Merging manual edits
- Understanding file differences at a glance

