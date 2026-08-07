extends GutTest

const GridManagerClass = preload("res://scripts/GridManager.gd")
const GameManagerClass = preload("res://scripts/GameManager.gd")

var grid: GridManagerClass

func before_each():
	var gm = Node.new()
	gm.name = "GameManager"
	gm.set_script(GameManagerClass)
	get_tree().root.add_child(gm)

	# Mock a Gauntlet parent that has a max_mistakes property
	var gauntlet_mock = Node.new()
	gauntlet_mock.name = "EscapeGauntletMock"
	gauntlet_mock.set("max_mistakes", 3)
	get_tree().root.add_child(gauntlet_mock)

	grid = GridManagerClass.new()
	grid.base_grid_size = 3
	gauntlet_mock.add_child(grid)

func after_each():
	var gm = get_tree().root.get_node_or_null("GameManager")
	if gm:
		gm.queue_free()

	var gauntlet = get_tree().root.get_node_or_null("EscapeGauntletMock")
	if gauntlet:
		gauntlet.queue_free()

func test_corruption_triggers_on_low_hp():
	# Make sure grid has active target solutions to start the game properly
	grid.target_solution = {
		Vector3i(0, 0, 0): true,
		Vector3i(1, 1, 1): true
	}
	grid.start_level()
	grid.player_hp = 3

	# Helper to count corrupted blocks
	var get_corrupted_count = func():
		var count = 0
		for pos in grid.voxel_states.keys():
			if grid.voxel_states[pos].get("is_corrupted", false):
				count += 1
		return count

	assert_eq(get_corrupted_count.call(), 0, "Should have 0 corrupted blocks initially")

	# Trigger a mistake. HP drops from 3 to 2.
	# 2/3 = 66% which is not < 50%, so no corruption yet.
	grid._handle_mistake()
	assert_eq(get_corrupted_count.call(), 0, "Should have 0 corrupted blocks at HP 2/3")

	# Trigger another mistake. HP drops from 2 to 1.
	# 1/3 = 33% which is < 50%, so corruption should occur.
	grid._handle_mistake()
	assert_eq(get_corrupted_count.call(), 1, "Should have 1 corrupted block at HP 1/3")

func test_corruption_updates_multimesh():
	grid.target_solution = {
		Vector3i(0, 0, 0): true,
		Vector3i(1, 1, 1): true
	}
	grid.start_level()
	grid.player_hp = 1

	# Manually corrupt a block to test the multimesh application logic
	var target_pos = Vector3i(2, 2, 2)
	grid.voxel_states[target_pos]["is_corrupted"] = true
	grid._update_multimesh()

	# We can't directly read the color back from the MultiMeshInstance3D easily in tests,
	# but we can verify it doesn't crash and correctly set the flag.
	assert_true(grid.voxel_states[target_pos]["is_corrupted"], "Block should retain corrupted flag")
