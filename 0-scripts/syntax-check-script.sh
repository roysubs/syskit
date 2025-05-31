#!/bin/bash
# Author: Roy Wiseman 2025-04

# Script name: check-script-syntax.sh
#
# Checks a specified file or all regular files in a given directory
# (optionally recursively) for:
# - Bash or Python syntax errors (based on extension/shebang).
# - Issues with shebangs for .sh files.
# - Potentially undesired characters (non-standard-printable-ASCII, excluding a safe list if specified).
#
# Usage: ./check-script-syntax.sh [options] <file_or_directory_path>

# --- Configuration ---
# Define your safe non-ASCII/symbol characters here.
# Ensure this script file is saved with UTF-8 encoding for these characters to be correct.
declare -a USER_DEFINED_SAFE_CHARS=(
  # Box Drawing
  '╔' '═' '╠' '║' '┌' '┐' '└' '┘' '├' '┤' '┬' '┴' '┼' '─' '│' '━' '┃'
  # Checkmarks, Crosses, Status
  '✔' '✓' '✅' '❌' '✘' '🟢' '⚪'
  # Arrows & Pointers
  '←' '↑' '→' '↓' '►' '◄' '▲' '▼' '➤'
  # Information, Alerts, Questions
  'ℹ' '💡' '🔍' '🚨' '⚠️' '❓' '📌'
  # Geometric Shapes & Bullets
  '●' '○' '◆' '◇' '▪' '▫' '🔹' '🔸' '•'
  # Blocks & Shades
  '░' '▒' '▓' '█'
  # Thematic Emojis (Tools, Objects, Concepts)
  '📊' '🐳' '📛' '🔧' '🔁' '📦' '🧩' '🌐' '🎉' '🧪' '🖥' '🧠' '🧵' '💾'
  '🌡' '🚀' '🏁' '📋' '⚙' '🖼' '📂' '🗂' '📡' '🧾' '🛠' '🧹' '♻' '🧽' '☁'
  '🗃' '📏' '📅' '🕒' '📍' '🗺️' '🔗'
  # Punctuation & Other Symbols
  '·' '…' '—'
  # Currency & Copyright (from script example comments)
  '£' '€' '©' '®'
  # Specific Git/Powerline Symbols (from your list)
  '' '✚' '⚑'
)

# --- Global Variables ---
files_with_issues_total=0
processed_files_count=0

# --- Usage Function ---
usage() {
  echo "Usage: ${0##*/} [options] <file_or_directory_path>"
  echo ""
  echo "Checks script files for syntax errors and potentially undesired characters."
  echo ""
  echo "Arguments:"
  echo "  <file_or_directory_path>  Path to a single file or a directory to check."
  echo "                            Can use '.' for current directory or '~' (unquoted) for home."
  echo ""
  echo "Options:"
  echo "  -r, --recurse             If <path> is a directory, recursively check files."
  echo "                            Ignored if <path> is a file."
  echo "  -i, --ignore-safe-chars   Do not report characters that are in the script's"
  echo "                            predefined USER_DEFINED_SAFE_CHARS list."
  echo "  -h, --help                Show this help message."
  exit 1
}

