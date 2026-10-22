#!/bin/bash
# script09-apache-ssl-tuning.sh - Configures Apache performance and HTTPS
# Enables mod_deflate, KeepAlive, hardware-based tuning and Let's Encrypt
# Usage: ./script09-apache-ssl-tuning.sh

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
    echo "$(date '+%F %T') [APACHE] $*" | tee -a "$SEC_LOG"
}

[[ -f "$CONFIG" ]] || {
    echo "Missing $CONFIG. Run script00-prepare.sh first."
    exit 1
}

source "$CONFIG"

# Detect public IP
log "Detecting public IP..."
PUBLIC_IP="$(curl -4 -s --max-time 10 ifconfig.me || true)"

if [[ -z "$PUBLIC_IP" ]]; then
    log "[FAIL] Could not determine public IP."
    exit 1
fi

if [[ ! "$PUBLIC_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    log "[FAIL] Invalid public IP detected: $PUBLIC_IP"
    exit 1
fi

log "[OK] Public IP: $PUBLIC_IP"

# Install required packages
log "Installing Apache SSL and required packages..."
dnf install -y mod_ssl openssl certbot
log "[OK] Required packages installed."

# Create temporary localhost certificate if required
LOCAL_CERT="/etc/pki/tls/certs/localhost.crt"
LOCAL_KEY="/etc/pki/tls/private/localhost.key"

if [[ ! -s "$LOCAL_CERT" || ! -s "$LOCAL_KEY" ]]; then
    log "Creating temporary localhost certificate for Apache..."

    mkdir -p /etc/pki/tls/private

    openssl req -x509 -nodes \
        -newkey rsa:2048 \
        -keyout "$LOCAL_KEY" \
        -out "$LOCAL_CERT" \
        -days 1 \
        -subj "/CN=localhost" \
        >/dev/null 2>&1

    chmod 600 "$LOCAL_KEY"
    chmod 644 "$LOCAL_CERT"

    log "[OK] Temporary localhost certificate created."
else
    log "[OK] Existing localhost certificate found."
fi

# Configure mod_deflate
log "Configuring mod_deflate..."

cat > /etc/httpd/conf.d/deflate.conf <<'EOF'
<IfModule mod_deflate.c>
    AddOutputFilterByType DEFLATE text/plain
    AddOutputFilterByType DEFLATE text/html
    AddOutputFilterByType DEFLATE text/xml
    AddOutputFilterByType DEFLATE text/css
    AddOutputFilterByType DEFLATE application/xml
    AddOutputFilterByType DEFLATE application/xhtml+xml
    AddOutputFilterByType DEFLATE application/rss+xml
    AddOutputFilterByType DEFLATE application/javascript
    AddOutputFilterByType DEFLATE application/json
    AddOutputFilterByType DEFLATE image/svg+xml
</IfModule>
EOF

log "[OK] mod_deflate configured."

# Configure KeepAlive
log "Configuring KeepAlive..."

cat > /etc/httpd/conf.d/keepalive.conf <<'EOF'
KeepAlive On
MaxKeepAliveRequests 100
KeepAliveTimeout 5
EOF

log "[OK] KeepAlive configured."

# Detect hardware
RAM_MB="$(free -m | awk '/^Mem:/ {print $2}')"
CPU_CORES="$(nproc)"

log "Detected RAM: ${RAM_MB} MB"
log "Detected CPU cores: ${CPU_CORES}"

# Calculate MaxRequestWorkers based on RAM
if [[ "$RAM_MB" -lt 2048 ]]; then
    MAX_WORKERS=50
elif [[ "$RAM_MB" -lt 4096 ]]; then
    MAX_WORKERS=100
elif [[ "$RAM_MB" -lt 8192 ]]; then
    MAX_WORKERS=150
else
    MAX_WORKERS=200
fi

log "Calculated MaxRequestWorkers: $MAX_WORKERS"

# Configure Apache performance
log "Configuring Apache performance settings..."

cat > /etc/httpd/conf.d/performance.conf <<EOF
Timeout 60

<IfModule mpm_event_module>
    StartServers 3
    MinSpareThreads 25
    MaxSpareThreads 75
    ThreadsPerChild 25
    MaxRequestWorkers ${MAX_WORKERS}
    MaxConnectionsPerChild 1000
</IfModule>

<IfModule mpm_worker_module>
    StartServers 3
    MinSpareThreads 25
    MaxSpareThreads 75
    ThreadsPerChild 25
    MaxRequestWorkers ${MAX_WORKERS}
    MaxConnectionsPerChild 1000
</IfModule>

<IfModule mpm_prefork_module>
    StartServers 3
    MinSpareServers 5
    MaxSpareServers 10
    MaxRequestWorkers ${MAX_WORKERS}
    MaxConnectionsPerChild 1000
</IfModule>
EOF

log "[OK] Apache performance settings configured."

# Configure ServerName
log "Configuring Apache ServerName..."

cat > /etc/httpd/conf.d/servername.conf <<EOF
ServerName $PUBLIC_IP
EOF

log "[OK] ServerName configured."

# Prepare Let's Encrypt ACME challenge
log "Preparing Let's Encrypt ACME challenge directory..."

mkdir -p /var/www/html/.well-known/acme-challenge

chown -R apache:apache /var/www/html/.well-known
chmod -R 755 /var/www/html/.well-known

cat > /etc/httpd/conf.d/acme-challenge.conf <<'EOF'
Alias /.well-known/acme-challenge/ /var/www/html/.well-known/acme-challenge/

<Directory "/var/www/html/.well-known/acme-challenge/">
    AllowOverride None
    Options None
    Require all granted
</Directory>
EOF

log "[OK] ACME challenge directory configured."

# Test Apache configuration
log "Testing Apache configuration..."

if httpd -t; then
    log "[OK] Apache configuration is valid."
else
    log "[FAIL] Apache configuration is invalid."
    exit 1
fi

# Restart Apache
systemctl restart httpd

if systemctl is-active --quiet httpd; then
    log "[OK] Apache is running."
else
    log "[FAIL] Apache failed to start."
    exit 1
fi

# Test HTTP accessibility
log "Testing HTTP accessibility..."

HTTP_CODE="$(curl -s -o /dev/null -w '%{http_code}' \
    "http://$PUBLIC_IP/" || true)"

log "HTTP status: $HTTP_CODE"

if [[ "$HTTP_CODE" == "000" ]]; then
    log "[FAIL] HTTP service is not reachable."
    exit 1
fi

# Check Certbot version
CERTBOT="$(command -v certbot)"
CERTBOT_VERSION="$("$CERTBOT" --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"

MAJOR="$(echo "$CERTBOT_VERSION" | cut -d. -f1)"
MINOR="$(echo "$CERTBOT_VERSION" | cut -d. -f2)"

log "Certbot version: $CERTBOT_VERSION"

# Upgrade Certbot if version is too old for IP certificates
if (( MAJOR < 5 || (MAJOR == 5 && MINOR < 4) )); then

    log "Certbot version is too old for IP certificates."
    log "Installing Python pip..."

    dnf install -y python3-pip

    log "Upgrading Certbot using pip..."

    python3 -m pip install --upgrade certbot --break-system-packages

    CERTBOT="$(command -v certbot)"
    CERTBOT_VERSION="$("$CERTBOT" --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"

    MAJOR="$(echo "$CERTBOT_VERSION" | cut -d. -f1)"
    MINOR="$(echo "$CERTBOT_VERSION" | cut -d. -f2)"

    log "Certbot version after upgrade: $CERTBOT_VERSION"

    if (( MAJOR < 5 || (MAJOR == 5 && MINOR < 4) )); then
        log "[FAIL] Could not install Certbot 5.4 or newer."
        exit 1
    fi

    log "[OK] Certbot upgraded successfully."

else
    log "[OK] Certbot version supports IP certificates."
fi

# Configure email
ALERT_EMAIL="${ALERT_EMAIL:-root@$PUBLIC_IP}"

log "Certificate notification email: $ALERT_EMAIL"

# Let's Encrypt certificate
CERT_DIR="/etc/letsencrypt/live/$PUBLIC_IP"

if [[ -s "$CERT_DIR/fullchain.pem" && -s "$CERT_DIR/privkey.pem" ]]; then

    log "[OK] Existing Let's Encrypt certificate found."

else

    log "Requesting Let's Encrypt certificate for $PUBLIC_IP..."

    "$CERTBOT" certonly \
        --webroot \
        --webroot-path /var/www/html \
        --ip-address "$PUBLIC_IP" \
        --preferred-profile shortlived \
        --non-interactive \
        --agree-tos \
        -m "$ALERT_EMAIL" \
        --keep-until-expiring

    if [[ ! -s "$CERT_DIR/fullchain.pem" || ! -s "$CERT_DIR/privkey.pem" ]]; then
        log "[FAIL] Let's Encrypt certificate was not created."
        exit 1
    fi

    log "[OK] Let's Encrypt certificate obtained."
fi

# Configure HTTPS virtual host
log "Configuring HTTPS virtual host..."

cat > /etc/httpd/conf.d/ssl-project.conf <<EOF
<VirtualHost *:443>

    ServerName $PUBLIC_IP

    DocumentRoot /var/www/html

    SSLEngine on

    SSLCertificateFile $CERT_DIR/fullchain.pem
    SSLCertificateKeyFile $CERT_DIR/privkey.pem

    SSLProtocol -all +TLSv1.2 +TLSv1.3

    <Directory "/var/www/html">
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog /var/log/httpd/ssl_project_error.log
    CustomLog /var/log/httpd/ssl_project_access.log combined

</VirtualHost>
EOF

log "[OK] HTTPS virtual host configured."

# Configure automatic certificate renewal
log "Configuring automatic certificate renewal..."

cat > /usr/local/sbin/project-certbot-renew.sh <<'EOF'
#!/bin/bash

if /usr/bin/certbot renew --quiet; then
    systemctl reload httpd
fi
EOF

chmod 700 /usr/local/sbin/project-certbot-renew.sh

cat > /etc/systemd/system/project-certbot-renew.service <<'EOF'
[Unit]
Description=Renew Let's Encrypt certificate for project web server
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/project-certbot-renew.sh
EOF

cat > /etc/systemd/system/project-certbot-renew.timer <<'EOF'
[Unit]
Description=Automatic Let's Encrypt certificate renewal

[Timer]
OnBootSec=30min
OnUnitActiveSec=12h
RandomizedDelaySec=30min
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now project-certbot-renew.timer

log "[OK] Automatic certificate renewal configured."

# Final Apache validation
log "Performing final Apache configuration test..."

if ! httpd -t; then
    log "[FAIL] Final Apache configuration is invalid."
    exit 1
fi

log "[OK] Final Apache configuration is valid."

# Restart Apache
systemctl restart httpd

if ! systemctl is-active --quiet httpd; then
    log "[FAIL] Apache failed after final configuration."
    exit 1
fi

log "[OK] Apache restarted successfully."

# Final HTTP and HTTPS tests
HTTP_CODE="$(curl -s -o /dev/null -w '%{http_code}' \
    "http://$PUBLIC_IP/" || true)"

HTTPS_CODE="$(curl -k -s -o /dev/null -w '%{http_code}' \
    "https://$PUBLIC_IP/" || true)"

# Check modules
DEFLATE_STATUS="disabled"
KEEPALIVE_STATUS="disabled"

if httpd -M 2>/dev/null | grep -q "deflate_module"; then
    DEFLATE_STATUS="enabled"
fi

if grep -q "^KeepAlive On" /etc/httpd/conf.d/keepalive.conf; then
    KEEPALIVE_STATUS="enabled"
fi

# Check renewal timer
RENEWAL_TIMER_STATUS="$(systemctl is-active project-certbot-renew.timer || true)"

echo
echo "=========================================="
echo " Apache Performance + SSL/TLS"
echo "=========================================="
echo "Public IP:             $PUBLIC_IP"
echo "RAM:                   ${RAM_MB} MB"
echo "CPU cores:             $CPU_CORES"
echo "MaxRequestWorkers:     $MAX_WORKERS"
echo "Timeout:               60"
echo "KeepAlive:             $KEEPALIVE_STATUS"
echo "mod_deflate:           $DEFLATE_STATUS"
echo "Certbot version:       $CERTBOT_VERSION"
echo "SSL/TLS:               enabled"
echo "Certificate:           $CERT_DIR"
echo "HTTP status:           $HTTP_CODE"
echo "HTTPS status:          $HTTPS_CODE"
echo "Renewal timer:         $RENEWAL_TIMER_STATUS"
echo "Security log:          $SEC_LOG"
echo "=========================================="

log "[OK] Apache performance and SSL/TLS configuration completed."
