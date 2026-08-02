# Godot Engine Project Context for Jules

## Engine & Setup
- Engine Version: Godot 4.x
- Primary Language: GDScript
- Test Framework: GUT (Godot Unit Testing) / GdUnit4

## How to Run Automated Tests
Jules MUST run tests in headless mode inside the VM:
`godot --headless --rendering-driver opengl3 -s addons/gut/gut_cmdln.gd -gdir=res://test/unit/ -gexit`

## Architecture & Conventions
- Always follow official GDScript style guidelines.
- Keep signals decoupled; avoid hardcoded node paths across scenes.
- Every new gameplay feature or bug fix MUST include a corresponding test script in `res://test/unit/`.
- Do not make changes if the automated test suite fails.
