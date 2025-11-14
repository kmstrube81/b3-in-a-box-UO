#!/usr/bin/env bash
set -euo pipefail

# --- locate the example ini inside the cloned repo ---
TEMPLATE=""
for CAND in \
  /opt/b3/b3/conf/b3.distribution.ini \
  /opt/b3/b3/conf/b3.ini
do
  if [ -f "$CAND" ]; then TEMPLATE="$CAND"; break; fi
done

if [ -z "${TEMPLATE}" ]; then
  echo "ERROR: could not find b3.distribution.ini in the image" >&2
  ls -al /opt/b3/b3/conf || true
  exit 1
fi

# Ensure runtime dirs exist (safe if host bind-mounts are empty)
mkdir -p /app/conf /app/extplugins /app/logs

# NEW: expose built-in extplugins from the image into the volume-based dir
# so B3 (which is set to use /app/extplugins) can still see repo plugins.
/bin/true
if [ -d /opt/b3/b3/extplugins ]; then
  for f in /opt/b3/b3/extplugins/*.py; do
    [ -e "$f" ] || continue
    base="$(basename "$f")"
    dest="/app/extplugins/$base"
    # only create the symlink if the user hasn't provided their own file
    if [ ! -e "$dest" ]; then
      ln -s "$f" "$dest"
    fi
  done
  # make sure the package marker exists in /app/extplugins
  if [ -e /opt/b3/b3/extplugins/__init__.py ] && [ ! -e /app/extplugins/__init__.py ]; then
    ln -s /opt/b3/b3/extplugins/__init__.py /app/extplugins/__init__.py 2>/dev/null || true
  elif [ ! -e /app/extplugins/__init__.py ]; then
    # fall back to creating an empty one
    touch /app/extplugins/__init__.py
  fi
fi

OUT_INI="/app/conf/b3.ini"

# --- dequote helper (because .env often contains quotes on Windows) ---
dequote() {
  local v="${1:-}"
  v="${v%\"}"; v="${v#\"}"
  printf '%s' "$v"
}

# ---- Normalize DB/envs -------------------------------------------------------
DB_HOST="${MYSQL_B3_HOST:-db}"
DB_NAME="$(dequote "${MYSQL_B3_DB:-b3}")"
DB_USER="$(dequote "${MYSQL_B3_USER:-b3user}")"
DB_PASS="$(dequote "${MYSQL_B3_PASSWORD:-b3pass}")"
DB_DSN="mysql://${DB_USER}:${DB_PASS}@${DB_HOST}/${DB_NAME}"

PARSER="$(dequote "${B3_PARSER:-cod}")"
BOT_NAME="$(dequote "${B3_BOT_NAME:-b3}")"
BOT_PREFIX="$(dequote "${B3_BOT_PREFIX:-^0(^2b3^0)^7:}")"
RCON_IP="$(dequote "${B3_RCON_IP:-host.docker.internal}")"
RCON_PORT="$(dequote "${B3_RCON_PORT:-28960}")"
RCON_PASSWORD="$(dequote "${B3_RCON_PASSWORD:-rconpass}")"
GL_FILE_RAW="$(dequote "${B3_GAME_LOG_FILE:-}")"   # either filename OR full URL
if [[ "$GL_FILE_RAW" =~ ^https?:// || "$GL_FILE_RAW" =~ ^ftp:// ]]; then
  GAME_LOG="$GL_FILE_RAW"
else
  if [ -z "$GL_FILE_RAW" ]; then
    GL_FILE_RAW="games_mp.log"
  fi
  GAME_LOG="/game-logs/${GL_FILE_RAW}"
fi

echo "=== ENV seen by b3 entrypoint ==="
echo "MYSQL_B3_DB=${DB_NAME}"
echo "MYSQL_B3_USER=${DB_USER}"
echo "MYSQL_B3_PASSWORD=${DB_PASS}"
echo "B3_DB_HOST=${DB_HOST}"
echo "B3_PARSER=${PARSER}"
echo "B3_BOT_NAME=${BOT_NAME}"
echo "B3_BOT_PREFIX=${BOT_PREFIX}"
echo "B3_GAME_LOG=${GAME_LOG}"
echo "B3_RCON_IP=${RCON_IP}"
echo "B3_RCON_PORT=${RCON_PORT}"
echo "B3_RCON_PASSWORD=${RCON_PASSWORD}"
echo "DB_DSN=${DB_DSN}"
echo "Using template: ${TEMPLATE}"
echo "Target ini: ${OUT_INI}"
echo "================================="

# --- function: sync INI keys to env ------------------------------------------
sync_b3_ini() {
  local ini="$1"
  local tmp="${ini}.tmp"

  sed -i 's/\r$//' "$ini" || true

    awk -v parser="$PARSER" \
      -v dsn="$DB_DSN" \
      -v bot="$BOT_NAME" \
      -v prefix="$BOT_PREFIX" \
      -v game_log="$GAME_LOG" \
      -v rip="$RCON_IP" \
      -v rport="$RCON_PORT" \
      -v rpass="$RCON_PASSWORD" '
    BEGIN { sec = "" }
    /^\[/ { sec = $0 }

    {
      if (sec ~ /^\[b3\]/) {
        if ($0 ~ /^[ \t]*parser[ \t]*[:=]/)          { $0 = "parser: " parser }
        else if ($0 ~ /^[ \t]*database[ \t]*[:=]/)   { $0 = "database: " dsn }
        else if ($0 ~ /^[ \t]*bot_name[ \t]*[:=]/)   { $0 = "bot_name: " bot }
        else if ($0 ~ /^[ \t]*bot_prefix[ \t]*[:=]/) { $0 = "bot_prefix: " prefix }
      } else if (sec ~ /^\[server\]/) {
        if      ($0 ~ /^[ \t]*game_log[ \t]*[:=]/)      { $0 = "game_log: " game_log }
        else if ($0 ~ /^[ \t]*rcon_ip[ \t]*[:=]/)       { $0 = "rcon_ip: " rip }
        else if ($0 ~ /^[ \t]*port[ \t]*[:=]/)          { $0 = "port: " rport }
        else if ($0 ~ /^[ \t]*rcon_password[ \t]*[:=]/) { $0 = "rcon_password: " rpass }
        else if ($0 ~ /^[ \t]*punkbuster[ \t]*[:=]/)    { $0 = "punkbuster: off" }
      } else if (sec ~ /^\[plugins\]/) {
        if      ($0 ~ /^[ \t]*xlrstats[ \t]*[:=]/)      { $0 = "xlrstats: /app/conf/plugin_xlrstats.ini" }
        else if ($0 ~ /^[ \t]*playercardedit[ \t]*[:=]/){ $0 = "playercardedit: /app/conf/plugin_playercardedit.xml" }
      }
      print
    }
  ' "$ini" > "$tmp" && mv "$tmp" "$ini"

  # normalize plugin paths and extplugins dir to /app
  sed -i -E \
    -e 's#@?b3/conf/#/app/conf/#g' \
    -e 's#(^[[:space:]]*[A-Za-z0-9_]+:[[:space:]]*)conf/#\1/app/conf/#' \
    -e 's#@?b3/extplugins/#/app/extplugins/#g' \
    -e 's#(^[[:space:]]*external_plugins_dir[[:space:]]*:[[:space:]]*).*$#\1/app/extplugins#' \
    -e 's#(^[[:space:]]*[A-Za-z0-9_]+:[[:space:]]*)extplugins/#\1/app/extplugins/#' \
    "$ini"
}

if [ ! -f "$OUT_INI" ]; then
  echo "[b3-init] No b3.ini detected; creating from template…"
  cp "$TEMPLATE" "$OUT_INI"
  sync_b3_ini "$OUT_INI"
  echo "==== Using b3.ini (key lines) ===="
  egrep -n '^\[b3\]$|^\[server\]$|^(parser|database|bot_name|bot_prefix|game_log|rcon_ip|port|rcon_password|punkbuster)\s*:' "$OUT_INI" || true
  echo "==== Plugin path samples =========="
  egrep -n '^\[plugins\]$|^[[:space:]]*[A-Za-z0-9_]+:[[:space:]]*/app/(conf|extplugins)/|^[[:space:]]*external_plugins_dir[[:space:]]*:' "$OUT_INI" || true
  echo "=================================="
