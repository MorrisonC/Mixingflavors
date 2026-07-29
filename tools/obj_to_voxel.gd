extends SceneTree

# Simple voxelizer script for converting an .obj file to a Picross 3D JSON puzzle
# Intended for internal use by devs to generate puzzles.

const OBJ_PATH = "res://assets/models/heart.obj" # Example input path
const OUT_PATH = "user://valentine_puzzle.json"
const VOXEL_GRID_SIZE = Vector3i(10, 10, 10)

func _init():
	print("Starting OBJ to Voxel conversion...")

	if not FileAccess.file_exists(OBJ_PATH):
		print("Error: OBJ file not found at " + OBJ_PATH)
		quit()
		return

	# Parse .obj file
	var file = FileAccess.open(OBJ_PATH, FileAccess.READ)
	var vertices = []
	var faces = []
	var min_bound = Vector3(INF, INF, INF)
	var max_bound = Vector3(-INF, -INF, -INF)

	while not file.eof_reached():
		var line = file.get_line().strip_edges()
		if line.begins_with("v "):
			var parts = line.split(" ", false)
			if parts.size() >= 4:
				var v = Vector3(parts[1].to_float(), parts[2].to_float(), parts[3].to_float())
				vertices.append(v)
				min_bound = min_bound.min(v)
				max_bound = max_bound.max(v)
		elif line.begins_with("f "):
			# Optional: We could do point-in-triangle tests, but for a simple
			# bounding box voxelizer, just checking points near vertices/edges is a start.
			pass

	file.close()

	if vertices.is_empty():
		print("No vertices found in OBJ.")
		quit()
		return

	var extents = max_bound - min_bound
	var max_extent = max(extents.x, max(extents.y, extents.z))
	if max_extent == 0: max_extent = 1.0 # prevent div by zero

	var puzzle_data = {
		"dims": [VOXEL_GRID_SIZE.x, VOXEL_GRID_SIZE.y, VOXEL_GRID_SIZE.z],
		"cells": []
	}

	# Very basic point-cloud voxelizer based on vertex proximity
	# This maps the OBJ bounds to the voxel grid and marks voxels that contain or are very close to a vertex.
	var voxel_size = max_extent / float(VOXEL_GRID_SIZE.x)
	var threshold = voxel_size * 1.5 # distance threshold to consider a voxel 'filled'

	for z in range(VOXEL_GRID_SIZE.z):
		for y in range(VOXEL_GRID_SIZE.y):
			for x in range(VOXEL_GRID_SIZE.x):
				var pos = Vector3(x, y, z)
				# Map voxel pos to world space of OBJ
				var world_pos = min_bound + (pos / Vector3(VOXEL_GRID_SIZE)) * max_extent

				var state = 0
				for v in vertices:
					if world_pos.distance_to(v) < threshold:
						state = 1
						break

				puzzle_data["cells"].append(state)

	var json_string = JSON.stringify(puzzle_data)

	var out_file = FileAccess.open(OUT_PATH, FileAccess.WRITE)
	if out_file:
		out_file.store_string(json_string)
		out_file.close()
		print("Voxelization complete. Saved to " + OUT_PATH)
	else:
		print("Failed to save output JSON.")

	quit()
