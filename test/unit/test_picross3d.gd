extends GutTest

const Picross3DScene = preload("res://scenes/Picross3D.tscn")
var picross

func before_each():
	picross = Picross3DScene.instantiate()
	# ensure it uses a small consistent size
	picross.grid_size = Vector3i(2, 2, 2)
	add_child(picross)

func after_each():
	picross.queue_free()

func test_generate_hints():
	# _generate_hints is called in _ready, so hints_container should have children
	assert_gt(picross.hints_container.get_child_count(), 0, "Hints should be generated")

func test_calculate_line_hint_zero():
	# Forcibly set a line to empty to test hint logic
	picross.voxel_data[Vector3i(0,0,0)]["target"] = picross.VoxelTargetState.EMPTY
	picross.voxel_data[Vector3i(1,0,0)]["target"] = picross.VoxelTargetState.EMPTY
	var hint = picross._calculate_line_hint(Vector3i(0,0,0), Vector3i(1,0,0), 2)
	assert_eq(hint, "0", "Empty line should return '0'")

func test_calculate_line_hint_contiguous():
	picross.voxel_data[Vector3i(0,0,0)]["target"] = picross.VoxelTargetState.FILLED
	picross.voxel_data[Vector3i(1,0,0)]["target"] = picross.VoxelTargetState.FILLED
	var hint = picross._calculate_line_hint(Vector3i(0,0,0), Vector3i(1,0,0), 2)
	assert_eq(hint, "2", "Contiguous line should return 'N'")

func test_calculate_line_hint_split():
	# Need a grid size of 3 for this
	picross.grid_size = Vector3i(3,3,3)
	picross._generate_solution() # regen for size
	picross.voxel_data[Vector3i(0,0,0)]["target"] = picross.VoxelTargetState.FILLED
	picross.voxel_data[Vector3i(1,0,0)]["target"] = picross.VoxelTargetState.EMPTY
	picross.voxel_data[Vector3i(2,0,0)]["target"] = picross.VoxelTargetState.FILLED
	var hint = picross._calculate_line_hint(Vector3i(0,0,0), Vector3i(1,0,0), 3)
	assert_eq(hint, "(2)", "Split line should return '(N)'")

func test_slicing_hides_voxels():
	# Initial state should show block at 0,0,0
	assert_true(picross.voxel_nodes[Vector3i(0,0,0)]["mesh"].visible, "Block should be visible initially")

	# Slice so max is -1 (should hide everything, or hide block at 0,0,0)
	picross.set_slice(Vector3i(1, 1, 1), Vector3i(1, 1, 1))
	assert_false(picross.voxel_nodes[Vector3i(0,0,0)]["mesh"].visible, "Block should be hidden after slice")
