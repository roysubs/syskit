#!/bin/bash
# Author: Roy Wiseman 2025-04

# angband-saves: Backup and restore Angband save files

SAVE_DIR="/var/games/angband/save"
BACKUP_DIR="$HOME/.angband/Angband"

# Function to display usage instructions
usage() {
    echo "Usage:"
    echo "  $0           : List saves in $SAVE_DIR"
    echo "  $0 -b        : Backup saves to $BACKUP_DIR with timestamp"
    echo "  $0 -r FILE   : Restore backup FILE from $BACKUP_DIR to $SAVE_DIR"
    exit 1
}

# Function to list save files
list_saves() {
    echo "Save files in $SAVE_DIR:"
    ls -l "$SAVE_DIR"
}

# Function to backup save files
backup_saves() {
    mkdir -p "$BACKUP_DIR"
    for file in "$SAVE_DIR"/*; do
        [ -f "$file" ] || continue
        base_name=$(basename "$file")
        mod_time=$(stat -c "%Y" "$file")
        timestamp=$(date -d "@$mod_time" +"%Y%m%d-%H%M%S")
        cp -p "$file" "$BACKUP_DIR/${base_name}-${timestamp}.sav"
        echo "Backed up $base_name to ${base_name}-${timestamp}.sav"
    done
}

# Function to restore a save file
restore_save() {
    if [ -z "$1" ]; then
        echo "Available backups in $BACKUP_DIR:"
        ls "$BACKUP_DIR"/*.sav 2>/dev/null
        echo "Please specify a backup file to restore."
        exit 1
    fi

    backup_file="$1"
    if [[ "$backup_file" != /* ]]; then
        backup_file="$BACKUP_DIR/$backup_file"
    fi

    if [ ! -f "$backup_file" ]; then
        echo "Backup file not found: $backup_file"
        exit 1
    fi

    # Extract original filename by removing the timestamp
    filename=$(basename "$backup_file")
    original_name="${filename%-????????-??????.sav}"

    cp -i "$backup_file" "$SAVE_DIR/$original_name"
    echo "Restored $original_name to $SAVE_DIR"
}

# Main script logic
case "$1" in
    -b)
        backup_saves
        ;;
    -r)
        restore_save "$2"
        ;;
    "")
        list_saves
        usage
        ;;
    *)
        echo "Invalid option: $1"
        usage
        ;;
esac

