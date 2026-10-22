#!/bin/bash
# script14-deploy-website.sh - Final website deployment
# Usage:
#   ./script14-deploy-website.sh

set -euo pipefail

[[ $EUID -eq 0 ]] || {
    echo "Run as root (sudo)."
    exit 1
}

WEB_ROOT="/var/www/html"
INDEX_FILE="$WEB_ROOT/index.html"
SEC_LOG="/var/log/seguranca.log"

touch "$SEC_LOG"
chmod 600 "$SEC_LOG"

log() {
    echo "$(date '+%F %T') [WEBSITE] $*" | tee -a "$SEC_LOG"
}

echo
echo "=========================================="
echo " Final Website Deployment"
echo "=========================================="
echo

log "Starting final website deployment."

# Remove temporary test files
log "Removing temporary test files."

rm -f "$WEB_ROOT/info.php"
rm -f "$WEB_ROOT/modsecurity-test.php"

log "[OK] Temporary test files removed."

# Create final website
log "Creating final website."

cat > "$INDEX_FILE" <<'HTML'
<!DOCTYPE html>
<html lang="en">

<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">

    <title>ATEC Web Server Project - Jadson Rodrigues</title>

    <style>
        * {
            box-sizing: border-box;
            margin: 0;
            padding: 0;
        }

        body {
            font-family: Arial, Helvetica, sans-serif;
            background: #0f172a;
            color: #e2e8f0;
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 30px;
        }

        .container {
            width: 100%;
            max-width: 950px;
        }

        header {
            text-align: center;
            margin-bottom: 30px;
        }

        header h1 {
            color: #38bdf8;
            font-size: 42px;
            margin-bottom: 12px;
        }

        header p {
            color: #94a3b8;
            font-size: 18px;
        }

        .author {
            margin-top: 12px;
            color: #f8fafc;
            font-weight: bold;
        }

        .card {
            background: #1e293b;
            border: 1px solid #334155;
            border-radius: 16px;
            padding: 35px;
            box-shadow: 0 20px 50px rgba(0, 0, 0, 0.35);
        }

        h2 {
            color: #f8fafc;
            margin-bottom: 20px;
        }

        .description {
            color: #cbd5e1;
            line-height: 1.7;
            margin-bottom: 25px;
        }

        .grid {
            display: grid;
            grid-template-columns: repeat(2, 1fr);
            gap: 15px;
        }

        .item {
            background: #0f172a;
            border: 1px solid #334155;
            border-radius: 10px;
            padding: 18px;
        }

        .item strong {
            display: block;
            color: #38bdf8;
            margin-bottom: 6px;
        }

        .item span {
            color: #cbd5e1;
        }

        .technologies {
            margin-top: 35px;
        }

        .technology-grid {
            display: grid;
            grid-template-columns: repeat(3, 1fr);
            gap: 12px;
        }

        .technology {
            background: #0f172a;
            border: 1px solid #334155;
            border-radius: 10px;
            padding: 15px;
            text-align: center;
            color: #cbd5e1;
        }

        .technology strong {
            display: block;
            color: #38bdf8;
            margin-bottom: 5px;
        }

        .status {
            margin-top: 30px;
            padding: 15px;
            text-align: center;
            border-radius: 10px;
            background: #052e16;
            border: 1px solid #166534;
            color: #86efac;
            font-weight: bold;
        }

        footer {
            text-align: center;
            margin-top: 25px;
            color: #64748b;
            font-size: 14px;
        }

        @media (max-width: 700px) {
            header h1 {
                font-size: 32px;
            }

            .grid {
                grid-template-columns: 1fr;
            }

            .technology-grid {
                grid-template-columns: repeat(2, 1fr);
            }
        }

        @media (max-width: 450px) {
            .technology-grid {
                grid-template-columns: 1fr;
            }

            .card {
                padding: 25px;
            }
        }
    </style>
</head>

