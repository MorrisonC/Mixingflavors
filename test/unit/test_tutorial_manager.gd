extends GutTest

const TutorialManagerClass = preload("res://scripts/TutorialManager.gd")
const GridManagerClass = preload("res://scripts/GridManager.gd")

var tutorial: TutorialManagerClass
var grid: GridManagerClass

func before_each():
	tutorial = TutorialManagerClass.new()
	add_child_autoqfree(tutorial)

	grid = GridManagerClass.new()
	grid.grid_size = Vector3i(3, 3, 3)
	add_child_autoqfree(grid)

	tutorial.grid_manager = grid

	# Initialize 3x3x3 voxel states with target Star voxels
	var target_voxels = [
		Vector3i(1, 0, 1),
		Vector3i(0, 1, 1), Vector3i(1, 1, 1), Vector3i(2, 1, 1),
		Vector3i(1, 1, 0), Vector3i(1, 1, 2),
		Vector3i(1, 2, 1)
	]
	grid.target_solution.clear()
	for z in range(3):
		for y in range(3):
			for x in range(3):
				var pos = Vector3i(x, y, z)
				var is_target = pos in target_voxels
				grid.target_solution[pos] = is_target
				grid.voxel_states[pos] = {
					"cell_state": GridManagerClass.CellState.UNBROKEN,
					"is_painted": false,
					"is_hidden_by_slice": false
				}

func test_initial_step_is_camera_orbit():
	assert_eq(tutorial.current_step, TutorialManagerClass.Step.CAMERA_ORBIT, "Tutorial should start on CAMERA_ORBIT step")

func test_camera_orbit_advances_to_zero_chisel():
	tutorial.on_camera_rotated(deg_to_rad(50.0))
	assert_eq(tutorial.current_step, TutorialManagerClass.Step.CLUE_ZERO_CHISEL, "Rotating camera >= 45 deg should advance to CLUE_ZERO_CHISEL step")

func test_contextual_hint_triggers_on_wrong_actions():
	tutorial._start_step(TutorialManagerClass.Step.CLUE_ZERO_CHISEL)
	tutorial.on_voxel_chiseled(Vector3i(1, 1, 1), false)
	tutorial.on_voxel_chiseled(Vector3i(1, 1, 1), false)
	tutorial.on_voxel_chiseled(Vector3i(1, 1, 1), false)

	assert_eq(tutorial.wrong_action_count, 3, "Wrong action count should equal 3")

func test_layer_slider_advances_step():
	tutorial._start_step(TutorialManagerClass.Step.LAYER_SLICING)
	tutorial.on_layer_slider_changed("Y", 1)
	assert_eq(tutorial.current_step, TutorialManagerClass.Step.DEDUCTION_SOLVE, "Slicing layer slider should advance to DEDUCTION_SOLVE step")

func test_puzzle_solved_advances_to_victory():
	tutorial.on_puzzle_solved()
	assert_eq(tutorial.current_step, TutorialManagerClass.Step.VICTORY, "Puzzle solved signal should advance step to VICTORY")

func test_chiseling_all_non_targets_triggers_victory_win_condition():
	tutorial._start_step(TutorialManagerClass.Step.DEDUCTION_SOLVE)

	# Chisel all 20 non-target voxels using grid.hammer_cell
	for pos in grid.voxel_states.keys():
		if not grid.is_target_cell(pos):
			grid.hammer_cell(pos)

	tutorial._check_puzzle_completion()
	assert_eq(tutorial.current_step, TutorialManagerClass.Step.VICTORY, "Chiseling all non-target voxels must complete the tutorial puzzle and show victory")
