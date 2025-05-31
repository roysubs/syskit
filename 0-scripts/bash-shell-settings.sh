#!/usr/bin/env bash
# Author: Roy Wiseman 2025-04

# Colors using $'...'. This ensures backslash escapes are interpreted.
# Using \e as a shorthand for \033 (ESC).
YELLOW=$'\e[1;33m'
GREEN=$'\e[0;32m'
RED=$'\e[0;31m' # Added RED color
NC=$'\e[0m'     # No Color

# Function to print a heading
heading() {
  printf "\n%s== %s ==%s\n" "${YELLOW}" "$1" "${NC}"
}

# --- Shell Detection ---
printf "Detected shell: %s\n" "$SHELL"
shell_name=$(basename "$SHELL")

detect_actual_shell() {
    if [ -n "$BASH_VERSION" ]; then
        printf "Shell detected: bash %s\n" "$BASH_VERSION"
    elif [ -n "$ZSH_VERSION" ]; then
        printf "Shell detected: zsh %s\n" "$ZSH_VERSION"
    elif [ -n "$KSH_VERSION" ]; then
        printf "Shell detected: ksh %s (Version: %s)\n" "$KSH_VERSION" # KSH_VERSION might be complex
    elif [ -n "$FISH_VERSION" ]; then
        printf "Shell detected: fish %s (not POSIX-compliant)\n" "$FISH_VERSION"
    else
        # Fallback for other shells like dash (often /bin/sh)
        if ps -p $$ -o comm= | grep -q "dash"; then
            printf "Shell detected: dash (likely /bin/sh, POSIX-compliant)\n"
        else
            printf "%sUnknown or basic POSIX shell%s\n" "${YELLOW}" "${NC}"
        fi
    fi
}
detect_actual_shell

# --- Feature Checks ---
printf "\n%sChecking feature support...%s\n" "${YELLOW}" "${NC}"

# Check associative arrays
if bash -c 'declare -A test_assoc_array &>/dev/null' ; then
    printf "✔ %sAssociative arrays supported%s\n" "${GREEN}" "${NC}"
else
    printf "✘ %sAssociative arrays NOT supported%s\n" "${RED}" "${NC}"
fi

# Check [[ operator
if bash -c '[[ 1 -eq 1 ]]' &>/dev/null; then
    printf "✔ %s[[ operator supported%s\n" "${GREEN}" "${NC}"
else
    printf "✘ %s[[ operator NOT supported%s\n" "${RED}" "${NC}"
fi

# Check process substitution
if bash -c 'cat < <(echo test_psub) &>/dev/null' ; then
    printf "✔ %sProcess substitution supported%s\n" "${GREEN}" "${NC}"
else
    printf "✘ %sProcess substitution NOT supported%s\n" "${RED}" "${NC}"
fi

# Check arithmetic expansion
if bash -c ': "$((1 + 2))"' &>/dev/null; then # The ':' is a no-op, tests if arithmetic is parsed
    printf "✔ %sArithmetic expansion supported%s\n" "${GREEN}" "${NC}"
else
    printf "✘ %sArithmetic expansion NOT supported%s\n" "${RED}" "${NC}"
fi

printf "\nIf any feature is missing, scripts using modern Bash may not work reliably.\n"

# --- Shell Options Display ---

# Helper to print current setting of shopt option
show_shopt() {
  local opt=$1
  local desc=$2
  local state_str
  if shopt -q "$opt"; then # shopt -q exits 0 if ON, 1 if OFF
    state_str="${GREEN}on${NC}"
  else
    state_str="${RED}off${NC}"
  fi
  printf "%-20s : %s\n" "$opt" "$state_str"
  [ -n "$desc" ] && printf "    %s\n" "$desc"
}

