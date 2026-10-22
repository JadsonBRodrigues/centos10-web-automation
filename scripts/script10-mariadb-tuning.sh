#!/bin/bash
# script10-mariadb-tuning.sh - Tunes MariaDB 10.11 based on system RAM
# Usage: ./script10-mariadb-tuning.sh

set -euo pipefail

[[ $EUID -eq 0 ]] || {
    echo "Run as root (sudo)."
    exit 1
}

BASE="$(cd "$(dirname "$0")/.." && pwd)"
SEC_LOG="/var/log/seguranca.log"
MYCNF="/etc/my.cnf"
BACKUP_DIR="$BASE/logs"
BACKUP_FILE="$BACKUP_DIR/my.cnf.backup-$(date +%F_%H%M%S)"

mkdir -p "$BACKUP_DIR"
touch "$SEC_LOG"
chmod 600 "$SEC_LOG"

log() {
    echo "$(date '+%F %T') [MARIADB] $*" | tee -a "$SEC_LOG"
}

log "Starting MariaDB performance tuning..."

# Check MariaDB service
if ! systemctl cat mariadb.service >/dev/null 2>&1; then
    log "[FAIL] MariaDB service was not found."
    exit 1
fi

if ! systemctl is-active --quiet mariadb; then
    log "MariaDB is not running. Starting MariaDB..."
    systemctl start mariadb
fi

log "[OK] MariaDB service is active."

# Detect MariaDB version
MARIADB_VERSION="$(mariadb --version | sed -n 's/.*Distrib \([0-9.]*\).*/\1/p')"

if [[ -z "$MARIADB_VERSION" ]]; then
    log "[FAIL] Could not detect MariaDB version."
    exit 1
fi

log "MariaDB version: $MARIADB_VERSION"

# Request MariaDB root password securely
read -rsp "Enter MariaDB root password: " DB_ROOT_PASS
echo

if ! mariadb -u root -p"$DB_ROOT_PASS" -e "SELECT 1;" >/dev/null 2>&1; then
    log "[FAIL] MariaDB root authentication failed."
    unset DB_ROOT_PASS
    exit 1
fi

log "[OK] MariaDB root authentication successful."

# Detect system RAM
RAM_MB="$(free -m | awk '/^Mem:/ {print $2}')"

if [[ -z "$RAM_MB" || "$RAM_MB" -le 0 ]]; then
    log "[FAIL] Could not detect system RAM."
    unset DB_ROOT_PASS
    exit 1
fi

# Calculate 60% of available RAM
BUFFER_POOL_MB=$((RAM_MB * 60 / 100))

log "Detected RAM: ${RAM_MB} MB"
log "InnoDB buffer pool target: ${BUFFER_POOL_MB} MB"

# Create configuration backup
if [[ -f "$MYCNF" ]]; then
    cp -a "$MYCNF" "$BACKUP_FILE"
    log "[OK] Backup created: $BACKUP_FILE"
else
    touch "$MYCNF"
    log "[WARN] /etc/my.cnf did not exist. Created a new configuration file."
fi

# Remove previous project tuning parameters
sed -i \
    -e '/^[[:space:]]*innodb_buffer_pool_size[[:space:]]*=/d' \
    -e '/^[[:space:]]*innodb_log_file_size[[:space:]]*=/d' \
    -e '/^[[:space:]]*max_connections[[:space:]]*=/d' \
    -e '/^[[:space:]]*query_cache_size[[:space:]]*=/d' \
    "$MYCNF"

# Ensure [mysqld] section exists
if ! grep -qE '^[[:space:]]*\[mysqld\][[:space:]]*$' "$MYCNF"; then
    printf '\n[mysqld]\n' >> "$MYCNF"
fi

# Add project tuning parameters
cat >> "$MYCNF" <<EOF

# Project MariaDB performance tuning
innodb_buffer_pool_size = ${BUFFER_POOL_MB}M
innodb_log_file_size = 256M
max_connections = 100
query_cache_size = 32M
EOF

log "[OK] Tuning parameters written to $MYCNF."

echo
echo "Configured MariaDB parameters:"
grep -E \
    '^[[:space:]]*(innodb_buffer_pool_size|innodb_log_file_size|max_connections|query_cache_size)[[:space:]]*=' \
    "$MYCNF"

# Restart MariaDB
log "Restarting MariaDB..."
systemctl restart mariadb

if systemctl is-active --quiet mariadb; then
    log "[OK] MariaDB restarted successfully."
else
    log "[FAIL] MariaDB failed to start after tuning."

    systemctl status mariadb --no-pager -l | tee -a "$SEC_LOG"

    log "Restoring previous configuration..."
    cp -a "$BACKUP_FILE" "$MYCNF"
    systemctl restart mariadb

    unset DB_ROOT_PASS

    log "[OK] Previous configuration restored."
    exit 1
fi

# Validate active settings
log "Validating active MariaDB settings..."

