#!/bin/bash
# script08-modsecurity.sh - Installs and configures ModSecurity + OWASP CRS
# Tests protection against simulated SQL Injection and XSS attacks
# Usage: ./script08-modsecurity.sh

set -euo pipefail

[[ $EUID -eq 0 ]] || {
    echo "Run as root (sudo)."
    exit 1
}

BASE="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="$BASE/config.env"
SEC_LOG="/var/log/seguranca.log"

touch "$SEC_LOG"
chmod 600 "$SEC_LOG"

log() {
    echo "$(date '+%F %T') [MODSECURITY] $*" | tee -a "$SEC_LOG"
}

[[ -f "$CONFIG" ]] || {
    echo "Missing $CONFIG. Run script00-prepare.sh first."
    exit 1
}

source "$CONFIG"

MODSEC_CONF="/etc/httpd/conf.d/mod_security.conf"
CRS_SETUP="/etc/httpd/modsecurity.d/crs-setup.conf"
CRS_RULES="/usr/share/mod_modsecurity_crs/rules"
CRS_ACTIVE="/etc/httpd/modsecurity.d/activated_rules"
TEST_PAGE="/var/www/html/modsecurity-test.php"

# ------------------------------------------------------------
# Install ModSecurity and OWASP CRS
# ------------------------------------------------------------

log "Installing ModSecurity and OWASP CRS..."

dnf install -y mod_security mod_security_crs

log "[OK] ModSecurity and OWASP CRS packages installed."

# ------------------------------------------------------------
# Verify ModSecurity configuration
# ------------------------------------------------------------

if [[ ! -f "$MODSEC_CONF" ]]; then
    log "[FAIL] ModSecurity configuration file not found: $MODSEC_CONF"
    exit 1
fi

log "Configuring ModSecurity..."

if grep -qE '^[[:space:]]*SecRuleEngine' "$MODSEC_CONF"; then
    sed -i 's/^[[:space:]]*SecRuleEngine.*/SecRuleEngine On/' "$MODSEC_CONF"
else
    echo "SecRuleEngine On" >> "$MODSEC_CONF"
fi

log "[OK] SecRuleEngine is set to On."

# ------------------------------------------------------------
# Verify ModSecurity Apache module
# ------------------------------------------------------------

log "Checking ModSecurity Apache module..."

if httpd -M 2>/dev/null | grep -q "security2_module"; then
    log "[OK] ModSecurity Apache module is loaded."
else
    log "[FAIL] ModSecurity Apache module is not loaded."
    exit 1
fi

# ------------------------------------------------------------
# Verify OWASP CRS
# ------------------------------------------------------------

log "Checking OWASP CRS..."

if [[ ! -f "$CRS_SETUP" ]]; then
    log "[FAIL] OWASP CRS setup file not found: $CRS_SETUP"
    exit 1
fi

if [[ ! -d "$CRS_RULES" ]]; then
    log "[FAIL] OWASP CRS rules directory not found: $CRS_RULES"
    exit 1
fi

if [[ ! -d "$CRS_ACTIVE" ]]; then
    log "[FAIL] OWASP CRS activated rules directory not found: $CRS_ACTIVE"
    exit 1
fi

log "[OK] OWASP CRS setup found."
log "[OK] OWASP CRS rules directory found."
log "[OK] OWASP CRS activated rules directory found."

# ------------------------------------------------------------
# Verify SQL Injection and XSS rules
# ------------------------------------------------------------

SQLI_RULE="$CRS_ACTIVE/REQUEST-942-APPLICATION-ATTACK-SQLI.conf"
XSS_RULE="$CRS_ACTIVE/REQUEST-941-APPLICATION-ATTACK-XSS.conf"

if [[ -f "$SQLI_RULE" ]]; then
    log "[OK] SQL Injection protection rules are active."
else
    log "[FAIL] SQL Injection protection rules are not active."
    exit 1
fi

if [[ -f "$XSS_RULE" ]]; then
    log "[OK] XSS protection rules are active."
else
    log "[FAIL] XSS protection rules are not active."
    exit 1
