extends CanvasLayer
class_name TutorialUI

const GameManagerClass = preload("res://scripts/GameManager.gd")

@onready var banner_label: Label = $MarginContainer/VBoxContainer/BannerPanel/MarginContainer/Row/BannerLabel
@onready var step_label: Label = $MarginContainer/VBoxContainer/BannerPanel/MarginContainer/Row/StepChip/MarginContainer/StepLabel
@onready var skip_button: Button = $MarginContainer/VBoxContainer/TopRow/SkipButton
@onready var tool_highlight: ColorRect = $ToolHighlight
@onready var slicer_highlight: ColorRect = $SlicerHighlight
@onready var banner_panel: PanelContainer = $MarginContainer/VBoxContainer/BannerPanel
@onready var safe_margin: MarginContainer = $MarginContainer
@onready var content_column: VBoxContainer = $MarginContainer/VBoxContainer

var tutorial_manager: TutorialManager
var _tool_target: Control
var _slicer_target: Control


func _ready() -> void:
	if skip_button:
		skip_button.pressed.connect(_on_skip_pressed)
		skip_button.focus_mode = Control.FOCUS_ALL

	_setup_pulsing(tool_highlight)
	_setup_pulsing(slicer_highlight)

	if tool_highlight:
		tool_highlight.hide()
	if slicer_highlight:
		slicer_highlight.hide()
	get_viewport().size_changed.connect(_apply_safe_area_and_position)
	call_deferred("_apply_safe_area_and_position")


func _setup_pulsing(node: CanvasItem) -> void:
	if node == null:
		return
	var tween: Tween = create_tween().set_loops()
	tween.tween_property(node, "modulate:a", 0.2, 0.8).set_trans(Tween.TRANS_SINE)
	tween.tween_property(node, "modulate:a", 0.6, 0.8).set_trans(Tween.TRANS_SINE)


func setup(manager: TutorialManager) -> void:
	tutorial_manager = manager
	if tutorial_manager == null:
		return
	tutorial_manager.hud_banner_label = banner_label
	tutorial_manager.tool_highlight_rect = tool_highlight
	tutorial_manager.slicer_slider_highlight = slicer_highlight

	if not tutorial_manager.step_advanced.is_connected(_on_step_advanced):
		tutorial_manager.step_advanced.connect(_on_step_advanced)

	_cache_highlight_targets()
	_on_step_advanced(int(tutorial_manager.current_step), tutorial_manager.step_instructions.get(tutorial_manager.current_step, ""))


func _cache_highlight_targets() -> void:
	_tool_target = null
	_slicer_target = null
	var grid_manager: Node = _get_grid_manager()
	if grid_manager == null:
		return
	var mark_value: Node = grid_manager.find_child("MarkButton", true, false)
	if mark_value is Control:
		_tool_target = mark_value as Control
	var slice_value: Node = grid_manager.find_child("SliderY", true, false)
	if slice_value is Control:
		_slicer_target = slice_value as Control
	else:
		var slice_controls: Node = grid_manager.find_child("SliceControls", true, false)
		if slice_controls is Control:
			_slicer_target = slice_controls as Control

	if _tool_target:
		if not _tool_target.resized.is_connected(_apply_safe_area_and_position):
			_tool_target.resized.connect(_apply_safe_area_and_position)
		if not _tool_target.visibility_changed.is_connected(_apply_safe_area_and_position):
			_tool_target.visibility_changed.connect(_apply_safe_area_and_position)
	if _slicer_target:
		if not _slicer_target.resized.is_connected(_apply_safe_area_and_position):
			_slicer_target.resized.connect(_apply_safe_area_and_position)
		if not _slicer_target.visibility_changed.is_connected(_apply_safe_area_and_position):
			_slicer_target.visibility_changed.connect(_apply_safe_area_and_position)
	var slice_container_value: Node = grid_manager.find_child("SliceControls", true, false)
	if slice_container_value is Control:
		var slice_container: Control = slice_container_value as Control
		if not slice_container.visibility_changed.is_connected(_apply_safe_area_and_position):
			slice_container.visibility_changed.connect(_apply_safe_area_and_position)
	call_deferred("_position_highlights")


