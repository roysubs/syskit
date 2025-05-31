#!/bin/bash
# Author: Roy Wiseman 2025-04

# Colorscheme cleanup script
# Moves advanced/template-based colorschemes to a separate directory

COLORS_DIR="$HOME/.vim/colors"
ADVANCED_DIR="$HOME/.vim/colors-advanced"

# Create the advanced directory if it doesn't exist
mkdir -p "$ADVANCED_DIR"

echo "Scanning for advanced/template colorschemes in $COLORS_DIR..."
echo "Will move them to $ADVANCED_DIR"
echo

# Counter for moved files
moved_count=0

# Function to move file and report
move_file() {
    local file="$1"
    local reason="$2"
    local basename=$(basename "$file")
    
    echo "Moving $basename ($reason)"
    mv "$file" "$ADVANCED_DIR/"
    ((moved_count++))
}

# Find files by name patterns (case-insensitive)
echo "=== Checking filename patterns ==="
while IFS= read -r -d '' file; do
    basename=$(basename "$file" .vim)
    case "$basename" in
        *base16*|*base24*|*base32*)
            move_file "$file" "base16/24/32 naming"
            ;;
        *pywal*|*wal-*)
            move_file "$file" "pywal naming"
            ;;
        *template*|*generated*|*auto*)
            move_file "$file" "template/generated naming"
            ;;
        *themer*|*themery*)
            move_file "$file" "themer naming"
            ;;
    esac
done < <(find "$COLORS_DIR" -name "*.vim" -print0)

echo

# Find files by content patterns
echo "=== Checking file contents ==="

# Look for base16/template references in file contents
grep -l -i -E "(base16|base24|base32|pywal|template|generated|themer)" "$COLORS_DIR"/*.vim 2>/dev/null | while read -r file; do
    # Skip if already moved
    if [[ ! -f "$file" ]]; then
        continue
    fi
    
    basename=$(basename "$file")
    
    # Check what pattern matched
    if grep -q -i "base1[6248]" "$file" 2>/dev/null; then
        move_file "$file" "contains base16/24 references"
    elif grep -q -i "pywal\|wal.*generated" "$file" 2>/dev/null; then
        move_file "$file" "contains pywal references"  
    elif grep -q -i "template\|generated.*automatically" "$file" 2>/dev/null; then
        move_file "$file" "contains template/generated references"
    elif grep -q -i "themer" "$file" 2>/dev/null; then
        move_file "$file" "contains themer references"
    fi
done

echo

# Look for files with template-like syntax
echo "=== Checking for template syntax ==="
grep -l -E "\{\{.*\}\}|%\{.*\}|\$\{.*\}" "$COLORS_DIR"/*.vim 2>/dev/null | while read -r file; do
    if [[ -f "$file" ]]; then
        move_file "$file" "contains template syntax"
    fi
done

echo

# Look for files that reference missing dependencies
echo "=== Checking for dependency references ==="
grep -l -i -E "(python|pip|install|dependency|require.*module)" "$COLORS_DIR"/*.vim 2>/dev/null | while read -r file; do
    if [[ -f "$file" ]]; then
        # Only move if it seems to be about dependencies, not just mentioning python
        if grep -q -i -E "(install.*python|pip install|missing.*dependency|require.*module)" "$file" 2>/dev/null; then
            move_file "$file" "references missing dependencies"
        fi
    fi
done

echo

# Look for files with suspicious error patterns when loaded
echo "=== Checking for files with common error patterns ==="
while IFS= read -r -d '' file; do
    if [[ ! -f "$file" ]]; then
        continue
    fi
    
    # Check for files that have incomplete color definitions
    if ! grep -q -E "hi(ghlight)?\s+(Normal|Comment|String)" "$file" 2>/dev/null; then
        # If it doesn't define basic highlight groups, it might be a template
        basename=$(basename "$file")
        if [[ -f "$file" ]] && [[ $(wc -l < "$file") -lt 20 ]]; then
            move_file "$file" "appears to be incomplete/template (too short)"
        fi
    fi
done < <(find "$COLORS_DIR" -name "*.vim" -print0)

echo
echo "=== Summary ==="
echo "Moved $moved_count files to $ADVANCED_DIR"
echo "Remaining files in $COLORS_DIR: $(find "$COLORS_DIR" -name "*.vim" | wc -l)"
echo
echo "You can review the moved files with:"
echo "  ls -la '$ADVANCED_DIR'"
echo
echo "To restore a file:"
echo "  mv '$ADVANCED_DIR/filename.vim' '$COLORS_DIR/'"
echo
echo "To permanently delete the advanced ones:"
echo "  rm -rf '$ADVANCED_DIR'"
