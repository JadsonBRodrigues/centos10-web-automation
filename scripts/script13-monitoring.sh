#!/bin/bash
# script13-monitoring.sh - Configures system monitoring, security alerts and NTP
# Usage:
#   ./script13-monitoring.sh
#   ./script13-monitoring.sh --report-only

set -euo pipefail

[[ $EUID -eq 0 ]] || {
    echo "Run as root (sudo)."
    exit 1
}

BASE="$(cd "$(dirname "$0")/.." && pwd)"

LOG_DIR="$BASE/logs"
SEC_LOG="/var/log/seguranca.log"

APACHE_LOG_DIR="/var/log/httpd"
SECURE_LOG="/var/log/secure"

REPORT_DIR="$LOG_DIR/monitoring"
REPORT_FILE="$REPORT_DIR/security-report-$(date '+%Y-%m-%d_%H-%M-%S').log"

CONFIG_FILE="$BASE/config.env"

SYSTEMD_SERVICE="/etc/systemd/system/project-monitoring.service"
SYSTEMD_TIMER="/etc/systemd/system/project-monitoring.timer"

mkdir -p "$LOG_DIR" "$REPORT_DIR"

touch "$SEC_LOG"
chmod 600 "$SEC_LOG"

log() {
    echo "$(date '+%F %T') [MONITORING] $*" | tee -a "$SEC_LOG"
}

log "Starting monitoring configuration..."

# Check required commands
for CMD in systemctl journalctl awk grep sed date hostname mailx chronyc; do
    if ! command -v "$CMD" >/dev/null 2>&1; then
        log "[FAIL] Required command not found: $CMD"
        exit 1
    fi
done

# Load project configuration
if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
fi

if [[ -z "${ALERT_EMAIL:-}" ]]; then
    log "[FAIL] ALERT_EMAIL is not configured in $CONFIG_FILE."
    exit 1
fi

# Install and enable monitoring dependencies
if [[ "${1:-}" != "--report-only" ]]; then
    log "Installing monitoring packages..."

    dnf install -y chrony mailx

    log "[OK] Monitoring packages installed."
fi

# Configure NTP using Chrony
log "Configuring time synchronization..."

systemctl enable --now chronyd

if systemctl is-active --quiet chronyd; then
    log "[OK] Chrony service is active."
else
    log "[FAIL] Chrony service is not active."
    exit 1
fi

if chronyc tracking >/dev/null 2>&1; then
    log "[OK] Chrony is responding."
else
    log "[FAIL] Chrony is not responding."
    exit 1
fi

# Check synchronization status
if chronyc waitsync 5 >/dev/null 2>&1; then
    log "[OK] System clock is synchronized."
else
    log "[WARN] System clock synchronization is not yet confirmed."
fi

# Generate monitoring report
log "Generating security monitoring report..."

{
    echo "=========================================="
    echo " Security Monitoring Report"
    echo "=========================================="
    echo "Hostname:        $(hostname)"
    echo "Date:            $(date '+%F %T %Z')"
    echo "Server:          $(hostname -f 2>/dev/null || hostname)"
    echo "=========================================="
    echo

    echo "----- SYSTEM INFORMATION -----"
    uptime
    echo

    echo "----- TIME SYNCHRONIZATION -----"
    chronyc tracking 2>/dev/null || true
    echo
    chronyc sources -v 2>/dev/null || true
    echo

    echo "----- APACHE LOGS -----"

    if [[ -d "$APACHE_LOG_DIR" ]]; then
        echo "Apache log directory: $APACHE_LOG_DIR"
        echo
        echo "Recent Apache error log entries:"
        if [[ -f "$APACHE_LOG_DIR/error_log" ]]; then
            tail -n 30 "$APACHE_LOG_DIR/error_log"
        else
            echo "No error_log file found."
        fi

        echo
        echo "Recent Apache access log entries:"
        if [[ -f "$APACHE_LOG_DIR/access_log" ]]; then
            tail -n 30 "$APACHE_LOG_DIR/access_log"
        else
            echo "No access_log file found."
        fi
    else
        echo "Apache log directory not found."
    fi

    echo
    echo "----- SSH AND AUTHENTICATION LOGS -----"

    if [[ -f "$SECURE_LOG" ]]; then
        echo "Recent authentication failures:"
        grep -Ei "failed password|authentication failure|invalid user|failed publickey" \
            "$SECURE_LOG" | tail -n 30 || echo "No recent authentication failures found."

        echo
        echo "Recent successful SSH logins:"
        grep -Ei "accepted password|accepted publickey" \
            "$SECURE_LOG" | tail -n 20 || echo "No recent successful SSH logins found."
    else
        echo "Secure log not found."
    fi

    echo
    echo "----- APACHE HTTP SECURITY EVENTS -----"

    if [[ -f "$APACHE_LOG_DIR/access_log" ]]; then
        echo "Recent HTTP 4xx responses:"
        awk '$9 ~ /^4/ {print}' "$APACHE_LOG_DIR/access_log" | tail -n 20 \
            || echo "No recent HTTP 4xx responses found."

        echo
        echo "Recent HTTP 5xx responses:"
        awk '$9 ~ /^5/ {print}' "$APACHE_LOG_DIR/access_log" | tail -n 20 \
            || echo "No recent HTTP 5xx responses found."
    else
        echo "Apache access log not found."
    fi

    echo
    echo "----- FAIL2BAN EVENTS -----"

    if [[ -f "/var/log/fail2ban.log" ]]; then
        grep -Ei "Ban|Unban|Found" /var/log/fail2ban.log | tail -n 30 \
            || echo "No recent Fail2ban security events found."
    else
        echo "Fail2ban log not found."
    fi

    echo
    echo "----- MODSECURITY EVENTS -----"

    if [[ -f "$APACHE_LOG_DIR/error_log" ]]; then
        grep -Ei "ModSecurity|Access denied|[id]" "$APACHE_LOG_DIR/error_log" | tail -n 30 \
            || echo "No recent ModSecurity events found."
    else
        echo "Apache error log not found."
    fi

    echo
    echo "----- SYSTEMD SECURITY EVENTS -----"

    journalctl --since "24 hours ago" -p warning..alert --no-pager 2>/dev/null \
        | tail -n 50 || true

    echo
    echo "----- MONITORING STATUS -----"

    echo "Apache:"
    systemctl is-active httpd || true

    echo
    echo "MariaDB:"
    systemctl is-active mariadb || true

    echo
    echo "PHP-FPM:"
    systemctl is-active php-fpm || true

    echo
    echo "Fail2ban:"
    systemctl is-active fail2ban || true

    echo
    echo "Postfix:"
    systemctl is-active postfix || true

    echo
    echo "Chrony:"
    systemctl is-active chronyd || true

    echo
    echo "=========================================="
    echo " End of Security Monitoring Report"
    echo "=========================================="

} > "$REPORT_FILE"

