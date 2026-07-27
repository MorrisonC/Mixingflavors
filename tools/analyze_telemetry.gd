extends SceneTree

var telemetry_file_path = "user://telemetry_output.json"
var roadmap_file_path = "res://BALANCE_ROADMAP.md"

# Thresholds for GameFlow & MDA
var high_friction_stuck_threshold = 3.0
var low_friction_apm_threshold = 10.0 # very low APM means boring/disengaged
var dead_mechanic_threshold = 0.1 # <10% utilization

func _init():
    print("[TelemetryAnalyzer] Starting analysis...")
    analyze_and_patch()
    quit(0)

func analyze_and_patch():
    var file = FileAccess.open(telemetry_file_path, FileAccess.READ)
    if not file:
        print("[TelemetryAnalyzer] Error: Could not find telemetry file at ", telemetry_file_path)
        return

    var json_text = file.get_as_text()
    file.close()

    var json = JSON.new()
    var error = json.parse(json_text)
    if error != OK:
        print("[TelemetryAnalyzer] JSON Parse Error: ", json.get_error_message())
        return

    var data = json.get_data()

    var adjustments_needed = []
    var roadmap_findings = []

    # Process each level
    for level_data in data.get("levels", []):
        var level_id = level_data.get("level_id", "Unknown")
        print("[TelemetryAnalyzer] Analyzing Level: ", level_id)

        var level_findings = {
            "id": level_id,
            "issues": [],
            "apm": level_data.get("apm", 0.0),
            "ttc": level_data.get("time_to_complete", 0.0)
        }

        # 1. GameFlow Framework: Challenge vs Skill (Stuck Zones & Pacing)
        var stuck_zones = level_data.get("stuck_zones", [])
        if stuck_zones.size() > 2:
            var issue_msg = "HIGH FRICTION detected. Bot was stuck >2 times. Needs difficulty reduction."
            print("  - [GameFlow] ", issue_msg)
            adjustments_needed.append({"type": "decrease_difficulty", "mode": level_id})
            level_findings.issues.append(issue_msg)

        var apm = level_data.get("apm", 0.0)
        if apm > 0.0 and apm < low_friction_apm_threshold and level_data.get("time_to_complete", 0.0) > 0.0:
            var issue_msg = "LOW FRICTION / BORING detected. Very low APM (%f). Needs difficulty increase." % apm
            print("  - [GameFlow] ", issue_msg)
            adjustments_needed.append({"type": "increase_difficulty", "mode": level_id})
            level_findings.issues.append(issue_msg)

        # 2. MDA Framework: Mechanic usage
        var verb_counts = level_data.get("verb_counts", {})
        var total_actions = level_data.get("actions", []).size()

        if total_actions > 0:
            for verb in verb_counts.keys():
                var utilization = float(verb_counts[verb]) / float(total_actions)
                if utilization < dead_mechanic_threshold:
                    var issue_msg = "DEAD MECHANIC detected. '%s' utilized only %.2f%%" % [verb, utilization * 100]
                    print("  - [MDA] ", issue_msg)
                    level_findings.issues.append(issue_msg)

        roadmap_findings.append(level_findings)

    # Update roadmap file
    update_roadmap(roadmap_findings)

    # Apply patches if necessary
    if adjustments_needed.size() > 0:
        apply_patches(adjustments_needed)
    else:
        print("[TelemetryAnalyzer] No patches required. Game is balanced.")

