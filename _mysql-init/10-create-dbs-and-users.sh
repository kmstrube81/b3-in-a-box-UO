#!/usr/bin/env bash
set -euo pipefail

# This runs inside the official MariaDB image during first bootstrap.
# It has MYSQL_ROOT_PASSWORD in env and the server is already up.

mysql=( mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" --protocol=socket -hlocalhost --execute )

# Helper: CREATE DATABASE if not exists with sane defaults
create_db() {
  local db="$1"
  ${mysql[@]} "CREATE DATABASE IF NOT EXISTS \`$db\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
}

# Helper: CREATE USER if not exists and grant full privileges on db.*
create_user_and_grant() {
  local user="$1" pass="$2" db="$3"
  # Create user for both '%' and 'localhost' to be friendly
  ${mysql[@]} "CREATE USER IF NOT EXISTS '$user'@'%' IDENTIFIED BY '${pass}';"
  ${mysql[@]} "CREATE USER IF NOT EXISTS '$user'@'localhost' IDENTIFIED BY '${pass}';"
  ${mysql[@]} "GRANT ALL PRIVILEGES ON \`$db\`.* TO '$user'@'%';"
  ${mysql[@]} "GRANT ALL PRIVILEGES ON \`$db\`.* TO '$user'@'localhost';"
  ${mysql[@]} "FLUSH PRIVILEGES;"
}

echo "[initdb] Creating B3 database/user…"
create_db "${MYSQL_B3_DB}"
create_user_and_grant "${MYSQL_B3_USER}" "${MYSQL_B3_PASSWORD}" "${MYSQL_B3_DB}"

echo "[initdb] Done."
