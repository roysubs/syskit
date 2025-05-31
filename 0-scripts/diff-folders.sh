#!/bin/bash
# Author: Roy Wiseman 2025-03

show_help() {
    cat <<EOF
Usage: $0 [OPTIONS] <folder1> <folder2>

Compares files in two folders recursively and generates a list with sizes.
Also creates an update script to sync changed files from <folder2> to <folder1>.

OPTIONS:
  --only-diffs              Show only files that differ
  --exclude-dirs="d1:d2"    Exclude subdirectories (relative to root, colon-separated)
  -h, --help                Show this help message
EOF
    exit 0
}

# Parse args
only_diffs=0
exclude_dirs=()

while [[ "$1" == -* ]]; do
    case "$1" in
        --only-diffs)
            only_diffs=1
            shift
            ;;
        --exclude-dirs=*)
            IFS=':' read -ra exclude_dirs <<< "${1#*=}"
            shift
            ;;
        -h|--help)
            show_help
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            ;;
    esac
done

if [[ $# -ne 2 ]]; then
    echo "Error: Exactly two folder arguments are required."
    show_help
fi

folder1=$(realpath "$1")
folder2=$(realpath "$2")

if [[ ! -d "$folder1" || ! -d "$folder2" ]]; then
    echo "Both arguments must be valid directories."
    exit 1
fi

# Create update script
safe_folder1=$(basename "$folder1" | sed 's/[^a-zA-Z0-9_-]/_/g')
update_script="update-for-${safe_folder1}.sh"
echo "#!/bin/bash" > "$update_script"
echo "# This script updates changed files from $folder2 to $folder1" >> "$update_script"
echo >> "$update_script"

# Collect all relative file paths from both folders
collect_files() {
    local base="$1"
    if [[ ! -d "$base" ]]; then return; fi
    cd "$base" || exit 1
    if [[ ${#exclude_dirs[@]} -eq 0 ]]; then
        find . -type f | sed 's|^\./||'
    else
        find_expr=()
        for dir in "${exclude_dirs[@]}"; do
            find_expr+=( \( -path "./$dir" -o -path "./$dir/*" \) -prune -o )
        done
        find_expr+=( -type f -print )
        find . "${find_expr[@]}" | sed 's|^\./||'
    fi
}

mapfile -t rel_files < <(
    {
        collect_files "$folder1"
        collect_files "$folder2"
    } | sort -u
)

# Output header
printf "%-60s %-16s %-16s\n" "File" "Size(folder1)" "Size(folder2)"
echo "--------------------------------------------------------------------------------------------------------"

for rel_path in "${rel_files[@]}"; do
    file1="$folder1/$rel_path"
    file2="$folder2/$rel_path"

    size1="---"
    size2="---"
    color_start=""
    color_end=""

    [[ -f "$file1" ]] && size1=$(stat -c%s "$file1")
    [[ -f "$file2" ]] && size2=$(stat -c%s "$file2")

    if [[ "$size1" != "$size2" ]]; then
        [[ "$size2" != "---" ]] && color_start=$'\e[32m' && color_end=$'\e[0m'
        if [[ "$size1" != "---" && "$size2" != "---" ]]; then
            echo "mkdir -p \"$(dirname "$folder1/$rel_path")\"" >> "$update_script"
            echo "cp -f \"$file2\" \"$file1\"" >> "$update_script"
        fi
        show=1
    else
        show=0
    fi

    if [[ $only_diffs -eq 0 || $show -eq 1 ]]; then
        printf "%-60s %-16s ${color_start}%-16s${color_end}\n" "$rel_path" "$size1" "$size2"
    fi
done

