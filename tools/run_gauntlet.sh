#!/bin/bash
set -e

CYCLE_DIR=${CYCLE_DIR:-cycle_00}
export CYCLE_DIR=$CYCLE_DIR

# Add GauntletBridge autoload
grep -q "GauntletBridge" project.godot || sed -i '$ a GauntletBridge="*res://scripts/GauntletBridge.gd"' project.godot

# Start game process with xvfb in background
xvfb-run -a ~/.local/bin/godot --rendering-driver opengl3 > godot.log 2>&1 &
GODOT_PID=$!

# Wait a bit for it to start
sleep 5

# Run python driver
python3 tools/gauntlet_driver.py

# Kill game process
kill $GODOT_PID

# Remove GauntletBridge autoload
git checkout project.godot