else
  echo "[b3-init] Found existing /app/conf/b3.ini; syncing keys to current env…"
  if [ ! -f "${OUT_INI}.orig" ]; then
    cp "$OUT_INI" "${OUT_INI}.orig"
  fi
  sync_b3_ini "$OUT_INI"
fi

LOG_TARGET="/app/logs/b3.log"
B3_INI="/app/conf/b3.ini"

mkdir -p "$(dirname "$LOG_TARGET")"
touch "$LOG_TARGET"

if [ -f "$B3_INI" ]; then
  awk -v target="$LOG_TARGET" '
    BEGIN { in_b3=0; found=0 }
    /^\s*\[/ {
      if (in_b3 && !found) print "logfile: " target
      in_b3 = ($0 ~ /^\s*\[b3\]\s*$/)
      found = 0
      print; next
    }
    {
      if (in_b3) {
        if ($0 ~ /^\s*#?\s*logfile\s*[:=]/) { print "logfile: " target; found=1 }
        else { print }
      } else { print }
    }
    END {
      if (in_b3 && !found) print "logfile: " target
    }
  ' "$B3_INI" > "${B3_INI}.tmp" && mv "${B3_INI}.tmp" "$B3_INI"
  echo "[b3-init] Patched b3.ini to use logfile = $LOG_TARGET"
else
  echo "[b3-init] WARNING: $B3_INI not found; cannot patch logfile path" >&2
fi

# --- Copy *.ini and *.xml into /app/conf if missing --------------------------
for SRC in /opt/b3/b3/conf; do
  if [ -d "$SRC" ]; then
    while IFS= read -r -d '' f; do
      base="$(basename "$f")"
      if [ "$base" = "b3.ini" ]; then continue; fi
      dst="/app/conf/$base"
      if [ ! -e "$dst" ]; then
        echo "[b3-init] Adding $(printf '%q' "$base") to /app/conf"
        cp "$f" "$dst"
        sed -i 's/\r$//' "$dst" || true
      else
        echo "[b3-init] Skipping existing $(printf '%q' "$base")"
      fi
    done < <(find "$SRC" -maxdepth 1 -type f \( -iname '*.ini' -o -iname '*.xml' \) -print0)
  fi
done

# --- Schema bootstrap + migrations -------------------------------------------
SQL_BASE="/opt/b3/b3/sql/mysql"
SQL_UPDATES_DIR="/opt/b3/b3/sql/mysql/updates"
BASE_SQL="${SQL_BASE}/b3.sql"

echo "[b3-init] Ensuring B3 schema exists and applying migrations …"
have_clients=$(mysql -h "$DB_HOST" -u"${DB_USER}" -p"${DB_PASS}" -N -e "SHOW TABLES LIKE 'clients';" "${DB_NAME}" | wc -l || true)
if [ "$have_clients" -eq 0 ]; then
  echo "[b3-init] Importing base schema: $BASE_SQL"
  mysql -h "$DB_HOST" -u"${DB_USER}" -p"${DB_PASS}" "${DB_NAME}" < "$BASE_SQL"
fi

mysql -h "$DB_HOST" -u"${DB_USER}" -p"${DB_PASS}" "${DB_NAME}" -e \
"CREATE TABLE IF NOT EXISTS schema_version (
  version VARCHAR(16) NOT NULL PRIMARY KEY,
  applied_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=MyISAM DEFAULT CHARSET=utf8;"

CURR_VER=$(mysql -h "$DB_HOST" -u"${DB_USER}" -p"${DB_PASS}" -N -e "SELECT COALESCE(MAX(version),'0') FROM schema_version;" "${DB_NAME}" | tr -d '
')

echo "[b3-init] Current DB version: ${CURR_VER}"

if [ -d "$SQL_UPDATES_DIR" ]; then
  echo "[b3-init] Looking for updates in ${SQL_UPDATES_DIR} …"
  shopt -s nullglob
  mapfile -t files < <(ls -1 "${SQL_UPDATES_DIR}/"*.sql 2>/dev/null | sort)
  for f in "${files[@]}"; do
    base="$(basename "$f" .sql)"
    if [[ "$base" > "$CURR_VER" ]]; then
      echo "[b3-init] Applying update $base from $f …"
      mysql -h "$DB_HOST" -u"${DB_USER}" -p"${DB_PASS}" "${DB_NAME}" < "$f"
      mysql -h "$DB_HOST" -u"${DB_USER}" -p"${DB_PASS}" "${DB_NAME}" -e "INSERT IGNORE INTO schema_version(version) VALUES ('$base');"
    fi
  done
else
  echo "[b3-init] No updates dir found at ${SQL_UPDATES_DIR}; skipping migrations."
fi

exec python /opt/b3/b3_run.py -c "$OUT_INI"
