#!/usr/bin/env bash
# ==============================================================================
# Secure Website Files Backup Script
# Creates a compressed archive with 600 permissions (umask 077) and rotates old archives.
# Usage:
#   SITE_DIR="/var/www/<DOMAIN>/public" ./backup_files.sh
# ==============================================================================

set -euo pipefail
umask 077

# Configuration (override via environment variables if desired)
SITE_DIR="${SITE_DIR:-/var/www/<DOMAIN>/public}"
BACKUP_DIR="${BACKUP_DIR:-${HOME}/backups/files}"
RETENTION_DAYS="${RETENTION_DAYS:-14}"
DATE="$(date +%Y-%m-%d_%H-%M-%S)"
ARCHIVE_FILE="${BACKUP_DIR}/site_files_${DATE}.tar.gz"

# Validate source directory
if [[ "$SITE_DIR" == *"<DOMAIN>"* || ! -d "$SITE_DIR" ]]; then
    echo "ERROR: SITE_DIR does not exist or still contains placeholder: $SITE_DIR" >&2
    exit 1
fi

mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

# Archive using -C to avoid embedding full leading paths
PARENT_DIR="$(dirname "$SITE_DIR")"
TARGET_NAME="$(basename "$SITE_DIR")"

tar -czf "$ARCHIVE_FILE" -C "$PARENT_DIR" "$TARGET_NAME"

# Rotate archives older than RETENTION_DAYS
find "$BACKUP_DIR" -maxdepth 1 -type f -name "site_files_*.tar.gz" -mtime "+${RETENTION_DAYS}" -delete

echo "OK: Files backup created at $ARCHIVE_FILE"
