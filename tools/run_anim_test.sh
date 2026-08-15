#!/bin/bash
set -e

# Start game process with xvfb in background
xvfb-run -a ~/.local/bin/godot --rendering-driver opengl3 > godot.log 2>&1 &
GODOT_PID=$!

# Wait a bit for it to start
sleep 2

# Run python driver
python3 tools/gauntlet_driver.py

# Kill game process
kill $GODOT_PID
