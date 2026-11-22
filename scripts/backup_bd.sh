#!/usr/bin/env bash
# ==============================================================================
# Secure MariaDB Backup & Optimization Script
# Authentication: uses ~/.my.cnf (chmod 600) — never passes passwords on CLI.
# Usage:
#   DB_NAME="<DB_NAME>" ./backup_bd.sh
# ==============================================================================

set -euo pipefail
umask 077

# Configuration (override via environment variables if desired)
DB_NAME="${DB_NAME:-<DB_NAME>}"
MY_CNF="${MY_CNF:-${HOME}/.my.cnf}"
BACKUP_DIR="${BACKUP_DIR:-${HOME}/backups/db}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"
DATE="$(date +%Y-%m-%d_%H-%M-%S)"
BACKUP_FILE="${BACKUP_DIR}/${DB_NAME}_${DATE}.sql.gz"

# Validate configuration
if [[ "$DB_NAME" == "<DB_NAME>" || -z "$DB_NAME" ]]; then
    echo "ERROR: Set DB_NAME to your actual database name." >&2
    exit 1
fi

if [[ ! -f "$MY_CNF" ]]; then
    echo "ERROR: Credentials file not found: $MY_CNF" >&2
    echo "Create it from templates/db/my.cnf.example and run: chmod 600 \"$MY_CNF\"" >&2
    exit 1
fi

# Enforce strict 600 permissions on credentials file
CNF_PERMS="$(stat -c '%a' "$MY_CNF")"
if [[ "$CNF_PERMS" != "600" ]]; then
    echo "ERROR: $MY_CNF has unsafe permissions ($CNF_PERMS). Expected 600." >&2
    echo "Fix with: chmod 600 \"$MY_CNF\"" >&2
    exit 1
fi

mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

# 1. Check and optimize tables
mariadb-check --defaults-extra-file="$MY_CNF" --optimize "$DB_NAME"

# 2. Consistent, compressed dump (no lock on InnoDB tables)
mariadb-dump \
    --defaults-extra-file="$MY_CNF" \
    --single-transaction \
    --quick \
    --routines \
    --triggers \
    "$DB_NAME" | gzip -9 > "$BACKUP_FILE"

# 3. Rotate backups older than RETENTION_DAYS
find "$BACKUP_DIR" -maxdepth 1 -type f -name "${DB_NAME}_*.sql.gz" -mtime "+${RETENTION_DAYS}" -delete

echo "OK: Database backup created at $BACKUP_FILE"
