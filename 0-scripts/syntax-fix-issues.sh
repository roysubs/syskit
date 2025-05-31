#!/bin/bash
# Author: Roy Wiseman 2025-01

# Script name: fix-syntax-issues.sh
#
# Cleans problematic "invisible" Unicode characters and some ASCII control
# characters from text files. Useful for scripts and configuration files.
# Offers a dry-run mode and a commit mode with backups.
#
# Uses perl for robust UTF-8 handling and character replacement.

# --- Configuration ---
# Base directory for backups when -c or --commit is used.
# Timestamped subdirectories will be created within this.
BACKUP_ROOT_DIR="$HOME/.backup/fixed-script-syntax"

# The core Perl script logic for cleaning.
# This is kept in a variable for easier management.
# It targets common "invisible" or problematic characters.
PERL_SCRIPT_LOGIC='
  # Replace common problematic Unicode spaces with ASCII space (\x20)
  s/\x{00A0}/ /g;  # NO-BREAK SPACE
  s/\x{2000}/ /g;  # EN QUAD
  s/\x{2001}/ /g;  # EM QUAD
  s/\x{2002}/ /g;  # EN SPACE
  s/\x{2003}/ /g;  # EM SPACE
  s/\x{2004}/ /g;  # THREE-PER-EM SPACE
  s/\x{2005}/ /g;  # FOUR-PER-EM SPACE
  s/\x{2006}/ /g;  # SIX-PER-EM SPACE
  s/\x{2007}/ /g;  # FIGURE SPACE
  s/\x{2008}/ /g;  # PUNCTUATION SPACE
  s/\x{2009}/ /g;  # THIN SPACE
  s/\x{200A}/ /g;  # HAIR SPACE
  s/\x{202F}/ /g;  # NARROW NO-BREAK SPACE
  s/\x{205F}/ /g;  # MEDIUM MATHEMATICAL SPACE
  s/\x{3000}/ /g;  # IDEOGRAPHIC SPACE

  # Remove zero-width characters and BOM (Byte Order Mark)
  s/\x{200B}//g;  # ZERO WIDTH SPACE
  s/\x{200C}//g;  # ZERO WIDTH NON-JOINER
  s/\x{200D}//g;  # ZERO WIDTH JOINER
  s/\x{FEFF}//g;  # ZERO WIDTH NO-BREAK SPACE (BOM)

  # Remove other problematic format/control characters
  s/\x{00AD}//g;  # SOFT HYPHEN
  s/[\x{202A}-\x{202E}]//g; # LRE, RLE, PDF, LRO, RLO (BiDi embedding/override controls)

  # Remove ASCII C0 control characters (0x00-0x1F) except Horizontal Tab (0x09),
  # Line Feed (0x0A), and Carriage Return (0x0D). Also remove DEL (0x7F).
  s/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]//g;
'

# --- Global Variables ---
processed_files_count=0
fixed_files_count=0
current_backup_dir=""

# --- Usage Function ---
usage() {
  echo "Usage: $0 [options] <file_or_directory_path>"
  echo ""
  echo "Cleans scripts and text files of common problematic 'invisible' Unicode characters"
  echo "and certain ASCII control characters, replacing them with standard spaces or removing them."
  echo ""
  echo "Why Perl? Perl provides robust UTF-8 handling and support for Unicode properties,"
  echo "making it more reliable for these kinds of text transformations than standard sed on all systems."
  echo ""
  echo "Modes:"
  echo "  Default (if only path is given): DRY-RUN mode. Shows potential changes using 'diff'."
  echo "                                 If path is a directory, processes files in that directory only (non-recursive)."
  echo ""
  echo "Options:"
  echo "  <file_or_directory_path>  Path to a single file or a directory to process."
  echo "  -c, --commit              Actually modify the files in-place. Creates backups in"
  echo "                            '$BACKUP_ROOT_DIR/<timestamp>/<original_path_structure>'."
  echo "  -a, --all                 If <path> is a directory, process files recursively."
  echo "                            In commit mode, prompts for confirmation before processing all."
  echo "  -v, --verbose             Enable verbose output, showing files being processed."
  echo "  -h, --help                Show this help message."
  echo ""
  echo "Examples:"
  echo "  $0 ./myscript.sh                      # Dry-run on a single file"
  echo "  $0 -c ./myscript.sh                   # Fix a single file (with backup)"
  echo "  $0 ./scripts_dir                     # Dry-run on files directly in scripts_dir"
  echo "  $0 -a ./scripts_dir                   # Dry-run on files in scripts_dir recursively"
  echo "  $0 -c -a ./scripts_dir                # Fix all files in scripts_dir recursively (with backups)"
  exit 1
}

# --- Helper Functions ---
verbose_echo() {
  if [[ $verbose_mode -eq 1 ]]; then
    echo "$@"
  fi
}

