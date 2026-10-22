#!/bin/bash
# script05-selinux.sh - Ensures SELinux is enforcing, generates a sealert report
# and writes to the central security log
# Usage: ./script05-selinux.sh

set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Run as root (sudo)."; exit 1; }

BASE="$(cd "$(dirname "$0")/.." && pwd)"
LOG_DIR="$BASE/logs"
SEC_LOG="/var/log/seguranca.log"
AUDIT_LOG="/var/log/audit/audit.log"
REPORT="$LOG_DIR/sealert-$(date +%F_%H%M%S).txt"

mkdir -p "$LOG_DIR"
touch "$SEC_LOG"
chmod 600 "$SEC_LOG"

log() { echo "$(date '+%F %T') [SELINUX] $*" | tee -a "$SEC_LOG"; }

# 1. Install required tools (sealert comes from setroubleshoot-server)
log "Installing SELinux tools..."
for PKG in audit policycoreutils-python-utils setroubleshoot-server; do
    dnf install -y "$PKG" >/dev/null 2>&1 && log "Package OK: $PKG" || log "WARN: could not install $PKG"
done

# 2. Make sure auditd is running (source of /var/log/audit/audit.log)
systemctl enable --now auditd >/dev/null 2>&1 || log "WARN: auditd could not be started"

# 3. Check SELinux mode
STATUS="$(getenforce)"
log "Current SELinux mode: $STATUS"
case "$STATUS" in
    Enforcing)
        log "[OK] SELinux is in enforcing mode."
        ;;
    Permissive)
        setenforce 1
        sed -i 's/^SELINUX=.*/SELINUX=enforcing/' /etc/selinux/config
        log "[FIXED] Switched to enforcing (runtime and /etc/selinux/config)."
        ;;
    Disabled)
        sed -i 's/^SELINUX=.*/SELINUX=enforcing/' /etc/selinux/config
        touch /.autorelabel
        log "[ACTION] SELinux was disabled. Config set to enforcing; reboot is required (full relabel). Run this script again after the reboot."
        exit 0
        ;;
esac

# 4. Restore the correct SELinux context on the web root
if [[ -d /var/www/html ]]; then
    restorecon -R /var/www/html
    log "Web root context: $(ls -Zd /var/www/html | awk '{print $1}')"
fi

# 5. Count AVC denials
AVC_COUNT="$(grep -c 'type=AVC' "$AUDIT_LOG" 2>/dev/null || true)"
log "AVC denials found in audit log: ${AVC_COUNT:-0}"

# 6. Generate the sealert report
if command -v sealert >/dev/null 2>&1; then
    log "Generating sealert report (may take a while)..."
    sealert -a "$AUDIT_LOG" > "$REPORT" 2>&1 || log "WARN: sealert finished with errors"
    log "Report saved to $REPORT"
else
    log "WARN: sealert not found, report skipped."
fi

# 7. Summary
log "[OK] SELinux check completed."
echo "[*] Last entries in $SEC_LOG:"
tail -n 8 "$SEC_LOG"
