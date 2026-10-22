#!/bin/bash
# script07-fail2ban.sh - Installs and configures Fail2ban for SSH and Apache
# Usage: ./script07-fail2ban.sh

set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Run as root (sudo)."; exit 1; }

BASE="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="$BASE/config.env"
SEC_LOG="/var/log/seguranca.log"
touch "$SEC_LOG"
chmod 600 "$SEC_LOG"
log() { echo "$(date '+%F %T') [FAIL2BAN] $*" | tee -a "$SEC_LOG"; }

[[ -f "$CONFIG" ]] || { echo "Missing $CONFIG. Run script00-prepare.sh first."; exit 1; }
source "$CONFIG"
[[ -n "${ALERT_EMAIL:-}" ]] || { echo "ALERT_EMAIL not set. Run script06-mail-relay.sh first."; exit 1; }

MAX_RETRY=3
BAN_TIME="1h"
FIND_TIME="10m"

# 1. Install Fail2ban (from EPEL)
log "Installing EPEL and Fail2ban..."
dnf install -y epel-release >/dev/null || { log "[FAIL] Could not install epel-release."; exit 1; }
dnf install -y fail2ban >/dev/null || { log "[FAIL] Could not install fail2ban."; exit 1; }
dnf install -y fail2ban-firewalld fail2ban-systemd >/dev/null 2>&1 || true
command -v fail2ban-client >/dev/null || { log "[FAIL] fail2ban-client not found."; exit 1; }

# 2. Custom action: write to the central log and send an email on every ban
cat > /etc/fail2ban/action.d/project-alert.conf <<'EOF'
[Definition]
actionstart =
actionstop =
actioncheck =
actionban = echo "$(date '+%%F %%T') [FAIL2BAN] BANNED <ip> jail=<name> failures=<failures>" >> /var/log/seguranca.log
            echo "Fail2ban banned <ip> (jail <name>, <failures> failed attempts) on $(hostname) at $(date)." | mail -s "[Fail2ban] <ip> banned (<name>) on $(hostname)" <dest>
actionunban = echo "$(date '+%%F %%T') [FAIL2BAN] UNBANNED <ip> jail=<name>" >> /var/log/seguranca.log

[Init]
dest = root
EOF

# 3. Jails: SSH and Apache, ban after 3 failed attempts
cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
bantime  = ${BAN_TIME}
findtime = ${FIND_TIME}
maxretry = ${MAX_RETRY}
ignoreip = 127.0.0.1/8 ::1
banaction = firewallcmd-rich-rules
banaction_allports = firewallcmd-rich-rules
action = %(action_)s
         project-alert[dest=${ALERT_EMAIL}]

[sshd]
enabled  = true
backend  = systemd

[apache-auth]
enabled  = true
port     = http,https
logpath  = /var/log/httpd/error_log

[apache-badbots]
enabled  = true
port     = http,https
logpath  = /var/log/httpd/access_log
EOF

# 4. Validate the configuration
if ! OUT="$(fail2ban-client -t 2>&1)"; then
    echo "$OUT"
    log "[FAIL] Invalid Fail2ban configuration."
    exit 1
fi

# 5. Enable and start the service
systemctl enable --now fail2ban
systemctl restart fail2ban
sleep 3
systemctl is-active --quiet fail2ban || { log "[FAIL] fail2ban is not running."; journalctl -u fail2ban --no-pager -n 15; exit 1; }

# 6. Show status
echo "[*] Active jails:"
fail2ban-client status
for JAIL in sshd apache-auth apache-badbots; do
    echo "[*] Jail $JAIL:"
    fail2ban-client status "$JAIL"
done

log "[OK] Fail2ban active (sshd, apache-auth, apache-badbots). Ban after $MAX_RETRY failures, alerts to $ALERT_EMAIL"
