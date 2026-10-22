#!/bin/bash
# script02-install-services.sh - Installs and enables Apache, PHP and MariaDB
# Usage: ./script02-install-services.sh

set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Run as root (sudo)."; exit 1; }

# Load configuration created by script00-prepare.sh
CONFIG="$(cd "$(dirname "$0")/.." && pwd)/config.env"
[[ -f "$CONFIG" ]] || { echo "Missing $CONFIG. Run script00-prepare.sh first."; exit 1; }
source "$CONFIG"
SERVER_IP="${IP%/*}"

# 1. Install packages
echo "[*] Installing Apache, PHP and MariaDB..."
dnf install -y httpd php php-fpm php-mysqlnd mariadb-server

# 2. Enable and start services
echo "[*] Enabling and starting services..."
systemctl enable --now mariadb
systemctl enable --now php-fpm
systemctl enable --now httpd
systemctl restart httpd

# 3. Create PHP test file
cat > /var/www/html/info.php <<'EOF'
<?php phpinfo(); ?>
EOF
echo "[OK] Created /var/www/html/info.php"

# 4. Check services
for SVC in httpd php-fpm mariadb; do
    STATE="$(systemctl is-active "$SVC" || true)"
    echo "[*] $SVC: $STATE"
done

# 5. Check website (local and server IP)
FAIL=0
for URL in "http://localhost/info.php" "http://$SERVER_IP/info.php"; do
    CODE="$(curl -s -o /dev/null -w '%{http_code}' "$URL" || true)"
    if [[ "$CODE" == "200" ]]; then
        echo "[OK] $URL (HTTP $CODE)"
    else
        echo "[FAIL] $URL (HTTP $CODE)"
        FAIL=1
    fi
done

[[ $FAIL -eq 0 ]] && echo "[OK] Services installed and website reachable." \
                  || echo "[WARN] Some checks failed. Review the output above."