chmod 600 "$REPORT_FILE"

log "[OK] Security monitoring report created: $REPORT_FILE"

# Detect security events for email alert
ALERT_FILE="/tmp/project-security-alert-$$.txt"

{
    echo "Project Security Alert"
    echo
    echo "Hostname: $(hostname)"
    echo "Date: $(date '+%F %T %Z')"
    echo

    echo "SSH authentication failures:"
    if [[ -f "$SECURE_LOG" ]]; then
        grep -Ei "failed password|authentication failure|invalid user|failed publickey" \
            "$SECURE_LOG" | tail -n 10 || echo "None detected."
    else
        echo "Secure log not found."
    fi

    echo
    echo "Fail2ban events:"
    if [[ -f "/var/log/fail2ban.log" ]]; then
        grep -Ei "Ban|Found" /var/log/fail2ban.log | tail -n 10 \
            || echo "None detected."
    else
        echo "Fail2ban log not found."
    fi

    echo
    echo "ModSecurity events:"
    if [[ -f "$APACHE_LOG_DIR/error_log" ]]; then
        grep -Ei "ModSecurity|Access denied" "$APACHE_LOG_DIR/error_log" | tail -n 10 \
            || echo "None detected."
    else
        echo "Apache error log not found."
    fi
} > "$ALERT_FILE"

# Count security events
SSH_FAILURES=0
FAIL2BAN_EVENTS=0
MODSECURITY_EVENTS=0

if [[ -f "$SECURE_LOG" ]]; then
    SSH_FAILURES="$(grep -Eic "failed password|authentication failure|invalid user|failed publickey" "$SECURE_LOG" || true)"
fi

if [[ -f "/var/log/fail2ban.log" ]]; then
    FAIL2BAN_EVENTS="$(grep -Eic "Ban|Found" /var/log/fail2ban.log || true)"
fi

if [[ -f "$APACHE_LOG_DIR/error_log" ]]; then
    MODSECURITY_EVENTS="$(grep -Eic "ModSecurity|Access denied" "$APACHE_LOG_DIR/error_log" || true)"
fi

TOTAL_SECURITY_EVENTS=$((SSH_FAILURES + FAIL2BAN_EVENTS + MODSECURITY_EVENTS))

# Send security alert email if events are detected
if (( TOTAL_SECURITY_EVENTS > 0 )); then

    SUBJECT="[SECURITY ALERT] $(hostname) - $TOTAL_SECURITY_EVENTS event(s) detected"

    if mailx -s "$SUBJECT" "$ALERT_EMAIL" < "$ALERT_FILE"; then
        log "[OK] Security alert email sent to configured recipient."
    else
        log "[FAIL] Unable to send security alert email."
    fi

else
    log "[OK] No security events requiring an email alert were detected."
fi

rm -f "$ALERT_FILE"

# Create systemd monitoring service
if [[ "${1:-}" != "--report-only" ]]; then

    log "Creating systemd monitoring service..."

    cat > "$SYSTEMD_SERVICE" <<EOF
[Unit]
Description=Project Security Monitoring
After=network-online.target

[Service]
Type=oneshot
ExecStart=/bin/bash $BASE/scripts/script13-monitoring.sh --report-only
EOF

    log "Creating daily monitoring timer..."

    cat > "$SYSTEMD_TIMER" <<'EOF'
[Unit]
Description=Daily Project Security Monitoring Timer

[Timer]
OnCalendar=*-*-* 03:00:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reload
    systemctl enable --now project-monitoring.timer

    if systemctl is-active --quiet project-monitoring.timer; then
        log "[OK] Daily monitoring timer is active."
    else
        log "[FAIL] Daily monitoring timer is not active."
        exit 1
    fi
fi

echo
echo "=========================================="
echo " Security Monitoring"
echo "=========================================="
echo "Report directory:       $REPORT_DIR"
echo "Latest report:          $REPORT_FILE"
echo "Alert email:            $ALERT_EMAIL"
echo "SSH failures:           $SSH_FAILURES"
echo "Fail2ban events:        $FAIL2BAN_EVENTS"
echo "ModSecurity events:     $MODSECURITY_EVENTS"
echo "NTP service:            $(systemctl is-active chronyd)"
echo "Monitoring timer:       $(systemctl is-active project-monitoring.timer 2>/dev/null || echo "not configured")"
echo "Daily monitoring time:  03:00"
echo "Security log:           $SEC_LOG"
echo "=========================================="

log "[OK] Monitoring configuration completed successfully."
