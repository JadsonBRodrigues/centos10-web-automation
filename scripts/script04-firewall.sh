#!/bin/bash
# script04-firewall.sh - Opens only ports 22, 80 and 443 in firewalld
# Usage: ./script04-firewall.sh

set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Run as root (sudo)."; exit 1; }

# Load configuration created by script00-prepare.sh
CONFIG="$(cd "$(dirname "$0")/.." && pwd)/config.env"
[[ -f "$CONFIG" ]] || { echo "Missing $CONFIG. Run script00-prepare.sh first."; exit 1; }
source "$CONFIG"
SERVER_IP="${IP%/*}"

ALLOWED="ssh http https"

# 1. Make sure firewalld is running
systemctl enable --now firewalld
ZONE="$(firewall-cmd --get-default-zone)"
echo "[*] Active zone: $ZONE"

# 2. Allow SSH (22), HTTP (80) and HTTPS (443)
for SVC in $ALLOWED; do
    firewall-cmd --permanent --zone="$ZONE" --add-service="$SVC"
done

# 3. Remove every other service (cockpit, dhcpv6-client, ...)
for SVC in $(firewall-cmd --permanent --zone="$ZONE" --list-services); do
    case " $ALLOWED " in
        *" $SVC "*) ;;
        *) echo "[*] Removing service: $SVC"
           firewall-cmd --permanent --zone="$ZONE" --remove-service="$SVC" ;;
    esac
done

# 4. Remove any extra open port
for PORT in $(firewall-cmd --permanent --zone="$ZONE" --list-ports); do
    echo "[*] Removing port: $PORT"
    firewall-cmd --permanent --zone="$ZONE" --remove-port="$PORT"
done

# 5. Apply changes
firewall-cmd --reload

# 6. Show result
echo "[*] Allowed services: $(firewall-cmd --zone="$ZONE" --list-services)"
echo "[*] Open ports: $(firewall-cmd --zone="$ZONE" --list-ports)"

# 7. Connectivity tests
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
ping -c 2 1.1.1.1 >/dev/null && echo "[OK] Internet reachable" || { echo "[FAIL] No Internet"; FAIL=1; }
echo "[*] Public IP: $(curl -s --max-time 5 ifconfig.me || echo 'unavailable')"

[[ $FAIL -eq 0 ]] && echo "[OK] Firewall configured." \
                  || echo "[WARN] Some checks failed. Review the output above."
