#!/usr/bin/env bash
# Runs Shadow Slave Colony. Downloads Godot 4.3 (about 50 MB) next to the game the first time.
set -e
cd "$(dirname "$0")"
GODOT_VER="4.3-stable"
BIN=".engine/Godot_v${GODOT_VER}_linux.x86_64"
if command -v godot4 >/dev/null 2>&1 && godot4 --version 2>/dev/null | grep -q "^4\.3"; then
  BIN="$(command -v godot4)"
elif [ ! -x "$BIN" ]; then
  echo "Downloading Godot ${GODOT_VER}..."
  mkdir -p .engine
  curl -L -o .engine/godot.zip "https://github.com/godotengine/godot/releases/download/${GODOT_VER}/Godot_v${GODOT_VER}_linux.x86_64.zip"
  (cd .engine && unzip -o godot.zip && rm godot.zip)
  chmod +x "$BIN"
fi
exec "$BIN" --path . "$@"
