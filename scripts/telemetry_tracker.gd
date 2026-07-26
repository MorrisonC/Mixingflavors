class_name TelemetryTracker
extends Node

var session_start_time: float
var level_start_time: float
var current_level_id: String

# Telemetry data structures
var session_data: Dictionary = {
    "levels": []
}
var current_level_data: Dictionary

# Sampling interval
var sample_interval: float = 1.0
var time_since_last_sample: float = 0.0

func _ready():
    session_start_time = Time.get_unix_time_from_system()

func start_level(level_id: String):
    current_level_id = level_id
    level_start_time = Time.get_unix_time_from_system()
    current_level_data = {
        "level_id": level_id,
        "start_time": level_start_time,
        "end_time": 0.0,
        "time_to_complete": 0.0,
        "actions": [],
        "heatmaps": [],
        "stuck_zones": [],
        "verb_counts": {},
        "pacing_velocity": []
    }

func log_action(verb: String, details: Dictionary = {}):
    if current_level_data.is_empty():
        return

    var timestamp = Time.get_unix_time_from_system()
    current_level_data["actions"].append({
        "timestamp": timestamp,
        "verb": verb,
        "details": details
    })

    if current_level_data["verb_counts"].has(verb):
        current_level_data["verb_counts"][verb] += 1
    else:
        current_level_data["verb_counts"][verb] = 1

func log_position(grid_coords: Vector3, system: String):
    if current_level_data.is_empty():
        return

    current_level_data["heatmaps"].append({
        "timestamp": Time.get_unix_time_from_system(),
        "coords": {"x": grid_coords.x, "y": grid_coords.y, "z": grid_coords.z},
        "system": system
    })

func log_stuck_zone(grid_coords: Vector3, duration: float, system: String):
    if current_level_data.is_empty():
        return

    current_level_data["stuck_zones"].append({
        "coords": {"x": grid_coords.x, "y": grid_coords.y, "z": grid_coords.z},
        "duration": duration,
        "system": system
    })

func log_pacing_velocity(quadrant_id: String, time_spent: float):
    if current_level_data.is_empty():
        return

    current_level_data["pacing_velocity"].append({
        "quadrant_id": quadrant_id,
        "time_spent": time_spent
    })

func end_level():
    if current_level_data.is_empty():
        return

    var end_time = Time.get_unix_time_from_system()
    current_level_data["end_time"] = end_time
    current_level_data["time_to_complete"] = end_time - level_start_time

    # Calculate Action Density (Actions Per Minute)
    var total_actions = current_level_data["actions"].size()
    var minutes = current_level_data["time_to_complete"] / 60.0
    current_level_data["apm"] = total_actions / max(minutes, 0.01)

    session_data["levels"].append(current_level_data)
    current_level_data = {}

func save_telemetry():
    var file = FileAccess.open("user://telemetry_output.json", FileAccess.WRITE)
    if file:
        file.store_string(JSON.stringify(session_data, "\t"))
        file.close()
        print("Saved telemetry to user://telemetry_output.json")
    else:
        print("Failed to save telemetry")