# --- File Processing Function ---
process_file() {
  local file_to_check="$1"
  processed_files_count=$((processed_files_count + 1))
  local has_issue_for_this_file=0
  local current_file_issue_output="" # Accumulates output for the current file

  # --- Determine file type and shebang ---
  local ext="${file_to_check##*.}"
  local first_line=""
  # Read first line, handle potentially empty files or unreadable files gracefully
  if [[ -r "$file_to_check" && -s "$file_to_check" ]]; then # readable and not empty
      first_line=$(head -n 1 "$file_to_check")
  elif [[ ! -r "$file_to_check" ]]; then
      current_file_issue_output+="File: $file_to_check\n"
      current_file_issue_output+="  [FILE ACCESS ERROR]: Cannot read file.\n"
      has_issue_for_this_file=1
      # Early output for this file if it has issues
      if [[ $has_issue_for_this_file -ne 0 ]]; then
        echo -e "$current_file_issue_output"
        echo "--------------------------------------------------"
        files_with_issues_total=$((files_with_issues_total + 1))
      fi
      return # Skip further processing for this file
  fi


  local is_python_candidate=0
  local is_bash_candidate=0
  local has_bash_shebang=0
  local has_python_shebang=0
  local has_other_shebang=0
  local other_shebang_path=""

  if [[ "$first_line" == "#!"* ]]; then
    if [[ "$first_line" == *"/bash"* || "$first_line" == *"/env bash"* ]]; then
      has_bash_shebang=1
    elif [[ "$first_line" == *"/python"* || "$first_line" == *"/env python"* ]]; then # Catches python, python2, python3
      has_python_shebang=1
    else
      has_other_shebang=1
      other_shebang_path="$first_line"
    fi
  fi

  if [[ "$ext" == "py" || $has_python_shebang -eq 1 ]]; then
    is_python_candidate=1
  fi
  # A file is a bash candidate if it has .sh OR a bash shebang
  if [[ "$ext" == "sh" || $has_bash_shebang -eq 1 ]]; then
    is_bash_candidate=1
  fi

  # --- Syntax Checks & Shebang Warnings ---
  local syntax_check_attempted=0 # Track if a syntax check was run

  # Python Check
  if [[ $is_python_candidate -eq 1 ]]; then
    syntax_check_attempted=1
    if [[ "$ext" == "sh" && $has_python_shebang -eq 1 ]]; then # .sh file with Python shebang
      if [[ $has_issue_for_this_file -eq 0 ]]; then current_file_issue_output+="File: $file_to_check\n"; fi
      current_file_issue_output+="  [SHEBANG CONFLICT]: File has .sh extension but Python shebang:\n"
      current_file_issue_output+="    $first_line\n"
      has_issue_for_this_file=1
    else
      # Using ast.parse for pure syntax check, avoids __pycache__
      python_errors=$(python3 -c "import ast; import sys; code = open(sys.argv[1], 'r', encoding='utf-8').read(); ast.parse(code)" "$file_to_check" 2>&1)
      python_exit_code=$?
      if [[ $python_exit_code -ne 0 ]]; then
        if [[ $has_issue_for_this_file -eq 0 ]]; then current_file_issue_output+="File: $file_to_check\n"; fi
        current_file_issue_output+="  [PYTHON SYNTAX ERRORS (python3 ast.parse)]:\n"
        while IFS= read -r line; do current_file_issue_output+="    $line\n"; done <<< "$python_errors"
        has_issue_for_this_file=1
      fi
    fi
  fi

  # Bash Check (only if not already identified and checked as Python, unless it's a .sh file with a non-python, non-bash shebang)
  if [[ $is_python_candidate -eq 0 || "$ext" == "sh" ]]; then # Allow bash check for .sh files even if python candidate was true due to python shebang (handled above)
    if [[ $is_bash_candidate -eq 1 || ("$ext" == "sh" && $has_python_shebang -eq 0) ]]; then # If it's a .sh file without a python shebang, or any file with a bash shebang
      syntax_check_attempted=1
      shebang_issue_reported=0
      if [[ "$ext" == "sh" ]]; then
        if [[ $has_bash_shebang -eq 0 ]]; then
          if [[ $has_other_shebang -eq 1 ]]; then
            if [[ $has_issue_for_this_file -eq 0 ]]; then current_file_issue_output+="File: $file_to_check\n"; fi
            current_file_issue_output+="  [SHEBANG CONFLICT]: File has .sh extension but a non-Bash shebang:\n"
            current_file_issue_output+="    $other_shebang_path\n"
            has_issue_for_this_file=1
            shebang_issue_reported=1 # Don't also run bash -n on this
          elif [[ $has_python_shebang -eq 0 ]]; then # No shebang at all, and not python
            if [[ $has_issue_for_this_file -eq 0 ]]; then current_file_issue_output+="File: $file_to_check\n"; fi
            current_file_issue_output+="  [SHEBANG WARNING]: File with .sh extension has no shebang. Assuming Bash for syntax check.\n"
            # has_issue_for_this_file=1 # Optionally make this a reported "issue"
          fi
        fi
      fi

      # Run bash -n if:
      # 1. It has a bash shebang OR
      # 2. It's a .sh file AND (it has no shebang OR it has a bash shebang)
      # AND no conflicting shebang was reported for this .sh file that prevents bash -n
      if [[ $shebang_issue_reported -eq 0 && ($has_bash_shebang -eq 1 || ("$ext" == "sh" && $has_other_shebang -eq 0 && $has_python_shebang -eq 0)) ]]; then
        bash_errors=$(bash -n "$file_to_check" 2>&1)
        if [[ $? -ne 0 ]]; then
          if [[ $has_issue_for_this_file -eq 0 ]]; then current_file_issue_output+="File: $file_to_check\n"; fi
          # If a shebang warning was already printed, don't add another header unless errors are different
          if [[ ! "$current_file_issue_output" == *"SHEBANG WARNING"* || ! "$current_file_issue_output" == *"[BASH SYNTAX ERRORS"* ]]; then
             current_file_issue_output+="  [BASH SYNTAX ERRORS (bash -n)]:\n"
          fi
          while IFS= read -r line; do current_file_issue_output+="    $line\n"; done <<< "$bash_errors"
          has_issue_for_this_file=1
        fi
      fi
    fi
  fi

  # --- Potentially Undesired Character Check ---
  # Checks for anything not plain printable ASCII (\x20-\x7E) or Tab/LF/CR.
  # This will catch all multi-byte UTF-8 characters, other control characters etc.
  # Using awk to get line number and line content to avoid issues with filenames containing colons
  # Redirecting stderr of grep to /dev/null to suppress binary file warnings if --text is not 100% effective
  # grep -P might not be available on all systems, but often is. Using standard grep with extended regex if P fails.
  GREP_CMD="grep"
  if grep -P "" /dev/null &>/dev/null; then
    UNDESIRED_CHAR_PATTERN="[^\t\r\n\x20-\x7E]"
    GREP_CMD="grep --text -P -n --color=never"
  else # Fallback for systems without grep -P, less precise for \xNN but catches non-printable
    UNDESIRED_CHAR_PATTERN="[^\t\r\n[:print:]]"
    GREP_CMD="grep --text -E -n --color=never" # [:print:] includes space
    # If using this fallback, the SAFE_ASCII_CHARS might not all be outside [:print:]
    # This part needs more thought for universal compatibility vs precision.
    # For now, assuming systems will have grep -P for the user's specific characters.
    # The user's previous output indicated they had grep -P.
    UNDESIRED_CHAR_PATTERN="[^\t\r\n\x20-\x7E]" # Keep this more specific pattern.
    GREP_CMD="grep --text -P -n --color=never"
  fi

  undesired_char_lines_with_numbers=$($GREP_CMD "$UNDESIRED_CHAR_PATTERN" "$file_to_check" 2>/dev/null)

  if [[ -n "$undesired_char_lines_with_numbers" ]]; then
    lines_to_report_buffer=""
    if [[ $ignore_safe_chars_flag -eq 1 ]]; then
      while IFS= read -r line_with_number; do
        line_content="${line_with_number#*:}"
        temp_line_content="$line_content"
        for safe_char in "${USER_DEFINED_SAFE_CHARS[@]}"; do
          temp_line_content="${temp_line_content//"$safe_char"/}"
        done
        # After removing safe characters, check if any *undesired* characters still remain
        # (i.e., anything not plain printable ASCII or Tab/LF/CR)
        if echo "$temp_line_content" | $GREP_CMD "$UNDESIRED_CHAR_PATTERN" 1>/dev/null 2>&1; then
          lines_to_report_buffer+="$line_with_number\n"
        fi
      done <<< "$undesired_char_lines_with_numbers"
    else
      lines_to_report_buffer="$undesired_char_lines_with_numbers\n"
    fi

    if [[ -n "$lines_to_report_buffer" ]]; then
      if [[ $has_issue_for_this_file -eq 0 ]]; then
        current_file_issue_output+="File: $file_to_check\n"
      fi
      if [[ $ignore_safe_chars_flag -eq 1 ]]; then
        current_file_issue_output+="  [POTENTIALLY UNDESIRED CHARACTERS FOUND (excluding safe list)]:\n"
      else
        current_file_issue_output+="  [POTENTIALLY UNDESIRED CHARACTERS FOUND (not plain ASCII or common whitespace)]:\n"
      fi
      while IFS= read -r report_line; do
          if [[ -n "$report_line" ]]; then
              current_file_issue_output+="    $report_line\n"
          fi
      done <<< "$(echo -e "$lines_to_report_buffer")" # Process the buffer
      has_issue_for_this_file=1
    fi
  fi

  # --- Output for this file if issues were found ---
  if [[ $has_issue_for_this_file -ne 0 ]]; then
    echo -e "$current_file_issue_output"
    echo "--------------------------------------------------"
    files_with_issues_total=$((files_with_issues_total + 1))
  fi
}

