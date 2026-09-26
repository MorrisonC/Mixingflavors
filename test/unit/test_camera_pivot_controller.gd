extends GutTest

const CameraPivotControllerClass = preload("res://scripts/CameraPivotController.gd")

var controller: CameraPivotController


func before_each() -> void:
	controller = CameraPivotControllerClass.new()
	add_child_autoqfree(controller)


func test_resolution_independent_orbit_delta() -> void:
	var half_resolution_delta: Vector2 = controller.normalized_orbit_delta(Vector2(10.0, 5.0), Vector2(640.0, 360.0))
	var full_resolution_delta: Vector2 = controller.normalized_orbit_delta(Vector2(20.0, 10.0), Vector2(1280.0, 720.0))
	assert_almost_eq(half_resolution_delta.x, full_resolution_delta.x, 0.0001)
	assert_almost_eq(half_resolution_delta.y, full_resolution_delta.y, 0.0001)


func test_fit_to_grid_is_finite_and_respects_realistic_minimum() -> void:
	controller.min_distance = 1.0
	controller.minimum_safe_distance = 4.0
	var fit_distance: float = controller.fit_to_grid(Vector3i(5, 5, 5))
	assert_true(is_finite(fit_distance), "Grid fit must never return NaN or Inf")
	assert_true(fit_distance >= 4.0, "Grid fit must respect the realistic minimum distance")
	assert_almost_eq(controller.target_distance, fit_distance, 0.0001)


func test_fit_handles_invalid_dimensions_without_corrupting_distance() -> void:
	controller.target_distance = 12.0
	var previous_distance: float = controller.target_distance
	var fit_distance: float = controller.fit_to_grid(Vector3i(0, -1, 2))
	assert_true(is_finite(fit_distance))
	assert_almost_eq(fit_distance, previous_distance, 0.0001)
	assert_almost_eq(controller.target_distance, previous_distance, 0.0001)


func test_zoom_is_clamped_at_both_ends() -> void:
	controller.min_distance = 4.0
	controller.minimum_safe_distance = 4.0
	controller.max_distance = 20.0
	controller.target_distance = 19.0
	controller.add_zoom_input(10.0)
	assert_true(controller.target_distance <= 20.0)
	controller.target_distance = 5.0
	controller.add_zoom_input(-10.0)
	assert_true(controller.target_distance >= 4.0)


func test_fit_aliases_delegate_to_safe_fit() -> void:
	var first_distance: float = controller.fit_grid_to_view(Vector3i(3, 3, 3))
	var second_distance: float = controller.fit_camera_to_grid(Vector3i(3, 3, 3))
	assert_true(is_finite(first_distance))
	assert_true(is_finite(second_distance))
	assert_almost_eq(first_distance, second_distance, 0.0001)


# The camera could be pinched in until it sat INSIDE a puzzle. Every ray then
# resolved to the single cell containing the origin, so the whole screen became
# one un-chiselable target. The fit now raises the distance floor to the
# puzzle's own bounding radius.
func test_camera_cannot_be_pulled_inside_the_puzzle() -> void:
	controller.min_distance = 0.5
	controller.minimum_safe_distance = 0.5
	var large: Vector3i = Vector3i(16, 12, 10)
	controller.fit_to_grid(large)
	var radius: float = (Vector3(large) * controller.voxel_size * 0.5).length()
	controller.target_distance = 0.1
	controller.add_zoom_input(-100.0)
	assert_gt(controller.target_distance, radius, "The camera must never be closer than the puzzle radius")
	# And the floor must follow the puzzle, not stick at the largest one seen.
	controller.fit_to_grid(Vector3i(3, 3, 3))
	controller.target_distance = 0.1
	controller.add_zoom_input(-100.0)
	var small_radius: float = (Vector3(3, 3, 3) * controller.voxel_size * 0.5).length()
	assert_lt(controller.target_distance, radius, "A small puzzle must not keep the large puzzle's floor")
	assert_gt(controller.target_distance, small_radius)


# Reset View is the advertised recovery action, but it only restored orientation
# and left the distance wherever the player had pinched to.
func test_reset_view_restores_the_fitted_distance_not_just_orientation() -> void:
	controller.fit_to_grid(Vector3i(5, 5, 5))
	var fitted: float = controller.target_distance
	controller.target_distance = fitted * 0.3
	controller.current_distance = controller.target_distance
	controller.reset_view(0.0)
	assert_almost_eq(controller.target_distance, fitted, 0.0001, "Reset must re-fit the distance")
	assert_almost_eq(controller.current_distance, fitted, 0.0001, "The live distance must be restored too")


func test_reset_view_is_safe_before_any_fit() -> void:
	controller.target_distance = 12.0
	controller.current_distance = 12.0
	controller.reset_view(0.0)
	assert_true(is_finite(controller.target_distance), "Reset must not produce a non-finite distance")
	assert_gt(controller.target_distance, 0.0)