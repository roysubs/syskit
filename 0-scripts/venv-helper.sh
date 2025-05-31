#!/usr/bin/env bash
# Author: Roy Wiseman 2025-02

# venv-helper.sh — A sourced utility to guide and manage Python virtual environments.

# Must be sourced to properly activate/deactivate venvs.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  SCRIPT_REALPATH="$(realpath "${BASH_SOURCE[0]}")"
  echo "This script must be sourced to activate/deactivate virtual environments."
  echo
  echo "Try this instead:"
  echo "  alias venvh='source $SCRIPT_REALPATH'"
  echo "  echo \"alias venvh='source $SCRIPT_REALPATH'\" >> ~/.bashrc"
  echo "  source ~/.bashrc"
  echo
  echo "Then use:"
  echo "  venvh <venv-path>"
  exit 1
fi

# Help message
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  SCRIPT_REALPATH="$(realpath "${BASH_SOURCE[0]}")"
  echo "venv-helper — A shell utility for managing and activating Python virtual environments"
  echo
  echo "PURPOSE:"
  echo "  - Simplifies working with Python virtual environments from the terminal."
  echo "  - Helps create new venvs if missing, and activates them via 'source'."
  echo "  - Intended for interactive use through an alias (see below)."
  echo
  echo "USAGE:"
  echo "  source venv-helper.sh <venv-path>"
  echo
  echo "NOTES:"
  echo "  - This script must be *sourced*, not executed, or it cannot activate anything."
  echo "  - It checks if the given <venv-path> exists, and creates it if not."
  echo "  - After sourcing, it activates the venv at <venv-path>."
  echo
  echo "ALIAS SETUP:"
  echo "  To make this command easier to use, add this to your ~/.bashrc:"
  echo
  echo "    alias venvh='source $SCRIPT_REALPATH'"
  echo
  echo "  Then reload your shell:"
  echo "    source ~/.bashrc"
  echo
  echo "EXAMPLES:"
  echo "  venvh ~/venvs/myproj       # Creates + activates venv at given path"
  echo "  venvh ./venv               # Uses relative path in your project folder"
  echo
  echo "Manual fallback (if you don't want to use venvh):"
  echo "  mkdir -p ./venv"
  echo "  python3 -m venv ./venv"
  echo "  source ./venv/bin/activate"
  return 0
fi

# No argument provided
if [[ -z "$1" ]]; then
  echo "Error: No path provided. Usage: source venv-helper.sh <venv-path>"
  return 1
fi

VENV_PATH="$1"

echo
echo "What is a virtual environment (venv)?"
echo "  - Isolates Python dependencies per project or test-bed."
echo "  - Prevents version conflicts between projects."
echo "  - Keeps system Python clean."
echo
echo "Common Practice:"
echo "  - venvs are often created in the project folder (and then .gitignore'd)."
echo "  - But you can absolutely put them anywhere — e.g., ~/venvs/mytest — and reuse."
echo
echo "Pro-tip: If your project is in Git, add 'venv/' to your .gitignore to avoid committing it."
echo

# Deactivate if already active
if [[ -n "$VIRTUAL_ENV" ]]; then
  echo "You currently have a venv active at: $VIRTUAL_ENV"
  read -rp "Do you want to deactivate it first? [y/N] " ans
  if [[ "$ans" =~ ^[Yy]$ ]]; then
    deactivate
    echo "Virtual environment deactivated."
  else
    echo "Continuing with current venv."
  fi
  echo
fi

# If the directory exists and contains a venv, inspect
if [[ -d "$VENV_PATH" && -f "$VENV_PATH/bin/activate" ]]; then
  echo "Inspecting virtual environment at: $VENV_PATH"
  PY_VER="$("$VENV_PATH/bin/python3" --version 2>/dev/null || "$VENV_PATH/bin/python" --version)"
  echo "Python version: $PY_VER"

  echo "Installed packages:"
  "$VENV_PATH/bin/pip" list

  echo
  read -rp "Do you want to activate this venv now? [y/N] " ans
  if [[ "$ans" =~ ^[Yy]$ ]]; then
    echo "To activate:"
    echo "  source \"$VENV_PATH/bin/activate\""
    echo "Now running activation for you..."
    source "$VENV_PATH/bin/activate"
    echo
    echo "Virtual environment activated."
    echo "  To deactivate later, type: deactivate"
  else
    echo "Leaving environment unactivated."
  fi
  return 0
fi

# Doesn't exist — create it
echo "This venv does not exist yet. Creating new virtual environment at: $VENV_PATH"
mkdir -p "$VENV_PATH"
python3 -m venv "$VENV_PATH"

echo "Virtual environment created."
echo "To activate it:"
echo "  source \"$VENV_PATH/bin/activate\""
read -rp "Activate now? [y/N] " ans
if [[ "$ans" =~ ^[Yy]$ ]]; then
  source "$VENV_PATH/bin/activate"
  echo
  echo "Virtual environment activated."
  echo "  To deactivate later, type: deactivate"
else
  echo "You can activate it later with:"
  echo "  source \"$VENV_PATH/bin/activate\""
fi