# Helper to print current setting of set -o option
show_setopt() {
  local opt=$1
  local desc=$2
  local state_str
  # Check current state of the option
  if ( set -o | grep -qE "^${opt}[[:space:]]+on$" ); then
    state_str="${GREEN}on${NC}"
  else
    state_str="${RED}off${NC}"
  fi
  printf "%-20s : %s\n" "$opt" "$state_str"
  [ -n "$desc" ] && printf "    %s\n" "$desc"
}

heading "Bash Shell Options via shopt"
show_shopt autocd        "Change directory by typing directory name if it's not a command."
show_shopt cdspell       "Correct minor typos in directory names during 'cd'."
show_shopt checkwinsize  "Update LINES and COLUMNS after each command."
show_shopt cmdhist       "Save all lines of a multi-line command in the same history entry."
show_shopt dotglob       "Include filenames beginning with '.' in pathname expansion results."
show_shopt extglob       "Enable extended pattern matching features (e.g., !(pattern))."
show_shopt globstar      "Enable '**' to match all files, directories, and subdirectories recursively."
show_shopt histappend    "Append to history file instead of overwriting when shell exits."
show_shopt hostcomplete  "Enable hostname completion after '@' during command line editing."
show_shopt huponexit     "Send SIGHUP to all jobs when an interactive login shell exits."
show_shopt interactive_comments "Allow words beginning with '#' to cause that word and all remaining characters on that line to be ignored in an interactive shell."
show_shopt lithist       "Save multi-line commands to history with embedded newlines (if cmdhist is off)."
show_shopt nocaseglob    "Perform case-insensitive pathname expansion."
show_shopt nullglob      "Allow patterns that match no files to expand to a null string, rather than themselves."
show_shopt progcomp      "Enable programmable completion facilities."
show_shopt promptvars    "Expand prompt strings like PS1 (variables, backslash-escaped chars)."
show_shopt sourcepath    "Allow 'source' builtin to search PATH for script if not found in current dir."

heading "POSIX Shell Options via set -o"
show_setopt allexport    "(-a) Automatically export all variables and functions created or modified."
show_setopt braceexpand  "(-B) Enable brace expansion (e.g. {a,b}c -> ac bc). On by default."
show_setopt errexit      "(-e) Exit immediately if a command exits with a non-zero status."
show_setopt functrace    "(-T) Allow DEBUG and RETURN traps to be inherited by functions, command substitutions, and subshells."
show_setopt histexpand   "(-H) Enable '!' style history substitution. On by default for interactive shells."
show_setopt history      "Enable command history. On by default for interactive shells."
show_setopt ignoreeof    "Prevent an interactive shell from exiting on EOF (Ctrl-D) (requires 'exit')."
show_setopt keyword      "(-k) Place keyword arguments in the environment for a command."
show_setopt monitor      "(-m) Enable job control. On by default for interactive shells."
show_setopt noclobber    "(-C) Prevent redirection from overwriting existing files ('>|' overrides)."
show_setopt noexec       "(-n) Read commands but do not execute them (syntax checking)."
show_setopt noglob       "(-f) Disable pathname expansion (globbing)."
show_setopt nounset      "(-u) Treat unset variables and parameters as an error when performing parameter expansion."
show_setopt pipefail     "The return value of a pipeline is the status of the last command to exit with non-zero, or zero if all exit successfully."
show_setopt posix        "Change Bash behavior to match POSIX standard more closely where defaults differ."
show_setopt verbose      "(-v) Print shell input lines as they are read."
show_setopt xtrace       "(-x) Print commands and their arguments as they are executed (debugging)."

# --- Managing Options ---
heading "Managing Shell Options"
printf "You can manage these options temporarily for your current session or permanently in your shell's startup files (e.g., %s~/.bashrc%s).\n" "${GREEN}" "${NC}"

