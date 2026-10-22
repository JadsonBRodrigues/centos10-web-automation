#!/bin/bash
# script11-php-tuning.sh - Applies PHP performance and upload settings
# Usage: ./script11-php-tuning.sh

set -euo pipefail

[[ $EUID -eq 0 ]] || {
    echo "Run as root (sudo)."
    exit 1
}

BASE="$(cd "$(dirname "$0")/.." && pwd)"
SEC_LOG="/var/log/seguranca.log"
PHP_INI="/etc/php.ini"
BACKUP_DIR="$BASE/logs"
BACKUP_FILE="$BACKUP_DIR/php.ini.backup-$(date +%F_%H%M%S)"

mkdir -p "$BACKUP_DIR"
touch "$SEC_LOG"
chmod 600 "$SEC_LOG"

log() {
    echo "$(date '+%F %T') [PHP] $*" | tee -a "$SEC_LOG"
}

log "Starting PHP configuration tuning..."

# Check PHP installation
if ! command -v php >/dev/null 2>&1; then
    log "[FAIL] PHP is not installed."
    exit 1
fi

PHP_VERSION="$(php -r 'echo PHP_VERSION;')"
log "[OK] PHP version: $PHP_VERSION"

# Check php.ini
if [[ ! -f "$PHP_INI" ]]; then
    log "[FAIL] PHP configuration file not found: $PHP_INI"
    exit 1
fi

log "[OK] PHP configuration file found: $PHP_INI"

# Create backup
cp -a "$PHP_INI" "$BACKUP_FILE"
log "[OK] Backup created: $BACKUP_FILE"

# Function to update a PHP parameter
set_php_value() {
    local PARAM="$1"
    local VALUE="$2"

    if grep -qE "^[;[:space:]]*${PARAM}[[:space:]]*=" "$PHP_INI"; then
        sed -i -E "s|^[;[:space:]]*${PARAM}[[:space:]]*=.*|${PARAM} = ${VALUE}|" "$PHP_INI"
    else
        echo "${PARAM} = ${VALUE}" >> "$PHP_INI"
    fi
}

log "Applying PHP configuration..."

set_php_value "date.timezone" "Europe/Lisbon"
set_php_value "upload_max_filesize" "20M"
set_php_value "post_max_size" "25M"
set_php_value "memory_limit" "256M"

log "[OK] PHP parameters configured."

echo
echo "Configured PHP parameters:"
grep -E \
    '^[[:space:]]*(date\.timezone|upload_max_filesize|post_max_size|memory_limit)[[:space:]]*=' \
    "$PHP_INI"

# Validate PHP configuration syntax
log "Validating PHP configuration..."

if php -r 'exit((int)!ini_get("date.timezone"));' >/dev/null 2>&1; then
    log "[OK] PHP configuration is readable."
else
    log "[FAIL] PHP configuration validation failed."
    cp -a "$BACKUP_FILE" "$PHP_INI"
    exit 1
fi

# Restart PHP-FPM
if systemctl cat php-fpm.service >/dev/null 2>&1; then
    log "Restarting PHP-FPM..."
    systemctl restart php-fpm

    if systemctl is-active --quiet php-fpm; then
        log "[OK] PHP-FPM restarted successfully."
    else
        log "[FAIL] PHP-FPM failed to start."

        log "Restoring previous PHP configuration..."
        cp -a "$BACKUP_FILE" "$PHP_INI"
        systemctl restart php-fpm

        log "[OK] Previous PHP configuration restored."
        exit 1
    fi
else
    log "[WARN] PHP-FPM service was not found."
fi

# Restart Apache to ensure PHP configuration is loaded
log "Restarting Apache..."
systemctl restart httpd

if systemctl is-active --quiet httpd; then
    log "[OK] Apache restarted successfully."
else
    log "[FAIL] Apache failed to start."

    log "Restoring previous PHP configuration..."
    cp -a "$BACKUP_FILE" "$PHP_INI"
    systemctl restart php-fpm
    systemctl restart httpd

    log "[OK] Previous PHP configuration restored."
    exit 1
fi

# Validate active PHP values
log "Validating active PHP settings..."

ACTIVE_TIMEZONE="$(php -r 'echo ini_get("date.timezone");')"
ACTIVE_UPLOAD="$(php -r 'echo ini_get("upload_max_filesize");')"
ACTIVE_POST="$(php -r 'echo ini_get("post_max_size");')"
ACTIVE_MEMORY="$(php -r 'echo ini_get("memory_limit");')"

log "Active date.timezone: $ACTIVE_TIMEZONE"
log "Active upload_max_filesize: $ACTIVE_UPLOAD"
log "Active post_max_size: $ACTIVE_POST"
log "Active memory_limit: $ACTIVE_MEMORY"

FAIL=0

if [[ "$ACTIVE_TIMEZONE" != "Europe/Lisbon" ]]; then
    log "[FAIL] date.timezone does not match the requested value."
    FAIL=1
else
    log "[OK] date.timezone is Europe/Lisbon."
fi

if [[ "$ACTIVE_UPLOAD" != "20M" ]]; then
    log "[FAIL] upload_max_filesize does not match 20M."
    FAIL=1
else
    log "[OK] upload_max_filesize is 20M."
fi

if [[ "$ACTIVE_POST" != "25M" ]]; then
    log "[FAIL] post_max_size does not match 25M."
    FAIL=1
else
    log "[OK] post_max_size is 25M."
fi

if [[ "$ACTIVE_MEMORY" != "256M" ]]; then
    log "[FAIL] memory_limit does not match 256M."
    FAIL=1
else
    log "[OK] memory_limit is 256M."
fi

echo
echo "=========================================="
echo " PHP Configuration Tuning"
echo "=========================================="
echo "PHP version:            $PHP_VERSION"
echo "Configuration:          $PHP_INI"
echo "date.timezone:          $ACTIVE_TIMEZONE"
echo "upload_max_filesize:    $ACTIVE_UPLOAD"
echo "post_max_size:          $ACTIVE_POST"
echo "memory_limit:           $ACTIVE_MEMORY"
echo "PHP-FPM service:        $(systemctl is-active php-fpm 2>/dev/null || echo 'not found')"
echo "Apache service:         $(systemctl is-active httpd)"
echo "Backup:                 $BACKUP_FILE"
echo "Security log:           $SEC_LOG"
echo "=========================================="

if [[ "$FAIL" -ne 0 ]]; then
    log "[FAIL] One or more PHP settings were not applied correctly."
    exit 1
fi

log "[OK] PHP configuration tuning completed successfully."
