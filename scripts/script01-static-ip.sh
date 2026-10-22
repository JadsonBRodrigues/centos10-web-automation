#!/bin/bash
# script01-static-ip.sh - Configures a static IP on CentOS 10 (nmcli)
# Usage: ./script01-static-ip.sh

set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Run as root (sudo)."; exit 1; }

# Load configuration created by script00-prepare.sh
CONFIG="$(cd "$(dirname "$0")/.." && pwd)/config.env"
[[ -f "$CONFIG" ]] || { echo "Missing $CONFIG. Run script00-prepare.sh first."; exit 1; }
source "$CONFIG"
echo "[*] Interface: $IFACE"

# Connection bound to the interface (create it if missing)
CON="$(nmcli -t -f NAME,DEVICE connection show | awk -F: -v d="$IFACE" '$2==d{print $1; exit}')"
if [[ -z "$CON" ]]; then
    CON="$IFACE"
    nmcli connection add type ethernet ifname "$IFACE" con-name "$CON"
fi

# Apply configuration
nmcli connection modify "$CON" \
    ipv4.method manual \
    ipv4.addresses "$IP" \
    ipv4.gateway "$GATEWAY" \
    ipv4.dns "$DNS" \
    connection.autoconnect yes

nmcli connection up "$CON"

# Validation
echo "[*] Address:"
ip -4 addr show "$IFACE" | grep inet
echo "[*] Gateway test:"
ping -c 2 "$GATEWAY"
echo "[*] Internet test:"
ping -c 2 1.1.1.1
echo "[*] DNS test:"
ping -c 2 google.com
echo "[OK] Static IP configured."