# --- Argument Parsing ---
recursive_check=0
ignore_safe_chars_flag=0 # Renamed for clarity
paths_to_check=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -r|--recurse)
      recursive_check=1
      shift
      ;;
    -i|--ignore-safe-chars)
      ignore_safe_chars_flag=1
      shift
      ;;
    -h|--help)
      usage
      ;;
    -*) # Unknown option
      echo "Error: Unknown option: $1" >&2
      usage
      ;;
    *) # Accumulate path arguments
      paths_to_check+=("$1")
      shift
      ;;
  esac
done

if [[ ${#paths_to_check[@]} -ne 1 ]]; then
  echo "Error: Please specify exactly one file or directory path." >&2
  usage
fi
TARGET_PATH="${paths_to_check[0]}"

if [[ -z "$TARGET_PATH" ]]; then
  echo "Error: No file or directory path specified." >&2
  usage
fi

# --- Main Logic ---
if [[ -f "$TARGET_PATH" ]]; then
  echo "Scanning single file: $TARGET_PATH"
  echo "--------------------------------------------------"
  process_file "$TARGET_PATH"
elif [[ -d "$TARGET_PATH" ]]; then
  if [[ $recursive_check -eq 1 ]]; then
    echo "Scanning directory recursively: $TARGET_PATH"
  else
    echo "Scanning directory (non-recursively): $TARGET_PATH"
  fi
  echo "--------------------------------------------------"
  
  find_depth_option=() # Use an array for find options
  if [[ $recursive_check -eq 0 ]]; then
    find_depth_option=(-maxdepth 1)
  fi

  find "$TARGET_PATH" "${find_depth_option[@]}" -type f -print0 | while IFS= read -r -d $'\0' file_found; do
    process_file "$file_found"
  done
else
  echo "Error: '$TARGET_PATH' is not a valid file or directory." >&2
  usage
fi

# --- Summary ---
echo ""
if [[ $processed_files_count -eq 0 ]]; then
    echo "Scan complete. No files found to check in '$TARGET_PATH'."
elif [[ $files_with_issues_total -eq 0 ]]; then
  echo "Scan complete. Processed $processed_files_count file(s). No issues found meeting the criteria."
else
  echo "Scan complete. Processed $processed_files_count file(s). Found issues in $files_with_issues_total file(s) meeting the criteria."
fi

exit 0