# Function to process a single file (either dry-run or commit)
process_single_file() {
  local filepath="$1"
  local target_to_check="$filepath" # For messages

  # Skip likely binary files
  # grep -I (capital I) processes binary files as if they do not match.
  # Returns 0 for text (no NULL bytes), 1 for binary (has NULL bytes).
  if ! grep -Iq "" "$filepath"; then
    verbose_echo "Skipping likely binary file: $filepath"
    return
  fi
  
  processed_files_count=$((processed_files_count + 1))
  verbose_echo "Processing: $filepath"

  if [[ $do_commit -eq 0 ]]; then # Dry-run mode
    # Use process substitution to avoid temp files for diff
    diff_output=$(diff -u "$filepath" <(perl -CSAD -pe "$PERL_SCRIPT_LOGIC" "$filepath" 2>/dev/null) 2>/dev/null)
    if [[ -n "$diff_output" ]]; then
      echo "--------------------------------------------------"
      echo "Potential changes for: $filepath"
      echo "$diff_output"
      files_with_issues_total=$((files_with_issues_total + 1)) # Using this to count files that would change
    else
      verbose_echo "No changes needed for: $filepath"
    fi
  else # Commit mode
    # Check if changes are actually needed before backing up and modifying
    original_content=$(<"$filepath")
    processed_content=$(echo "$original_content" | perl -CSAD -pe "$PERL_SCRIPT_LOGIC" 2>/dev/null)

    if [[ "$original_content" != "$processed_content" ]]; then
      echo "--------------------------------------------------"
      echo "Fixing: $filepath"
      
      # Create backup
      # Preserve relative path from the initial target for backup structure
      local backup_path_suffix="${filepath#"$initial_target_path_abs"}" # Get path relative to initial target
      if [[ "$backup_path_suffix" == "$filepath" ]]; then # Not a subpath, probably single file or top-level in dir
          backup_path_suffix="/$(basename "$filepath")"
      fi
      local backup_file_dir="$current_backup_dir${backup_path_suffix%/*}" # Get directory part of the relative path
      
      mkdir -p "$backup_file_dir"
      cp -p "$filepath" "$backup_file_dir/$(basename "$filepath")" # Copy with original name into structured backup
      echo "  Backed up to: $backup_file_dir/$(basename "$filepath")"

      # Apply changes (writing processed_content is safer than perl -i after check)
      echo "$processed_content" > "$filepath"
      echo "  Fixed in place."
      fixed_files_count=$((fixed_files_count + 1))
    else
      verbose_echo "No changes needed for: $filepath"
    fi
  fi
}

# --- Argument Parsing ---
do_commit=0
do_recursive_all=0
verbose_mode=0
TARGET_PATH=""
paths_specified=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -c|--commit)
      do_commit=1
      shift
      ;;
    -a|--all) # For directories, this implies recursive.
      do_recursive_all=1
      shift
      ;;
    -v|--verbose)
      verbose_mode=1
      shift
      ;;
    -h|--help)
      usage
      ;;
    -*)
      echo "Error: Unknown option $1" >&2
      usage
      ;;
    *)
      if [[ $paths_specified -eq 0 ]]; then
        TARGET_PATH="$1"
        paths_specified=1
      else
        echo "Error: Please specify only one file or directory path." >&2
        usage
      fi
      shift
      ;;
  esac
done

if [[ -z "$TARGET_PATH" ]]; then
  usage # No path provided or only options
fi

# Convert TARGET_PATH to an absolute path for consistent backup paths
initial_target_path_abs=$(readlink -f "$TARGET_PATH")


# --- Main Logic ---

# Setup backup directory if in commit mode
if [[ $do_commit -eq 1 ]]; then
  timestamp=$(date +%Y%m%d-%H%M%S)
  current_backup_dir="$BACKUP_ROOT_DIR/$timestamp"
  if ! mkdir -p "$current_backup_dir"; then
    echo "Error: Could not create backup directory: $current_backup_dir" >&2
    exit 1
  fi
  if [[ $do_commit -eq 1 ]]; then
    verbose_echo "Backups will be stored in: $current_backup_dir"
  fi
fi


if [[ -f "$TARGET_PATH" ]]; then
  verbose_echo "Mode: Single File"
  process_single_file "$initial_target_path_abs" # Process absolute path
elif [[ -d "$TARGET_PATH" ]]; then
  if [[ $do_recursive_all -eq 1 ]]; then
    verbose_echo "Mode: Directory Recursive (-a)"
    if [[ $do_commit -eq 1 ]]; then
        echo "WARNING: You are about to modify files recursively in '$TARGET_PATH'."
        read -rp "Are you sure you want to proceed? (yes/N): " confirmation
        if [[ "${confirmation,,}" != "yes" ]]; then
            echo "Operation cancelled by user."
            exit 0
        fi
    fi
    find "$initial_target_path_abs" -type f -print0 | while IFS= read -r -d $'\0' file_found; do
      process_single_file "$file_found"
    done
  else # Directory, non-recursive
    verbose_echo "Mode: Directory Non-Recursive"
    find "$initial_target_path_abs" -maxdepth 1 -type f -print0 | while IFS= read -r -d $'\0' file_found; do
      process_single_file "$file_found"
    done
  fi
else
  echo "Error: '$TARGET_PATH' is not a valid file or directory." >&2
  usage
fi

# --- Summary ---
echo ""
echo "--- Scan Summary ---"
echo "Files processed: $processed_files_count"
if [[ $do_commit -eq 0 ]]; then
  if [[ $files_with_issues_total -gt 0 ]]; then
    echo "Potential changes identified in $files_with_issues_total file(s) (Dry-run mode)."
  else
    echo "No problematic characters requiring changes found (Dry-run mode)."
  fi
else
  echo "Files actually fixed: $fixed_files_count"
  if [[ $fixed_files_count -gt 0 ]]; then
    echo "Backups stored in: $current_backup_dir"
  fi
fi

exit 0
