#!/usr/bin/env sh
set -eu

APP_DIR="/opt/xlrbot"
SRC_DIR="$APP_DIR/src"
REPO="https://github.com/kmstrube81/xlr-discord-bot.git"
REF="main"

echo "[boot] repo=$REPO ref=$REF app_dir=$APP_DIR"

mkdir -p "$SRC_DIR"

if [ ! -d "$SRC_DIR/.git" ]; then
  echo "[git] fresh clone..."
  git clone --depth 1 --branch "$REF" "$REPO" "$SRC_DIR"
else
  echo "[git] update existing clone..."
  git -C "$SRC_DIR" fetch origin --depth 1
  # try branch ref first, fallback to tag/commit if not a branch
  git -C "$SRC_DIR" checkout "$REF" || true
  git -C "$SRC_DIR" reset --hard "origin/$REF" || git -C "$SRC_DIR" reset --hard "$REF"
fi

cd "$SRC_DIR"

chmod +x bin/magick

# Install dependencies (respect lockfile if present)
if [ -f package-lock.json ]; then
  echo "[npm] ci (prod only)"
  npm ci --omit=dev
else
  echo "[npm] install (prod only)"
  npm i --omit=dev --no-audit --no-fund
fi

# Ensure config dir + file exist
mkdir -p /opt/xlrbot/cfg
[ -f /opt/xlrbot/cfg/.env ] || touch /opt/xlrbot/cfg/.env

# Re-point the app's expected .env to the mounted file
# (remove any real file to avoid "File exists" error; then symlink)
rm -f /opt/xlrbot/src/.env
ln -s /opt/xlrbot/cfg/.env /opt/xlrbot/src/.env


node src/index.js --register || echo "[register] warn: failed; continuing"

echo "[run] starting bot..."
exec node src/index.js
