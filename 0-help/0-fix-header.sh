#!/bin/bash
# Author: Roy Wiseman 2025-05

read -r -d '' header_content <<'EOM'
#!/bin/bash
command -v mdcat &>/dev/null || "${0%/*}/mdcat-get.sh"; hash -r
command -v mdcat &>/dev/null || { echo "Error: mdcat required but not available." >&2; exit 1; }
WIDTH=$(if [ $(tput cols) -ge 105 ]; then echo 100; else echo $(( $(tput cols) - 5 )); fi)
mdcat --columns="$WIDTH" <(cat <<'EOF'
EOM

# Color codes 
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
RESET='\033[0m'

MODIFIED_FILES=()
DELIMITER='mdcat --columns='

for file in ./h-*; do
    [[ -f "$file" ]] || continue

    lineno=$(grep -nF "$DELIMITER" "$file" | cut -d: -f1 | head -n1)
    if [[ -n "$lineno" ]]; then
        echo -e "${RED}${file}${RESET}"
        echo -e "${YELLOW}--- Removing lines 1 to $lineno (inclusive) ---${RESET}"
        head -n "$lineno" "$file"

        MODIFIED_FILES+=("$file")
    else
        echo -e "${GREEN}${file} — no '$DELIMITER' found${RESET}"
    fi
done

if [[ ${#MODIFIED_FILES[@]} -eq 0 ]]; then
    echo "No files to modify."
    exit 0
fi

echo
read -rp "Apply these changes? [y/N]: " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

# Apply changes
for file in "${MODIFIED_FILES[@]}"; do
    lineno=$(grep -nF "$DELIMITER" "$file" | cut -d: -f1 | head -n1)

    # Tail from line after the delimiter line
    tail -n +"$((lineno + 1))" "$file" > "${file}.tmp"

    # Overwrite file with new header + old content after delimiter
    printf "%s\n" "$header_content" > "$file"
    cat "${file}.tmp" >> "$file"
    rm -f "${file}.tmp"
done

echo "Modifications complete."