fi

# ------------------------------------------------------------
# Test Apache configuration
# ------------------------------------------------------------

log "Testing Apache configuration..."

if httpd -t; then
    log "[OK] Apache configuration is valid."
else
    log "[FAIL] Apache configuration contains errors."
    exit 1
fi

# ------------------------------------------------------------
# Restart Apache
# ------------------------------------------------------------

log "Restarting Apache..."

systemctl restart httpd

if systemctl is-active --quiet httpd; then
    log "[OK] Apache is running."
else
    log "[FAIL] Apache failed to start."
    exit 1
fi

# ------------------------------------------------------------
# Create ModSecurity test page
# ------------------------------------------------------------

log "Creating ModSecurity test page..."

cat > "$TEST_PAGE" <<'EOF'
<?php
echo "ModSecurity test page";
?>
EOF

restorecon "$TEST_PAGE" 2>/dev/null || true

log "[OK] Test page created: $TEST_PAGE"

# ------------------------------------------------------------
# Test normal request
# ------------------------------------------------------------

log "Testing normal HTTP request..."

NORMAL_CODE="$(curl -s -o /dev/null -w '%{http_code}' \
    "http://127.0.0.1/modsecurity-test.php" || true)"

if [[ "$NORMAL_CODE" == "200" ]]; then
    log "[OK] Normal request allowed (HTTP $NORMAL_CODE)."
else
    log "[WARN] Normal request returned HTTP $NORMAL_CODE."
fi

# ------------------------------------------------------------
# SQL Injection test
# ------------------------------------------------------------

log "Testing SQL Injection protection..."

SQLI_URL="http://127.0.0.1/modsecurity-test.php?id=1%27%20OR%20%271%27=%271"

SQLI_CODE="$(curl -s -o /tmp/modsec-sqli-response \
    -w '%{http_code}' \
    "$SQLI_URL" || true)"

if [[ "$SQLI_CODE" == "403" ]]; then
    log "[OK] SQL Injection test BLOCKED (HTTP $SQLI_CODE)."
else
    log "[WARN] SQL Injection test returned HTTP $SQLI_CODE."
fi

# ------------------------------------------------------------
# XSS test
# ------------------------------------------------------------

log "Testing XSS protection..."

XSS_URL="http://127.0.0.1/modsecurity-test.php?q=%3Cscript%3Ealert(1)%3C%2Fscript%3E"

XSS_CODE="$(curl -s -o /tmp/modsec-xss-response \
    -w '%{http_code}' \
    "$XSS_URL" || true)"

if [[ "$XSS_CODE" == "403" ]]; then
    log "[OK] XSS test BLOCKED (HTTP $XSS_CODE)."
else
    log "[WARN] XSS test returned HTTP $XSS_CODE."
fi

# ------------------------------------------------------------
# Check ModSecurity audit log
# ------------------------------------------------------------

log "Checking ModSecurity audit log..."

if [[ -f /var/log/httpd/modsec_audit.log ]]; then
    log "[OK] ModSecurity audit log found."
else
    log "[WARN] ModSecurity audit log was not found."
fi

# ------------------------------------------------------------
# Final status
# ------------------------------------------------------------

echo
echo "=========================================="
echo " ModSecurity + OWASP CRS"
echo "=========================================="
echo "ModSecurity:  $(httpd -M 2>/dev/null | grep security2 || echo 'not detected')"
echo "SecRuleEngine: $(grep -E '^[[:space:]]*SecRuleEngine' "$MODSEC_CONF" | tail -1)"
echo "CRS setup:    $CRS_SETUP"
echo "CRS rules:    $CRS_ACTIVE"
echo "Apache:       $(systemctl is-active httpd)"
echo
echo "Normal request:     HTTP $NORMAL_CODE"
echo "SQL Injection test: HTTP $SQLI_CODE"
echo "XSS test:           HTTP $XSS_CODE"
echo
echo "Security log: $SEC_LOG"
echo "=========================================="

log "[OK] ModSecurity and OWASP CRS configuration completed."