ACTIVE_BUFFER_POOL="$(
    mariadb -u root -p"$DB_ROOT_PASS" -Nse \
    "SHOW VARIABLES LIKE 'innodb_buffer_pool_size';" |
    awk '{print $2}'
)"

ACTIVE_LOG_FILE="$(
    mariadb -u root -p"$DB_ROOT_PASS" -Nse \
    "SHOW VARIABLES LIKE 'innodb_log_file_size';" |
    awk '{print $2}'
)"

ACTIVE_MAX_CONNECTIONS="$(
    mariadb -u root -p"$DB_ROOT_PASS" -Nse \
    "SHOW VARIABLES LIKE 'max_connections';" |
    awk '{print $2}'
)"

ACTIVE_QUERY_CACHE="$(
    mariadb -u root -p"$DB_ROOT_PASS" -Nse \
    "SHOW VARIABLES LIKE 'query_cache_size';" |
    awk '{print $2}'
)"

if [[ -z "$ACTIVE_BUFFER_POOL" ||
      -z "$ACTIVE_LOG_FILE" ||
      -z "$ACTIVE_MAX_CONNECTIONS" ||
      -z "$ACTIVE_QUERY_CACHE" ]]; then

    log "[FAIL] Could not read active MariaDB tuning values."

    log "Restoring previous configuration..."
    cp -a "$BACKUP_FILE" "$MYCNF"
    systemctl restart mariadb

    unset DB_ROOT_PASS

    log "[OK] Previous configuration restored."
    exit 1
fi

BUFFER_POOL_MB_ACTIVE=$((ACTIVE_BUFFER_POOL / 1024 / 1024))
LOG_FILE_MB_ACTIVE=$((ACTIVE_LOG_FILE / 1024 / 1024))

log "Active innodb_buffer_pool_size: ${BUFFER_POOL_MB_ACTIVE} MB"
log "Active innodb_log_file_size: ${LOG_FILE_MB_ACTIVE} MB"
log "Active max_connections: ${ACTIVE_MAX_CONNECTIONS}"
log "Active query_cache_size: ${ACTIVE_QUERY_CACHE}"

# Verify requested values
FAIL=0

if [[ "$BUFFER_POOL_MB_ACTIVE" -ne "$BUFFER_POOL_MB" ]]; then
    log "[FAIL] InnoDB buffer pool value does not match the target."
    FAIL=1
else
    log "[OK] InnoDB buffer pool matches 60% RAM target."
fi

if [[ "$LOG_FILE_MB_ACTIVE" -ne 256 ]]; then
    log "[FAIL] InnoDB log file size does not match 256 MB."
    FAIL=1
else
    log "[OK] InnoDB log file size is 256 MB."
fi

if [[ "$ACTIVE_MAX_CONNECTIONS" -ne 100 ]]; then
    log "[FAIL] max_connections does not match 100."
    FAIL=1
else
    log "[OK] max_connections is 100."
fi

if [[ "$ACTIVE_QUERY_CACHE" -ne 33554432 ]]; then
    log "[FAIL] query_cache_size does not match 32 MB."
    FAIL=1
else
    log "[OK] query_cache_size is 32 MB."
fi

# Collect performance counters
log "Collecting MariaDB performance counters..."

mariadb -u root -p"$DB_ROOT_PASS" -e "
SHOW GLOBAL STATUS LIKE 'Threads_connected';
SHOW GLOBAL STATUS LIKE 'Threads_running';
SHOW GLOBAL STATUS LIKE 'Connections';
SHOW GLOBAL STATUS LIKE 'Queries';
SHOW GLOBAL STATUS LIKE 'Slow_queries';
" | tee -a "$SEC_LOG"

# Database connectivity test
if mariadb -u root -p"$DB_ROOT_PASS" -e "SELECT 1;" >/dev/null 2>&1; then
    log "[OK] MariaDB connectivity test passed."
else
    log "[FAIL] MariaDB connectivity test failed."
    unset DB_ROOT_PASS
    exit 1
fi

unset DB_ROOT_PASS

if [[ "$FAIL" -ne 0 ]]; then
    log "[FAIL] One or more tuning values were not applied."
    exit 1
fi

echo
echo "=========================================="
echo " MariaDB Performance Tuning"
echo "=========================================="
echo "MariaDB version:        $MARIADB_VERSION"
echo "RAM:                    ${RAM_MB} MB"
echo "Buffer pool target:     ${BUFFER_POOL_MB} MB"
echo "Buffer pool active:     ${BUFFER_POOL_MB_ACTIVE} MB"
echo "InnoDB log file size:   ${LOG_FILE_MB_ACTIVE} MB"
echo "Max connections:        ${ACTIVE_MAX_CONNECTIONS}"
echo "Query cache size:       ${ACTIVE_QUERY_CACHE}"
echo "MariaDB service:        $(systemctl is-active mariadb)"
echo "Configuration:          $MYCNF"
echo "Backup:                 $BACKUP_FILE"
echo "Security log:           $SEC_LOG"
echo "=========================================="

log "[OK] MariaDB performance tuning completed successfully."
