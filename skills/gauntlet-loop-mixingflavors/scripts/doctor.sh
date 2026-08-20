#!/usr/bin/env bash
# Preflight check for gauntlet-loop-mixingflavors.
set -euo pipefail

SKILL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${SKILL_ROOT}/assets/config.yaml"

get_cfg () { yq -r ".$1" "$CONFIG"; }

GODOT_BIN="$(get_cfg godot_binary)"
echo "[doctor] Checking for Godot binary ('$GODOT_BIN')..."
if ! command -v "$GODOT_BIN" >/dev/null 2>&1; then
  echo "[doctor] '$GODOT_BIN' not found on PATH."
  echo "[doctor]   Install Godot 4.x and ensure the CLI binary is on PATH,"
  echo "[doctor]   or set godot_binary in assets/config.yaml to the right name."
  exit 1
fi
"$GODOT_BIN" --version

echo "[doctor] Checking for node/npm (Playwright is a project dependency)..."
command -v node >/dev/null 2>&1 || { echo "[doctor] node not found."; exit 1; }
command -v npm  >/dev/null 2>&1 || { echo "[doctor] npm not found."; exit 1; }

echo "[doctor] Checking Playwright is installed in this repo..."
if [[ ! -d "node_modules/playwright" && ! -d "node_modules/@playwright" ]]; then
  echo "[doctor] Playwright not found in node_modules — run 'npm install' first."
  exit 1
fi

echo "[doctor] Checking for yq (yaml parsing used throughout this skill)..."
command -v yq >/dev/null 2>&1 || { echo "[doctor] yq not found — install it."; exit 1; }

echo "[doctor] Environment OK."