printf "\n%sViewing Options:%s\n" "${YELLOW}" "${NC}"
printf "  %sshopt%s           : Show all shopt options and their states.\n" "${GREEN}" "${NC}"
printf "  %sshopt <optname>%s : Show state of a specific shopt option.\n" "${GREEN}" "${NC}"
printf "  %sshopt -p%s        : List shopt options in a reusable format (e.g., for scripts).\n" "${GREEN}" "${NC}"
printf "  %sset -o%s          : Show all 'set -o' options and their states.\n" "${GREEN}" "${NC}"
printf "  %sset +o%s          : List 'set -o' options in a reusable format.\n" "${GREEN}" "${NC}"

printf "\n%sEnabling Options:%s\n" "${YELLOW}" "${NC}"
printf "  %sshopt -s <optname>%s : Enable (set) a shopt option (e.g., %sshopt -s nullglob%s).\n" "${GREEN}" "${NC}" "${GREEN}" "${NC}"
printf "  %sset -o <optname>%s   : Enable a 'set -o' option (e.g., %sset -o nounset%s).\n" "${GREEN}" "${NC}" "${GREEN}" "${NC}"
printf "  %sset -<char>%s        : Enable a 'set' option using its single-character equivalent (e.g., %sset -u%s for nounset).\n" "${GREEN}" "${NC}" "${GREEN}" "${NC}"

printf "\n%sDisabling Options:%s\n" "${YELLOW}" "${NC}"
printf "  %sshopt -u <optname>%s : Disable (unset) a shopt option (e.g., %sshopt -u nullglob%s).\n" "${GREEN}" "${NC}" "${GREEN}" "${NC}"
printf "  %sset +o <optname>%s   : Disable a 'set -o' option (e.g., %sset +o nounset%s).\n" "${GREEN}" "${NC}" "${GREEN}" "${NC}"
printf "  %sset +<char>%s        : Disable a 'set' option using its single-character equivalent (e.g., %sset +u%s for nounset).\n" "${GREEN}" "${NC}" "${GREEN}" "${NC}"

printf "\n%sMaking changes persistent:%s\n" "${YELLOW}" "${NC}"
printf "  To make settings permanent, add the desired commands (e.g., %sshopt -s globstar%s or %sset -o pipefail%s) to your %s~/.bashrc%s file.\n" "${GREEN}" "${NC}" "${GREEN}" "${NC}" "${GREEN}" "${NC}"
printf "  Then, source the file (%ssource ~/.bashrc%s) or open a new terminal.\n" "${GREEN}" "${NC}"

heading "Try enabling some useful options temporarily"
printf "%sIn your interactive shell, try:%s\n" "${GREEN}" "${NC}"
printf "  %sshopt -s extglob%s        # Enable extended globbing, e.g., ls !(file.txt)\n" "${GREEN}" "${NC}"
printf "  %sshopt -s globstar%s       # Enable recursive globbing, e.g., ls **/*.txt\n" "${GREEN}" "${NC}"
printf "  %sshopt -s nullglob%s       # Make non-matching globs expand to nothing (safer in scripts)\n" "${GREEN}" "${NC}"
printf "  %sset -o nounset%s         # Treat unset variables as an error (helps catch typos)\n" "${GREEN}" "${NC}"
printf "  %sset -o pipefail%s       # Make pipeline fail if any command in it fails\n" "${GREEN}" "${NC}"
printf "  %sset -o errexit%s        # Exit script on first error (use with caution, understand implications)\n" "${GREEN}" "${NC}"
printf "  (To disable, use %sshopt -u ...%s or %sset +o ...%s)\n" "${GREEN}" "${NC}" "${GREEN}" "${NC}"

heading "See All Current shopt Options (raw output)"
printf "%sUse 'shopt -p' to see current settings in a reusable format:%s\n" "${YELLOW}" "${NC}"
shopt -p

heading "See All Current set -o Options (raw output)"
printf "%sUse 'set -o' to see current settings:%s\n" "${YELLOW}" "${NC}"
set -o

printf "\n%sNote:%s If colors do not render correctly, your terminal might not fully support ANSI escape codes or might need configuration.\n" "${YELLOW}" "${NC}"