func _get_grid_manager() -> Node:
	if tutorial_manager != null and tutorial_manager.grid_manager != null:
		return tutorial_manager.grid_manager
	var candidate: Node = get_parent()
	while candidate != null:
		if candidate.has_method("_on_slice_x_changed") or candidate.has_method("hammer_cell"):
			return candidate
		candidate = candidate.get_parent()
	return null


func _apply_safe_area_and_position() -> void:
	if not is_inside_tree():
		return
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	var insets: Vector4 = _get_safe_area_insets(viewport_size)
	if safe_margin:
		safe_margin.add_theme_constant_override("margin_left", int(insets.x + 12.0))
		safe_margin.add_theme_constant_override("margin_right", int(insets.z + 12.0))
		safe_margin.add_theme_constant_override("margin_bottom", int(insets.w + 12.0))
		# The instruction banner used to sit at the very top of the screen, which
		# is exactly where the puzzle HUD's own top bar renders. Both panels were
		# near-black, so the text was painted underneath the HUD and read as "no
		# instructions at all". Start below the HUD instead.
		safe_margin.add_theme_constant_override("margin_top", int(_banner_top_inset(insets, viewport_size)))
	if content_column:
		content_column.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	if banner_panel:
		banner_panel.custom_minimum_size = Vector2(0.0, 64.0 if viewport_size.x < 520.0 else 72.0)
		banner_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		banner_panel.clip_contents = false
	if banner_label:
		banner_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		# max_lines_visible is 0-based, not "unlimited": 0 clipped the label after
		# zero lines, so the guided instruction was never painted at all even
		# though the text was correctly assigned. -1 is the unlimited sentinel.
		banner_label.max_lines_visible = -1
		banner_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
		banner_label.add_theme_font_size_override("font_size", 16 if viewport_size.x < 520.0 else 20)
	if step_label:
		step_label.add_theme_font_size_override("font_size", 13 if viewport_size.x < 520.0 else 15)
	_position_highlights()


## Returns the top margin that clears both the safe area and the puzzle HUD.
func _banner_top_inset(insets: Vector4, viewport_size: Vector2) -> float:
	var top: float = insets.y + 12.0
	var hud_rect: Rect2 = _get_hud_top_rect()
	if hud_rect.size.y <= 0.0:
		return top
	# Only push down for a HUD that is actually near the top; a HUD placed lower
	# on the screen must not drag the banner down into the middle of the board.
	if hud_rect.position.y < top + 220.0:
		top = maxf(top, hud_rect.end.y + 12.0)
	# Never let the banner be pushed off the bottom of a very short screen.
	var max_top: float = maxf(top, viewport_size.y * 0.5)
	return minf(top, max_top)


func _get_hud_top_rect() -> Rect2:
	var grid_manager: Node = _get_grid_manager()
	if grid_manager == null:
		return Rect2()
	# The gauntlet hides the child puzzle's top row and drives its own HUD, so
	# an empty rect there simply means "nothing to clear".
	var top_row: Node = grid_manager.find_child("TopRowContainer", true, false)
	if top_row is Control and (top_row as Control).is_visible_in_tree():
		return (top_row as Control).get_global_rect()
	return Rect2()


func _position_highlights() -> void:
	_fit_highlight(tool_highlight, _tool_target, 10.0)
	_fit_highlight(slicer_highlight, _slicer_target, 8.0)


