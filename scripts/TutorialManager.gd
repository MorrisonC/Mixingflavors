extends Node
class_name TutorialManager

signal step_advanced(step_index: int, instruction: String)
signal tutorial_completed()
signal hint_pulsed(pos: Vector3i)

enum Step {
	CAMERA_ORBIT,
	CLUE_ZERO_CHISEL,
	MARKING_FULL_ROW,
	LAYER_SLICING,
	DEDUCTION_SOLVE,
	VICTORY
}

var current_step: Step = Step.CAMERA_ORBIT
var orbit_accumulated_angle: float = 0.0
var wrong_action_count: int = 0

var step_instructions: Dictionary = {
	Step.CAMERA_ORBIT: "Drag across the screen to rotate around the 3D cube.",
	Step.CLUE_ZERO_CHISEL: "A '0' clue means ALL blocks in that line are empty. Chisel them away!",
	Step.MARKING_FULL_ROW: "A '3' clue means ALL blocks stay! Switch to Mark mode and flag them.",
	Step.LAYER_SLICING: "Internal blocks are hidden! Drag the Layer Slicer slider to cut into the cube.",
	Step.DEDUCTION_SOLVE: "Combine slicing, marking, and chiseling to solve the remaining blocks!",
	Step.VICTORY: "Sculpture Revealed! You've mastered 3D Picross!"
}

@export var hud_banner_label: Label
@export var tool_highlight_rect: ColorRect
@export var slicer_slider_highlight: ColorRect

var grid_manager: Node

func _ready() -> void:
	_start_step(Step.CAMERA_ORBIT)

func _start_step(new_step: Step) -> void:
	current_step = new_step
	wrong_action_count = 0
	var instruction = step_instructions.get(current_step, "")
	if hud_banner_label:
		hud_banner_label.text = instruction
	step_advanced.emit(int(current_step), instruction)

	_update_ui_highlights()

func _update_ui_highlights() -> void:
	if tool_highlight_rect:
		tool_highlight_rect.visible = (current_step == Step.MARKING_FULL_ROW)
	if slicer_slider_highlight:
		slicer_slider_highlight.visible = (current_step == Step.LAYER_SLICING)

func on_camera_rotated(delta_angle: float) -> void:
	if current_step == Step.CAMERA_ORBIT:
		orbit_accumulated_angle += abs(delta_angle)
		if orbit_accumulated_angle >= deg_to_rad(45.0):
			if OS.has_feature("mobile"):
				Input.vibrate_handheld(40)
			_start_step(Step.CLUE_ZERO_CHISEL)

func on_voxel_chiseled(grid_pos: Vector3i, is_correct: bool) -> void:
	if not is_correct:
		wrong_action_count += 1
		if wrong_action_count >= 3:
			_trigger_contextual_hint()

	if current_step == Step.CLUE_ZERO_CHISEL:
		if _is_zero_row_cleared():
			if OS.has_feature("mobile"):
				Input.vibrate_handheld(40)
			_start_step(Step.MARKING_FULL_ROW)
	elif current_step == Step.DEDUCTION_SOLVE:
		_check_puzzle_completion()

func on_voxel_marked(grid_pos: Vector3i) -> void:
	if current_step == Step.MARKING_FULL_ROW:
		if _is_full_row_marked():
			if OS.has_feature("mobile"):
				Input.vibrate_handheld(40)
			_start_step(Step.LAYER_SLICING)
	elif current_step == Step.DEDUCTION_SOLVE:
		_check_puzzle_completion()

func on_layer_slider_changed(axis: String, value: int) -> void:
	if current_step == Step.LAYER_SLICING:
		if OS.has_feature("mobile"):
			Input.vibrate_handheld(40)
		_start_step(Step.DEDUCTION_SOLVE)

func on_puzzle_solved() -> void:
	if current_step != Step.VICTORY:
		if OS.has_feature("mobile"):
			Input.vibrate_handheld(40)
		_start_step(Step.VICTORY)
		tutorial_completed.emit()

		# Save state
		var game_manager = get_node_or_null("/root/GameManager")
		if is_instance_valid(game_manager):
			game_manager.tutorial_completed = true
			if game_manager.has_method("save_settings"):
				game_manager.save_settings()

func _trigger_contextual_hint() -> void:
	match current_step:
		Step.CLUE_ZERO_CHISEL:
			if hud_banner_label:
				hud_banner_label.text = "HINT: Look for the '0' clue on the bottom row and tap those blocks to chisel them!"
		Step.MARKING_FULL_ROW:
			if hud_banner_label:
				hud_banner_label.text = "HINT: Tap the 'Mark' button at the bottom, then tap each block in the row with clue '3'!"
		Step.LAYER_SLICING:
			if hud_banner_label:
				hud_banner_label.text = "HINT: Move the 'Slice Y' slider to reveal internal hidden blocks!"
		Step.DEDUCTION_SOLVE:
			if hud_banner_label:
				hud_banner_label.text = "HINT: Check intersecting clues to find blocks that must be empty!"

func _is_zero_row_cleared() -> bool:
	if not grid_manager: return false

	# '0' rows based on clues are at z=0 and z=2 for y=0
	var pos1 = Vector3i(0, 0, 0)
	var pos2 = Vector3i(1, 0, 0)
	var pos3 = Vector3i(2, 0, 0)

	var all_cleared = true
	for pos in [pos1, pos2, pos3]:
		if grid_manager.blocks.has(pos):
			var block = grid_manager.blocks[pos]
			if block.current_state != block.BlockState.DESTROYED:
				all_cleared = false
				break

	if all_cleared: return true

	var pos4 = Vector3i(0, 0, 2)
	var pos5 = Vector3i(1, 0, 2)
	var pos6 = Vector3i(2, 0, 2)

	all_cleared = true
	for pos in [pos4, pos5, pos6]:
		if grid_manager.blocks.has(pos):
			var block = grid_manager.blocks[pos]
			if block.current_state != block.BlockState.DESTROYED:
				all_cleared = false
				break

	return all_cleared

func _is_full_row_marked() -> bool:
	if not grid_manager: return false

	# Middle row has 3
	var pos1 = Vector3i(0, 1, 1)
	var pos2 = Vector3i(1, 1, 1)
	var pos3 = Vector3i(2, 1, 1)

	var all_marked = true
	for pos in [pos1, pos2, pos3]:
		if grid_manager.blocks.has(pos):
			var block = grid_manager.blocks[pos]
			if block.current_state != block.BlockState.MARKED:
				all_marked = false
				break

	return all_marked

func _check_puzzle_completion() -> void:
	if not grid_manager: return

	var non_target_remaining = 0

	for pos in grid_manager.voxel_states.keys():
		if not grid_manager.is_target_cell(pos) and not grid_manager.is_cell_chiseled(pos):
			non_target_remaining += 1

	if non_target_remaining == 0:
		on_puzzle_solved()
