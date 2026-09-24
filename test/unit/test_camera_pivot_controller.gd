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
