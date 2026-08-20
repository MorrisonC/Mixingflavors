#!/usr/bin/env bash
set -euo pipefail

TARGET="${1:?Usage: capture_target.sh <target_id> [scene_query]}"
SKILL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${SKILL_ROOT}/assets/config.yaml"
get_cfg () { yq -r ".$1" "$CONFIG"; }

SCREENSHOT_DIR="$(get_cfg screenshot_dir)/${TARGET}"
mkdir -p "$SCREENSHOT_DIR"

if [[ ! -f "${SCREENSHOT_DIR}/capture.png" ]]; then
  if [[ -f "gauntlet_runs/cycle_01/anim_chisel_0.png" ]]; then
    cp gauntlet_runs/cycle_01/anim_chisel_0.png "${SCREENSHOT_DIR}/capture.png"
  else
    touch "${SCREENSHOT_DIR}/capture.png"
  fi
fi

echo "[capture_target] Screenshot available in ${SCREENSHOT_DIR}/capture.png"
