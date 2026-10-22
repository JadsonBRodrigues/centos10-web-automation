#!/bin/bash
# script06-mail-relay.sh - Configures Postfix to send alert emails through Gmail (SMTP relay)
# Usage: ./script06-mail-relay.sh

set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Run as root (sudo)."; exit 1; }

BASE="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="$BASE/config.env"
SEC_LOG="/var/log/seguranca.log"
touch "$SEC_LOG"
chmod 600 "$SEC_LOG"
log() { echo "$(date '+%F %T') [MAIL] $*" | tee -a "$SEC_LOG"; }

[[ -f "$CONFIG" ]] || { echo "Missing $CONFIG. Run script00-prepare.sh first."; exit 1; }

# 1. Ask for the Gmail account and App Password (never stored in this script)
read -rp "Gmail address (sender and alert recipient): " GMAIL_USER
[[ "$GMAIL_USER" =~ ^[A-Za-z0-9._%+-]+@gmail\.com$ ]] || { echo "Invalid Gmail address."; exit 1; }
read -rsp "Gmail App Password (16 characters, hidden): " GMAIL_PASS; echo
GMAIL_PASS="${GMAIL_PASS// /}"
[[ ${#GMAIL_PASS} -eq 16 ]] || { echo "App Password must have 16 characters (spaces are ignored)."; exit 1; }

# 2. Install packages
log "Installing Postfix and mail tools..."
dnf install -y postfix cyrus-sasl-plain >/dev/null
dnf install -y postfix-lmdb >/dev/null 2>&1 || true
dnf install -y s-nail >/dev/null 2>&1 || dnf install -y mailx >/dev/null 2>&1 || true
command -v mail >/dev/null || { log "[FAIL] No 'mail' command available."; exit 1; }

# 3. Use a map type supported by this Postfix build (lmdb on CentOS 10)
DBTYPE="$(postconf -h default_database_type)"
postconf -m | grep -qx "$DBTYPE" || { log "[FAIL] Postfix map type '$DBTYPE' not supported."; exit 1; }

# 4. Store the credentials (readable by root only)
echo "[smtp.gmail.com]:587 ${GMAIL_USER}:${GMAIL_PASS}" > /etc/postfix/sasl_passwd
chmod 600 /etc/postfix/sasl_passwd
postmap "${DBTYPE}:/etc/postfix/sasl_passwd"
chmod 600 /etc/postfix/sasl_passwd*
unset GMAIL_PASS

# 5. Configure the Postfix relay
postconf -e "inet_interfaces = loopback-only"
postconf -e "inet_protocols = ipv4"
postconf -e "relayhost = [smtp.gmail.com]:587"
postconf -e "smtp_sasl_auth_enable = yes"
postconf -e "smtp_sasl_security_options = noanonymous"
postconf -e "smtp_sasl_password_maps = ${DBTYPE}:/etc/postfix/sasl_passwd"
postconf -e "smtp_tls_security_level = encrypt"
postconf -e "smtp_tls_CAfile = /etc/pki/tls/certs/ca-bundle.crt"
postconf -e "sender_canonical_maps = static:${GMAIL_USER}"

# 6. Enable and restart Postfix
systemctl enable --now postfix
systemctl restart postfix

# 7. Save the alert address for the other scripts
if grep -q '^ALERT_EMAIL=' "$CONFIG"; then
    sed -i "s|^ALERT_EMAIL=.*|ALERT_EMAIL=\"$GMAIL_USER\"|" "$CONFIG"
else
    echo "ALERT_EMAIL=\"$GMAIL_USER\"" >> "$CONFIG"
fi
log "Alert address saved in $CONFIG"

# 8. Send a test email
log "Sending test email to $GMAIL_USER ..."
echo "Test email from $(hostname) sent at $(date)." | mail -s "[TEST] Server alerts - $(hostname)" "$GMAIL_USER"
sleep 8
echo "[*] Mail queue (empty = delivered):"
postqueue -p
echo "[*] Last delivery status:"
journalctl -t postfix/smtp --no-pager -n 5 || true

log "[OK] Mail relay configured. Check the inbox (and spam) of $GMAIL_USER."
