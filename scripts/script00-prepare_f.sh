#!/bin/bash
# script00-prepare.sh - Creates the project structure, copies all scripts and collects network data
# Usage: ./script00-prepare.sh

set -euo pipefail

[[ $EUID -eq 0 ]] || {
    echo "Run as root (sudo)."
    exit 1
}

# Identify the real user who launched the script with sudo
REAL_USER="${SUDO_USER:-root}"
REAL_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"

if [[ -z "$REAL_HOME" ]]; then
    echo "[FAIL] Could not determine the user's home directory."
    exit 1
fi

# Project paths
BASE="$REAL_HOME/projeto-web"
SCRIPT_SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_DIR="$BASE/scripts"
LOG_DIR="$BASE/logs"
CONFIG_FILE="$BASE/config.env"

echo
echo "=========================================="
echo " Project Preparation"
echo "=========================================="
echo

# 1. Create project structure

echo "[*] Creating project structure..."

mkdir -p "$SCRIPT_DIR" "$LOG_DIR"

echo "[OK] Project directory: $BASE"

# 2. Copy all project scripts

echo "[*] Copying project scripts..."

SCRIPT_COUNT=0

for SCRIPT in "$SCRIPT_SOURCE_DIR"/*.sh; do

    [[ -f "$SCRIPT" ]] || continue

    DEST="$SCRIPT_DIR/$(basename "$SCRIPT")"

    if [[ "$SCRIPT" != "$DEST" ]]; then
        cp -f "$SCRIPT" "$DEST"
    fi

    chmod +x "$DEST"
    SCRIPT_COUNT=$((SCRIPT_COUNT + 1))

done

if [[ "$SCRIPT_COUNT" -eq 0 ]]; then
    echo "[FAIL] No .sh scripts were found in:"
    echo "       $SCRIPT_SOURCE_DIR"
    exit 1
fi
echo "[OK] $SCRIPT_COUNT script(s) copied to $SCRIPT_DIR"

# 3. Set project ownership

echo "[*] Configuring project ownership..."

chown -R "$REAL_USER":"$REAL_USER" "$BASE"

echo "[OK] Project ownership set to $REAL_USER"

# 4. Detect current network configuration

echo
echo "[*] Detecting current network configuration..."

IFACE="$(ip route | awk '/default/ {print $5; exit}')"
GW="$(ip route | awk '/default/ {print $3; exit}')"
CIDR="$(ip -4 -o addr show "$IFACE" | awk '{print $4; exit}')"

if [[ -z "$IFACE" ]]; then
    echo "[FAIL] Could not detect the active network interface."
    exit 1
fi

echo "[*] Interface: $IFACE"
echo "[*] Current IP: ${CIDR:-unknown}"
echo "[*] Gateway: ${GW:-unknown}"

# 5. Ask for network configuration

echo
echo "Enter the network configuration."
echo "Press Enter to keep the default value shown in brackets."
echo

read -rp "Static IP with mask [${CIDR:-192.168.1.65/23}]: " IP
IP="${IP:-${CIDR:-192.168.1.65/23}}"

read -rp "Gateway [${GW:-192.168.1.1}]: " GATEWAY
GATEWAY="${GATEWAY:-${GW:-192.168.1.1}}"

read -rp "DNS servers [1.1.1.1 8.8.8.8]: " DNS
DNS="${DNS:-1.1.1.1 8.8.8.8}"

# 6. Validate basic values

if [[ -z "$IP" || -z "$GATEWAY" || -z "$DNS" ]]; then
    echo "[FAIL] Network configuration values cannot be empty."
    exit 1
fi

# 7. Save project configuration

echo
echo "[*] Saving project configuration..."

cat > "$CONFIG_FILE" <<EOF
IFACE="$IFACE"
IP="$IP"
GATEWAY="$GATEWAY"
DNS="$DNS"
EOF

chown "$REAL_USER":"$REAL_USER" "$CONFIG_FILE"
chmod 600 "$CONFIG_FILE"

echo "[OK] Configuration saved to $CONFIG_FILE"

# 8. Display project summary

echo
echo "=========================================="
echo " Project Preparation Completed"
echo "=========================================="
echo "Project directory:      $BASE"
echo "Scripts directory:      $SCRIPT_DIR"
echo "Logs directory:         $LOG_DIR"
echo "Configuration file:     $CONFIG_FILE"
echo "Scripts copied:         $SCRIPT_COUNT"
echo "Interface:              $IFACE"
echo "Static IP:              $IP"
echo "Gateway:                $GATEWAY"
echo "DNS:                    $DNS"
echo "Project owner:          $REAL_USER"
echo "=========================================="
echo

echo "[OK] Project structure is ready."
echo
echo "Next step:"
echo "cd \"$SCRIPT_DIR\""
echo "sudo ./script01-static-ip.sh"
echo
