extends GutTest

const GridManagerScene = preload("res://scenes/VoxelLogic.tscn")
var grid_manager

func before_each():
	grid_manager = GridManagerScene.instantiate()
	grid_manager.base_grid_size = 3
	add_child(grid_manager)

	# Empty target solution to prevent "mistake" triggers that restart the level and kill HP
	grid_manager.target_solution.clear()

func after_each():
	grid_manager.queue_free()

func test_explosive_mechanic_triggers():
	# Trigger chisels repeatedly until combo is hit
	# The threshold is 5
	var combo_hit = false
	var exploded_block_pos = Vector3i(1, 1, 1) # Center of 3x3x3 grid

	# Empty out a block, wait for it to record
	grid_manager.on_chisel_requested(Vector3i(0, 0, 0))
	grid_manager.on_chisel_requested(Vector3i(2, 0, 0))
	grid_manager.on_chisel_requested(Vector3i(0, 2, 0))
	grid_manager.on_chisel_requested(Vector3i(2, 2, 0))

	assert_eq(grid_manager.combo, 4, "Combo should be 4")

	# Next chisel hits 5, triggering explosion around (1, 1, 1)
	grid_manager.on_chisel_requested(exploded_block_pos)

	assert_eq(grid_manager.combo, 5, "Combo should be 5")

	# Blocks adjacent to (1, 1, 1) should be destroyed by explosive chain mechanic
	# Target pos (1, 1, 0)
	var target_pos = Vector3i(1, 1, 0)
	assert_eq(grid_manager.blocks[target_pos].current_state, 3, "Adjacent block should be destroyed by chain mechanic")

	# A block far away shouldn't be touched by the radius 1 explosion
	var safe_pos = Vector3i(0, 0, 2)
	assert_eq(grid_manager.blocks[safe_pos].current_state, 0, "Far block should remain unbroken")

func test_undo_explosive_mechanic():
	grid_manager.on_chisel_requested(Vector3i(0, 0, 0))
	grid_manager.on_chisel_requested(Vector3i(2, 0, 0))
	grid_manager.on_chisel_requested(Vector3i(0, 2, 0))
	grid_manager.on_chisel_requested(Vector3i(2, 2, 0))

	grid_manager.on_chisel_requested(Vector3i(1, 1, 1)) # Explosion here
	var target_pos = Vector3i(1, 1, 0)

	assert_eq(grid_manager.blocks[target_pos].current_state, 3, "Adjacent block should be destroyed")

	# The explosion triggered an array-based group move.
	# The player chisel was one move (dict).
	# Wait, `GridManager` triggers the explosion AFTER the block is destroyed.
	# The move history is recorded in `on_chisel_requested` BEFORE `_destroy_block`.
	# So for the player move, it records:
	# 1. `_record_move(1,1,1)`
	# 2. `_destroy_block(1,1,1)` -> emits signal -> mechanic -> `start_move_group()`
	# 3. Mechanic calls `on_chisel_requested(1,1,0)` -> `_record_move(1,1,0)` -> records to group
	# 4. Mechanic ends group -> appends group to `move_history`

	# So we actually need to undo TWICE:
	# first to undo the explosion (the group array),
	# second to undo the player's trigger block.

	# Undo the explosion group
	grid_manager.undo_last_move()
	assert_eq(grid_manager.blocks[target_pos].current_state, 0, "Explosion should be undone")

	# Ensure the original block triggered it is still destroyed
	assert_eq(grid_manager.blocks[Vector3i(1, 1, 1)].current_state, 3, "Trigger block should still be destroyed")

	# Undo the player's trigger block
	grid_manager.undo_last_move()
	assert_eq(grid_manager.blocks[Vector3i(1, 1, 1)].current_state, 0, "Trigger block should be unbroken")