func update_roadmap(findings: Array):
    var date_string = Time.get_date_string_from_system()
    var time_string = Time.get_time_string_from_system()

    var content = "# Automated Game Balance Roadmap\n\n"
    content += "This document tracks the incremental balance improvements recommended by the headless telemetry system.\n\n"

    content += "## Instructions for Agents\n"
    content += "To run the automated flow and generate a new report, an agent should:\n"
    content += "1. Run the headless telemetry runner: `godot --headless --script res://tools/telemetry_runner.gd`\n"
    content += "2. Run the telemetry analyzer which patches files and updates this roadmap: `godot --headless --script res://tools/analyze_telemetry.gd`\n"
    content += "3. Review the changes in `BALANCE_ROADMAP.md` and the automatically patched `.gd` files.\n"
    content += "4. Use `git diff` to verify the automated parameter adjustments.\n"
    content += "5. Commit the changes and open a pull request for the design team to review.\n\n"

    content += "## Telemetry Run Analytics: " + date_string + " " + time_string + "\n\n"

    var issues_found = false

    for f in findings:
        content += "### " + f.id + "\n"
        content += "- **Time To Complete (TTC)**: %.2f seconds\n" % f.ttc
        content += "- **Actions Per Minute (APM)**: %.2f\n" % f.apm

        if f.issues.size() > 0:
            issues_found = true
            content += "- **Findings & Required Actions**:\n"
            for issue in f.issues:
                content += "  - [ ] " + issue + "\n"
        else:
            content += "- **Status**: Balanced. No immediate actions required.\n"
        content += "\n"

    # Prepend to existing roadmap or create new
    var existing_content = ""
    if FileAccess.file_exists(roadmap_file_path):
        var read_file = FileAccess.open(roadmap_file_path, FileAccess.READ)
        if read_file:
            existing_content = read_file.get_as_text()
            read_file.close()

            # Remove the old header so we just keep the history
            var header_end = existing_content.find("## Telemetry Run Analytics:")
            if header_end != -1:
                existing_content = existing_content.substr(header_end)
            else:
                existing_content = "\n" + existing_content

    var write_file = FileAccess.open(roadmap_file_path, FileAccess.WRITE)
    if write_file:
        write_file.store_string(content + "---\n\n### Historical Reports\n\n" + existing_content)
        write_file.close()
        print("[TelemetryAnalyzer] Generated and updated BALANCE_ROADMAP.md")
    else:
        print("[TelemetryAnalyzer] Failed to write BALANCE_ROADMAP.md")

func apply_patches(adjustments: Array):
    print("[TelemetryAnalyzer] Applying physical patches to project files...")

    # We will dynamically adjust GameManager.gd default RPG stats or VoxelGrid3D sizes
    # For this example, we parse and modify GameManager.gd

    var gm_path = "res://scripts/GameManager.gd"
    var gm_file = FileAccess.open(gm_path, FileAccess.READ)
    if gm_file:
        var content = gm_file.get_as_text()
        gm_file.close()

        var modified = false
        for adj in adjustments:
            if adj.type == "decrease_difficulty":
                if "Picross3D" in adj.mode:
                    content = content.replace("var alchemy_discipline: int = 1", "var alchemy_discipline: int = 2")
                    modified = true
                elif "MasqueradePainting" in adj.mode:
                    content = content.replace("var perception_level: int = 1", "var perception_level: int = 2")
                    modified = true

            elif adj.type == "increase_difficulty":
                if "Picross3D" in adj.mode:
                    content = content.replace("var health: int = 100", "var health: int = 50")
                    modified = true

        if modified:
            var write_file = FileAccess.open(gm_path, FileAccess.WRITE)
            write_file.store_string(content)
            write_file.close()
            print("[TelemetryAnalyzer] Patched ", gm_path, " to adjust difficulty parameters.")

    var vg_path = "res://scripts/VoxelGrid3D.gd"
    var vg_file = FileAccess.open(vg_path, FileAccess.READ)
    if vg_file:
        var content = vg_file.get_as_text()
        vg_file.close()

        var modified = false
        for adj in adjustments:
            if adj.type == "decrease_difficulty" and "Picross3D" in adj.mode:
                content = content.replace("@export var GridSizeX: int = 5", "@export var GridSizeX: int = 4")
                content = content.replace("@export var GridSizeY: int = 5", "@export var GridSizeY: int = 4")
                content = content.replace("@export var GridSizeZ: int = 5", "@export var GridSizeZ: int = 4")
                modified = true

        if modified:
            var write_file = FileAccess.open(vg_path, FileAccess.WRITE)
            write_file.store_string(content)
            write_file.close()
            print("[TelemetryAnalyzer] Patched ", vg_path, " to adjust puzzle grid size.")
