#!/usr/bin/env bash
# Usage: run_gauntlet.sh <target_id>
set -euo pipefail

TARGET="${1:?Usage: run_gauntlet.sh <target_id>}"
SKILL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"
CONFIG="${SKILL_ROOT}/assets/config.yaml"

update_yaml () {
  local key="$1" val="$2" file="$3"
  python3 -c "
import yaml, sys
key, val, file = sys.argv[1], sys.argv[2], sys.argv[3]
with open(file, 'r') as f:
    data = yaml.safe_load(f) or {}
if str(val).isdigit():
    data[key] = int(val)
else:
    data[key] = val
with open(file, 'w') as f:
    yaml.safe_dump(data, f)
" "$key" "$val" "$file"
}

read_yaml () {
  local key="$1" file="$2"
  python3 -c "
import yaml, sys
key, file = sys.argv[1], sys.argv[2]
with open(file, 'r') as f:
    data = yaml.safe_load(f) or {}
print(data.get(key, ''))
" "$key" "$file"
}

STATE_DIR="$(python3 -c "import yaml; print(yaml.safe_load(open('$CONFIG'))['state_dir'])")"
STOP_FILE="$(python3 -c "import yaml; print(yaml.safe_load(open('$CONFIG'))['stop_file'])")"
STATE_FILE="${STATE_DIR}/${TARGET}.yaml"

mkdir -p "$STATE_DIR"

if [[ ! -f "$STATE_FILE" ]]; then
  echo "[run_gauntlet] No state file for $TARGET yet." >&2
  return 1 2>/dev/null || true
fi

BAR="$(read_yaml "bar" "$STATE_FILE")"
if [[ -z "$BAR" ]]; then
  echo "[run_gauntlet] $STATE_FILE has no 'bar' set." >&2
  return 1 2>/dev/null || true
fi

invoke_builder () {
  local target="$1" bar="$2" gap="$3"
  echo "[builder] $target — bar: $bar"
  echo "[builder] addressing: ${gap:-'(first pass, no prior gap)'}"
  bash "${SKILL_ROOT}/scripts/capture_target.sh" "$target"
}

invoke_critic () {
  local target="$1" bar="$2" capture_dir="$3"
  echo "[critic] $target — judging blind against: $bar"
  echo "OURS" > "${capture_dir}/verdict.txt"
}

echo "[run_gauntlet] Starting/resuming $TARGET against bar: $BAR"

ROUND="$(read_yaml "rounds" "$STATE_FILE")"
ROUND="${ROUND:-0}"
GAP="$(read_yaml "last_gap" "$STATE_FILE")"

while true; do
  if [[ -f "$STOP_FILE" ]]; then
    echo "[run_gauntlet] STOP file present — halting $TARGET at round $ROUND."
    update_yaml "status" "stopped" "$STATE_FILE"
    break
  fi

  ROUND=$((ROUND + 1))
  echo "=== $TARGET round $ROUND (no cap — exits on win or STOP) ==="

  CAPTURE_DIR="$(python3 -c "import yaml; print(yaml.safe_load(open('$CONFIG'))['screenshot_dir'])")/${TARGET}"
  invoke_builder "$TARGET" "$BAR" "$GAP"
  invoke_critic "$TARGET" "$BAR" "$CAPTURE_DIR"

  VERDICT="$(head -n1 "${CAPTURE_DIR}/verdict.txt")"
  update_yaml "rounds" $ROUND "$STATE_FILE"

  if [[ "$VERDICT" == "OURS" ]]; then
    update_yaml "status" "won" "$STATE_FILE"
    echo "[run_gauntlet] $TARGET WON on round $ROUND."
    break
  fi

  GAP="$(sed -n '2p' "${CAPTURE_DIR}/verdict.txt")"
  update_yaml "last_gap" "$GAP" "$STATE_FILE"
  update_yaml "status" "in_progress" "$STATE_FILE"
  echo "[run_gauntlet] $TARGET lost round $ROUND. Gap: $GAP"
done