func _fit_highlight(highlight: ColorRect, target: Control, padding: float) -> void:
	if highlight == null:
		return
	if target == null or not is_instance_valid(target) or not target.is_inside_tree() or not target.is_visible_in_tree() or target.size.x <= 0.0 or target.size.y <= 0.0:
		return
	var target_rect: Rect2 = target.get_global_rect()
	var highlight_size: Vector2 = target_rect.size + Vector2(padding * 2.0, padding * 2.0)
	var highlight_position: Vector2 = target_rect.position - Vector2(padding, padding)
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	highlight_position.x = clampf(highlight_position.x, 0.0, maxf(0.0, viewport_size.x - highlight_size.x))
	highlight_position.y = clampf(highlight_position.y, 0.0, maxf(0.0, viewport_size.y - highlight_size.y))
	highlight_size.x = minf(highlight_size.x, viewport_size.x)
	highlight_size.y = minf(highlight_size.y, viewport_size.y)
	highlight.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	highlight.position = highlight_position
	highlight.size = highlight_size


func _on_step_advanced(step_index: int, instruction: String) -> void:
	if banner_label:
		banner_label.text = instruction
		call_deferred("_animate_banner")
	if step_label:
		step_label.text = "STEP %d/%d" % [step_index + 1, _total_steps()]
	if step_index > 0:
		_show_floating_text("Great job!")


func _total_steps() -> int:
	if tutorial_manager == null:
		return 1
	var instructions: Dictionary = tutorial_manager.step_instructions
	# The victory card is a result, not an instruction the player is waiting on.
	return maxi(1, instructions.size() - 1)


func _animate_banner() -> void:
	if banner_label == null or not is_instance_valid(banner_label):
		return
	banner_label.pivot_offset = banner_label.size * 0.5
	var tween: Tween = create_tween()
	tween.tween_property(banner_label, "scale", Vector2(1.04, 1.04), 0.15).set_trans(Tween.TRANS_SINE)
	tween.tween_property(banner_label, "scale", Vector2(1.0, 1.0), 0.15).set_trans(Tween.TRANS_SINE)


func _show_floating_text(text: String) -> void:
	var label: Label = Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override("font_color", Color.YELLOW)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	add_child(label)

	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var insets: Vector4 = _get_safe_area_insets(viewport_size)
	label.position = Vector2(
		clampf(insets.x, 0.0, maxf(0.0, viewport_size.x - 120.0)) + 12.0,
		viewport_size.y * 0.42
	)
	label.size = Vector2(120.0, 40.0)

	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 80.0, 0.9)
	tween.tween_property(label, "modulate:a", 0.0, 0.9)
	tween.chain().tween_callback(label.queue_free)


func _on_skip_pressed() -> void:
	var game_manager: Node = _get_game_manager()
	if game_manager:
		game_manager.set("tutorial_completed", true)
		if game_manager.has_method("save_settings"):
			game_manager.call("save_settings")
		if game_manager.has_method("switch_mode"):
			game_manager.call("switch_mode", GameManagerClass.GameMode.PUZZLE_SELECTION)


func _get_game_manager() -> Node:
	var scene_tree: SceneTree = get_tree()
	if scene_tree == null or scene_tree.root == null:
		return null
	return scene_tree.root.get_node_or_null("GameManager")


func _get_safe_area_insets(viewport_size: Vector2) -> Vector4:
	var minimum_insets: Vector4 = Vector4(12.0, 12.0, 12.0, 12.0)
	if DisplayServer.get_name() == "headless":
		return minimum_insets
	var safe_area: Rect2i = DisplayServer.get_display_safe_area()
	if safe_area.size.x <= 0 or safe_area.size.y <= 0:
		return minimum_insets
	var window_size: Vector2 = Vector2(DisplayServer.window_get_size())
	var scale: Vector2 = Vector2.ONE
	if window_size.x > 0.0 and window_size.y > 0.0:
		scale = viewport_size / window_size
	var safe_min: Vector2 = Vector2(safe_area.position) * scale
	var safe_max: Vector2 = Vector2(safe_area.position + safe_area.size) * scale
	return Vector4(
		maxf(minimum_insets.x, safe_min.x),
		maxf(minimum_insets.y, safe_min.y),
		maxf(minimum_insets.z, viewport_size.x - safe_max.x),
		maxf(minimum_insets.w, viewport_size.y - safe_max.y)
	)