<body>

    <main class="container">

        <header>
            <h1>ATEC Web Server Project</h1>

            <p>
                Automated Configuration and Hosting of a Linux Web Server
            </p>

            <div class="author">
                Developed by Jadson Rodrigues
            </div>
        </header>

        <section class="card">

            <h2>Server Infrastructure</h2>

            <p class="description">
                This website is hosted on a CentOS Stream 10 server
                configured and automated through Bash scripts.
                The infrastructure includes web services, database services,
                network security, monitoring and automated backups.
            </p>

            <div class="grid">

                <div class="item">
                    <strong>Operating System</strong>
                    <span>CentOS Stream 10</span>
                </div>

                <div class="item">
                    <strong>Web Server</strong>
                    <span>Apache HTTP Server</span>
                </div>

                <div class="item">
                    <strong>PHP</strong>
                    <span>PHP 8.3</span>
                </div>

                <div class="item">
                    <strong>Database</strong>
                    <span>MariaDB 10.11</span>
                </div>

                <div class="item">
                    <strong>Security</strong>
                    <span>SELinux, Fail2ban and ModSecurity</span>
                </div>

                <div class="item">
                    <strong>Network</strong>
                    <span>Firewalld, SSH, HTTP and HTTPS</span>
                </div>

                <div class="item">
                    <strong>Encryption</strong>
                    <span>Let's Encrypt SSL/TLS</span>
                </div>

                <div class="item">
                    <strong>Monitoring</strong>
                    <span>Chrony, logs and email alerts</span>
                </div>

            </div>

            <section class="technologies">

                <h2>Technologies Used</h2>

                <div class="technology-grid">

                    <div class="technology">
                        <strong>CentOS Stream</strong>
                        <span>Linux Server</span>
                    </div>

                    <div class="technology">
                        <strong>Apache HTTPD</strong>
                        <span>Web Server</span>
                    </div>

                    <div class="technology">
                        <strong>PHP 8.3</strong>
                        <span>Web Application</span>
                    </div>

                    <div class="technology">
                        <strong>MariaDB 10.11</strong>
                        <span>Database Server</span>
                    </div>

                    <div class="technology">
                        <strong>Firewalld</strong>
                        <span>Network Firewall</span>
                    </div>

                    <div class="technology">
                        <strong>SELinux</strong>
                        <span>Access Control</span>
                    </div>

                    <div class="technology">
                        <strong>Fail2ban</strong>
                        <span>Intrusion Protection</span>
                    </div>

                    <div class="technology">
                        <strong>ModSecurity</strong>
                        <span>Web Application Firewall</span>
                    </div>

                    <div class="technology">
                        <strong>OWASP CRS</strong>
                        <span>Security Rules</span>
                    </div>

                    <div class="technology">
                        <strong>Let's Encrypt</strong>
                        <span>SSL/TLS Certificate</span>
                    </div>

                    <div class="technology">
                        <strong>Chrony</strong>
                        <span>NTP Synchronization</span>
                    </div>

                    <div class="technology">
                        <strong>Bash</strong>
                        <span>Automation</span>
                    </div>

                    <div class="technology">
                        <strong>Systemd</strong>
                        <span>Scheduling</span>
                    </div>

                    <div class="technology">
                        <strong>Postfix</strong>
                        <span>Email Alerts</span>
                    </div>

                    <div class="technology">
                        <strong>SSH</strong>
                        <span>Remote Administration</span>
                    </div>

                </div>

            </section>

            <div class="status">
                Server successfully configured and secured
            </div>

        </section>

        <footer>
            Jadson Rodrigues · ATEC — Network and Operating Systems Management
        </footer>

    </main>

</body>

</html>
HTML

log "[OK] Final website created."

# Set ownership and permissions
chown root:root "$INDEX_FILE"
chmod 644 "$INDEX_FILE"

log "[OK] Website permissions configured."

# Restore SELinux contexts
log "Restoring SELinux contexts."

restorecon -Rv "$WEB_ROOT" >/dev/null

if [[ "$(getenforce)" == "Enforcing" ]]; then
    log "[OK] SELinux is enforcing."
else
    log "[FAIL] SELinux is not enforcing."
    exit 1
fi

# Validate Apache
log "Validating Apache configuration."

if httpd -t >/dev/null 2>&1; then
    log "[OK] Apache configuration is valid."
else
    log "[FAIL] Apache configuration is invalid."
    httpd -t
    exit 1
fi

# Reload Apache
systemctl reload httpd

if systemctl is-active --quiet httpd; then
    log "[OK] Apache is active."
else
    log "[FAIL] Apache is not active."
    exit 1
fi

# Detect public IP
log "Detecting public IP."

PUBLIC_IP="$(curl -4 -s --max-time 10 ifconfig.me || true)"

if [[ -z "$PUBLIC_IP" ]]; then
    log "[FAIL] Could not determine public IP."
    exit 1
fi

log "[OK] Public IP: $PUBLIC_IP"

# Test local website
log "Testing local website."

LOCAL_CODE="$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1/)"

if [[ "$LOCAL_CODE" == "200" ]]; then
    log "[OK] Local HTTP test returned 200."
else
    log "[FAIL] Local HTTP test returned $LOCAL_CODE."
    exit 1
fi

# Test public HTTP
log "Testing public HTTP."

HTTP_CODE="$(curl -4 -s \
    --max-time 15 \
    -o /dev/null \
    -w '%{http_code}' \
    "http://$PUBLIC_IP/" || true)"

if [[ "$HTTP_CODE" == "200" ]]; then
    log "[OK] Public HTTP test returned 200."
else
    log "[WARN] Public HTTP test returned $HTTP_CODE."
fi

# Test public HTTPS
log "Testing public HTTPS."

HTTPS_CODE="$(curl -4 -k -s \
    --max-time 15 \
    -o /dev/null \
    -w '%{http_code}' \
    "https://$PUBLIC_IP/" || true)"

if [[ "$HTTPS_CODE" == "200" ]]; then
    log "[OK] Public HTTPS test returned 200."
else
    log "[WARN] Public HTTPS test returned $HTTPS_CODE."
fi

# Verify final files
if [[ -f "$INDEX_FILE" ]]; then
    log "[OK] Final index.html exists."
else
    log "[FAIL] Final index.html does not exist."
    exit 1
fi

if [[ ! -f "$WEB_ROOT/info.php" &&
      ! -f "$WEB_ROOT/modsecurity-test.php" ]]; then
    log "[OK] Temporary test files are removed."
else
    log "[FAIL] Temporary test files still exist."
    exit 1
fi

echo
echo "=========================================="
echo " Final Website Deployment"
echo "=========================================="
echo "Developer:          Jadson Rodrigues"
echo "Website root:       $WEB_ROOT"
echo "Index file:         $INDEX_FILE"
echo "Public IP:          $PUBLIC_IP"
echo "Local HTTP:         $LOCAL_CODE"
echo "Public HTTP:        $HTTP_CODE"
echo "Public HTTPS:       $HTTPS_CODE"
echo "Apache status:      $(systemctl is-active httpd)"
echo "SELinux:             $(getenforce)"
echo "=========================================="
echo
echo "[OK] Final website deployment completed."
echo

log "[OK] Final website deployment completed successfully."
