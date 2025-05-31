#!/bin/bash
# Author: Roy Wiseman 2025-04

set -euo pipefail
shopt -s nullglob

# CONFIGURATION
USERNAME="${USER}"
BACKUP_REPO="$HOME/.backup/${USERNAME}_backup"
BACKUP_SOURCE="$HOME"
EXCLUDES=(
  '**/.cache'
  '**/Cache'
  '**/node_modules'
  '**/.npm'
  '**/.cargo/registry'
  '**/.rustup'
  '**/.local/share/Trash'
  '**/.gvfs'
  '**/.thumbnails'
  '**/tmp'
  '**/*.tmp'
)
CRON_BACKUP_SCHEDULE="0 2 * * *"
CRON_PRUNE_SCHEDULE="0 3 * * 0"   # Sundays at 3AM
SCRIPT_PATH="$(realpath "$0")"

# Ensure borg is installed
if ! command -v borg &> /dev/null; then
  echo "ERROR: 'borg' command not found. Please install BorgBackup first."
  exit 1
fi

# Ensure backup repo exists
if [ ! -d "$BACKUP_REPO" ]; then
  echo "Initializing backup repository at $BACKUP_REPO (no encryption)..."
  borg init --encryption=none "$BACKUP_REPO"
else
  echo "Using existing backup repository at $BACKUP_REPO"
fi

# Generate archive name
TIMESTAMP=$(date +%Y-%m-%dT%H:%M)
ARCHIVE_NAME="archive-$TIMESTAMP"

# Build exclusion args
EXCLUDE_ARGS=()
for pattern in "${EXCLUDES[@]}"; do
  EXCLUDE_ARGS+=(--exclude "$pattern")
done

# Perform backup
echo "Starting backup: $ARCHIVE_NAME"
borg create --verbose --stats --progress \
  "$BACKUP_REPO::$ARCHIVE_NAME" \
  "$BACKUP_SOURCE" \
  "${EXCLUDE_ARGS[@]}"

# Prune old backups
echo "Pruning old backups..."
borg prune --verbose --list "$BACKUP_REPO" \
  --keep-daily=7 \
  --keep-weekly=4 \
  --keep-monthly=3

# Summary
echo ""
echo "✅ Backup complete: $ARCHIVE_NAME"
echo "🗃️  Backup repository: $BACKUP_REPO"
echo ""
echo "📦 Archive list:"
borg list --short "$BACKUP_REPO" | tail

echo ""
echo "📏 Size of repository:"
borg info "$BACKUP_REPO" | grep -E 'All archives|Total size'

# CRON INSTALLATION (idempotent)
( crontab -l 2>/dev/null | grep -vF "$SCRIPT_PATH" ; echo "$CRON_BACKUP_SCHEDULE $SCRIPT_PATH # borg daily backup" ) \
  | sort | uniq | crontab -

( crontab -l 2>/dev/null | grep -vF "$SCRIPT_PATH --prune" ; echo "$CRON_PRUNE_SCHEDULE $SCRIPT_PATH --prune # borg weekly prune" ) \
  | sort | uniq | crontab -

# Handle optional --prune arg
if [[ "${1:-}" == "--prune" ]]; then
  echo "Running prune only..."
  exit 0
fi

# Helpful usage tips
cat <<EOF

🔧 USEFUL COMMANDS:

• List backup archives:
    borg list $BACKUP_REPO

• Mount an archive to browse contents:
    borg mount $BACKUP_REPO::archive-YYYY-MM-DDTHH:MM /mnt
    # then browse /mnt, and run:
    borg umount /mnt

• Diff two backups:
    borg diff $BACKUP_REPO::archive-YYYY-MM-DDTHH:MM $BACKUP_REPO::archive-YYYY-MM-DDTHH:MM

• Extract files:
    borg extract $BACKUP_REPO::archive-YYYY-MM-DDTHH:MM path/to/file

EOF

