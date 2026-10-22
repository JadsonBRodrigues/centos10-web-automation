#!/bin/bash
# script12-update-backup.sh - Updates the system and configures daily backups
# Usage:
#   ./script12-update-backup.sh
#   ./script12-update-backup.sh --backup-only

set -euo pipefail

[[ $EUID -eq 0 ]] || {
    echo "Run as root (sudo)."
    exit 1
}

BASE="$(cd "$(dirname "$0")/.." && pwd)"

SEC_LOG="/var/log/seguranca.log"

BACKUP_DIR="/backups"
WEB_ROOT="/var/www/html"
WEB_BACKUP_DIR="$BACKUP_DIR/website"
DB_BACKUP_DIR="$BACKUP_DIR/mariadb"

CREDENTIAL_FILE="/root/.project-db-password"

SYSTEMD_SERVICE="/etc/systemd/system/project-backup.service"
SYSTEMD_TIMER="/etc/systemd/system/project-backup.timer"

mkdir -p "$BASE/logs"
touch "$SEC_LOG"
chmod 600 "$SEC_LOG"

log() {
    echo "$(date '+%F %T') [BACKUP] $*" | tee -a "$SEC_LOG"
}

log "Starting update and backup configuration..."

# Check required commands
for CMD in dnf tar mariadb mysqldump systemctl gzip; do
    if ! command -v "$CMD" >/dev/null 2>&1; then
        log "[FAIL] Required command not found: $CMD"
        exit 1
    fi
done

# Create backup directories
mkdir -p "$BACKUP_DIR" "$WEB_BACKUP_DIR" "$DB_BACKUP_DIR"

chmod 700 "$BACKUP_DIR"
chmod 700 "$WEB_BACKUP_DIR"
chmod 700 "$DB_BACKUP_DIR"

log "[OK] Backup directories created."

# Update system packages
if [[ "${1:-}" != "--backup-only" ]]; then
    log "Updating system packages..."
    dnf update -y
    log "[OK] System update completed."
else
    log "[*] Backup-only mode selected. System update skipped."
fi

# Configure MariaDB backup credential
if [[ ! -f "$CREDENTIAL_FILE" ]]; then
    log "MariaDB backup credential not found."

    read -rsp "Enter MariaDB root password: " DB_ROOT_PASS
    echo

    printf '%s\n' "$DB_ROOT_PASS" > "$CREDENTIAL_FILE"

    unset DB_ROOT_PASS

    chmod 600 "$CREDENTIAL_FILE"

    log "[OK] MariaDB backup credential created."
else
    chmod 600 "$CREDENTIAL_FILE"
    log "[OK] MariaDB backup credential already exists."
fi

# Load MariaDB password
DB_ROOT_PASS="$(cat "$CREDENTIAL_FILE")"

# Test MariaDB authentication
if ! MYSQL_PWD="$DB_ROOT_PASS" mariadb -u root -e "SELECT 1;" >/dev/null 2>&1; then
    log "[FAIL] MariaDB authentication failed."
    unset DB_ROOT_PASS
    exit 1
fi

log "[OK] MariaDB root authentication successful."

DATE="$(date '+%Y-%m-%d_%H-%M-%S')"

WEB_ARCHIVE="$WEB_BACKUP_DIR/website-$DATE.tar.gz"
DB_ARCHIVE="$DB_BACKUP_DIR/mariadb-$DATE.sql.gz"

# Backup website
log "Creating website backup..."

if tar -czf "$WEB_ARCHIVE" \
    -C "$(dirname "$WEB_ROOT")" \
    "$(basename "$WEB_ROOT")"; then

    log "[OK] Website backup created: $WEB_ARCHIVE"
else
    log "[FAIL] Website backup failed."
    rm -f "$WEB_ARCHIVE"
    unset DB_ROOT_PASS
    exit 1
fi

# Backup MariaDB
log "Creating MariaDB backup..."

if MYSQL_PWD="$DB_ROOT_PASS" mysqldump \
    -u root \
    --all-databases \
    --single-transaction \
    --routines \
    --events \
    --triggers \
    | gzip > "$DB_ARCHIVE"; then

    log "[OK] MariaDB backup created: $DB_ARCHIVE"
else
    log "[FAIL] MariaDB backup failed."
    rm -f "$DB_ARCHIVE"
    unset DB_ROOT_PASS
    exit 1
fi

unset DB_ROOT_PASS

# Protect backup files
chmod 600 "$WEB_ARCHIVE"
chmod 600 "$DB_ARCHIVE"

# Verify website backup
log "Verifying website backup..."

if tar -tzf "$WEB_ARCHIVE" >/dev/null 2>&1; then
    log "[OK] Website archive integrity verified."
else
    log "[FAIL] Website archive integrity check failed."
    exit 1
fi

# Verify MariaDB backup
log "Verifying MariaDB backup..."

if gzip -t "$DB_ARCHIVE" >/dev/null 2>&1; then
    log "[OK] MariaDB archive integrity verified."
else
    log "[FAIL] MariaDB archive integrity check failed."
    exit 1
fi

# Get backup sizes
WEB_SIZE="$(du -h "$WEB_ARCHIVE" | awk '{print $1}')"
DB_SIZE="$(du -h "$DB_ARCHIVE" | awk '{print $1}')"

log "Website backup size: $WEB_SIZE"
log "MariaDB backup size: $DB_SIZE"

# Create systemd backup service
log "Creating systemd backup service..."

cat > "$SYSTEMD_SERVICE" <<EOF
[Unit]
Description=Project Website and MariaDB Backup
After=network-online.target mariadb.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/bin/bash $BASE/scripts/script12-update-backup.sh --backup-only
EOF

# Create systemd daily backup timer
log "Creating systemd daily backup timer..."

cat > "$SYSTEMD_TIMER" <<'EOF'
[Unit]
Description=Daily Project Website and MariaDB Backup Timer

[Timer]
OnCalendar=*-*-* 02:00:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now project-backup.timer

# Validate timer
if systemctl is-active --quiet project-backup.timer; then
    log "[OK] Daily backup timer is active."
else
    log "[FAIL] Daily backup timer is not active."
    exit 1
fi

echo
echo "=========================================="
echo " System Update and Backup"
echo "=========================================="
echo "Backup directory:       $BACKUP_DIR"
echo "Website backup:         $WEB_ARCHIVE"
echo "Website size:           $WEB_SIZE"
echo "MariaDB backup:         $DB_ARCHIVE"
echo "MariaDB size:           $DB_SIZE"
echo "Credential file:        $CREDENTIAL_FILE"
echo "Daily backup time:      02:00"
echo "Backup timer:           $(systemctl is-active project-backup.timer)"
echo "Security log:           $SEC_LOG"
echo "=========================================="

log "[OK] Update and backup configuration completed successfully."
