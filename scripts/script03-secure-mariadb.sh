#!/bin/bash
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Run as root."; exit 1; }

DB_ROOT_PASS="atec123#"
DB_USER="jadson"
DB_USER_PASS="atec123#"
DB_NAME="atec"

cat > /tmp/secure_mariadb.sql <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_ROOT_PASS}';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host!='localhost';
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test';
CREATE DATABASE ${DB_NAME};
CREATE USER '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_USER_PASS}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF

mysql < /tmp/secure_mariadb.sql

mysql -u root -p"${DB_ROOT_PASS}" -e "SELECT VERSION();" >/dev/null
mysql -u root -p"${DB_ROOT_PASS}" -e "SHOW DATABASES;"
mysql -u root -p"${DB_ROOT_PASS}" -e "SELECT User,Host FROM mysql.user;"
echo "[OK] MariaDB secure configuration applied."
