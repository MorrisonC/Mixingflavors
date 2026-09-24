extends Node3D

const GameManagerClass = preload("res://scripts/GameManager.gd")
const VoxelLogicScene: PackedScene = preload("res://scenes/VoxelLogic.tscn")
const DEFAULT_PANORAMA: Texture2D = preload("res://assets/textures/generated/abstract_panorama.svg")

var current_round: int = 1
var max_rounds: int = 999999
var time_left: float = 60.0
var current_wave_type: String = "normal"
var score: int = 0
var round_max_time: float = 60.0
var max_mistakes: int = 3
var current_health: int = 3
var active_puzzle: Node3D = null
var is_round_active: bool = true
var is_game_over: bool = false
var is_modal_open: bool = false
var _awaiting_victory_next: bool = false
var _advance_queued: bool = false

@onready var timer_label: Label = $CanvasLayer/UI/TimerLabel
@onready var round_label: Label = $CanvasLayer/UI/RoundLabel
@onready var health_label: Label = $CanvasLayer/UI/HealthLabel
@onready var score_label: Label = $CanvasLayer/UI/ScoreLabel
@onready var quit_btn: Button = $CanvasLayer/UI/QuitButton
@onready var confirm_dialog: Panel = $CanvasLayer/UI/ConfirmDialog
@onready var confirm_scrim: ColorRect = $CanvasLayer/UI/ConfirmDialog/ConfirmScrim
@onready var confirm_card: PanelContainer = $CanvasLayer/UI/ConfirmDialog/ConfirmCard
@onready var confirm_content: VBoxContainer = $CanvasLayer/UI/ConfirmDialog/VBoxContainer
@onready var yes_btn: Button = $CanvasLayer/UI/ConfirmDialog/VBoxContainer/HBoxContainer/YesButton
@onready var no_btn: Button = $CanvasLayer/UI/ConfirmDialog/VBoxContainer/HBoxContainer/NoButton
@onready var game_over: Control = $CanvasLayer/UI/GameOver
@onready var game_over_card: PanelContainer = $CanvasLayer/UI/GameOver/GameOverPanel
@onready var game_over_content: VBoxContainer = $CanvasLayer/UI/GameOver/GameOverPanel/GameOverVBox
@onready var game_over_title: Label = $CanvasLayer/UI/GameOver/GameOverPanel/GameOverVBox/GameOverTitle
@onready var game_over_message: Label = $CanvasLayer/UI/GameOver/GameOverPanel/GameOverVBox/GameOverMessage
@onready var game_over_buttons: GridContainer = $CanvasLayer/UI/GameOver/GameOverPanel/GameOverVBox/GameOverButtons
@onready var retry_btn: Button = $CanvasLayer/UI/GameOver/GameOverPanel/GameOverVBox/GameOverButtons/RetryButton
@onready var leave_btn: Button = $CanvasLayer/UI/GameOver/GameOverPanel/GameOverVBox/GameOverButtons/LeaveButton


func _ready() -> void:
	quit_btn.pressed.connect(_on_quit_pressed)
	no_btn.pressed.connect(_on_no_pressed)
	yes_btn.pressed.connect(_on_yes_pressed)
	retry_btn.pressed.connect(_on_retry_pressed)
	leave_btn.pressed.connect(_on_leave_pressed)
	get_viewport().size_changed.connect(_apply_responsive_layout)
	call_deferred("_apply_responsive_layout")
	_start_round()


func _process(delta: float) -> void:
	if not is_round_active or is_game_over or is_modal_open or _awaiting_victory_next:
		return
	if time_left <= 0.0:
		_fail_gauntlet()
		return
	time_left -= delta
	if timer_label:
		timer_label.text = "Time: " + str(int(ceil(time_left))) + "s"
	if time_left <= 0.0:
		_fail_gauntlet()


func _update_hud_labels() -> void:
	if health_label:
		health_label.text = "HP: %d/%d" % [current_health, max_mistakes]
	if score_label:
		score_label.text = "Score: " + str(score)


func _start_round() -> void:
	if is_game_over:
		return
	if is_instance_valid(active_puzzle):
		active_puzzle.queue_free()
	active_puzzle = VoxelLogicScene.instantiate() as Node3D
	active_puzzle.set("custom_puzzle_data", get_next_puzzle_for_mode())

	if current_round % 10 == 0:
		current_wave_type = "boss"
	elif current_round % 4 == 0:
		current_wave_type = "blitz"
	elif current_round % 5 == 0:
		current_wave_type = "fog"
	else:
		current_wave_type = "normal"

	var puzzle_data_value: Variant = active_puzzle.get("custom_puzzle_data")
	var puzzle_data: Dictionary = puzzle_data_value as Dictionary
	if puzzle_data == null:
		puzzle_data = {}

	var environment_node: WorldEnvironment = get_node_or_null("WorldEnvironment") as WorldEnvironment
	if environment_node and environment_node.environment and environment_node.environment.sky and environment_node.environment.sky.sky_material is PanoramaSkyMaterial:
		(environment_node.environment.sky.sky_material as PanoramaSkyMaterial).panorama = DEFAULT_PANORAMA

	var round_text: String = "Round: " + str(current_round)
	if current_wave_type == "blitz":
		round_text += " [BLITZ!]"
	elif current_wave_type == "fog":
		round_text += " [FOG!]"
	elif current_wave_type == "boss":
		round_text += " [BOSS!]"
	if round_label:
		round_label.text = round_text

	var par_time: float = float(puzzle_data.get("par_time_seconds", 120.0))
	if current_wave_type == "blitz":
		par_time *= 0.5
	round_max_time = maxf(1.0, par_time)
	time_left = round_max_time
	if timer_label:
		timer_label.text = "Time: " + str(int(ceil(time_left))) + "s"
	current_health = max_mistakes
	_update_hud_labels()

	add_child(active_puzzle)
	active_puzzle.set("player_hp", current_health)
	if active_puzzle.has_signal("puzzle_solved"):
		active_puzzle.connect("puzzle_solved", Callable(self, "_on_child_puzzle_solved"))
	if active_puzzle.has_signal("mistake_made"):
		active_puzzle.connect("mistake_made", Callable(self, "_on_mistake_made"))
	if active_puzzle.has_signal("game_over"):
		active_puzzle.connect("game_over", Callable(self, "_on_child_game_over"))
	if active_puzzle.has_method("_update_ui_state"):
		active_puzzle.call("_update_ui_state")
	_configure_child_hud()
	_set_child_input_enabled(true)
	is_round_active = true
	is_game_over = false
	is_modal_open = false
	current_health = max_mistakes
	_awaiting_victory_next = false
	_advance_queued = false
	_update_hud_labels()
	_apply_responsive_layout()


func _configure_child_hud() -> void:
	if not is_instance_valid(active_puzzle):
		return
	var child_canvas: CanvasLayer = active_puzzle.get_node_or_null("CanvasLayer") as CanvasLayer
	if child_canvas == null:
		return
	var child_ui: Control = child_canvas.get_node_or_null("Control") as Control
	if child_ui == null:
		return
	var child_top_row: Control = child_ui.get_node_or_null("MarginContainer/TopRowContainer") as Control
	if child_top_row:
		child_top_row.hide()
		for child_name in ["LeaveButton", "TimerLabel", "RoundLabel", "HPLabel", "ComboLabel", "BossContainer"]:
			var child_hud_item: CanvasItem = child_top_row.find_child(child_name, true, false) as CanvasItem
			if child_hud_item:
				child_hud_item.hide()
	var child_confirm: Control = child_ui.get_node_or_null("ConfirmDialog") as Control
	if child_confirm:
		child_confirm.hide()
	var child_toolbar: Control = _get_child_toolbar()
	if child_toolbar and not child_toolbar.resized.is_connected(_apply_responsive_layout):
		child_toolbar.resized.connect(_apply_responsive_layout)


func _get_child_toolbar() -> Control:
	if not is_instance_valid(active_puzzle):
		return null
	var child_canvas: CanvasLayer = active_puzzle.get_node_or_null("CanvasLayer") as CanvasLayer
	if child_canvas == null:
		return null
	var child_ui: Control = child_canvas.get_node_or_null("Control") as Control
	if child_ui == null:
		return null
	return child_ui.get_node_or_null("MarginContainer/VBoxContainer/HBoxContainer") as Control


func _set_child_input_enabled(enabled: bool) -> void:
	if is_instance_valid(active_puzzle):
		active_puzzle.set("input_locked", not enabled)
		if active_puzzle.has_method("set_input_locked"):
			active_puzzle.call("set_input_locked", not enabled)
	var toolbar: Control = _get_child_toolbar()
	if toolbar == null:
		return
	toolbar.mouse_filter = Control.MOUSE_FILTER_PASS if enabled else Control.MOUSE_FILTER_IGNORE
	for child in toolbar.get_children():
		if child is Button:
			(child as Button).disabled = not enabled


func _on_quit_pressed() -> void:
	if is_game_over:
		return
	_set_modal_open(true)


func _set_modal_open(open: bool) -> void:
	is_modal_open = open
	if confirm_dialog:
		confirm_dialog.visible = open
	if confirm_scrim:
		confirm_scrim.visible = open
	if quit_btn:
		quit_btn.disabled = open
	if open:
		_set_child_input_enabled(false)
		if yes_btn:
			yes_btn.call_deferred("grab_focus")
	else:
		_set_child_input_enabled(is_round_active and not _awaiting_victory_next)
		if quit_btn:
			quit_btn.call_deferred("grab_focus")


func _on_no_pressed() -> void:
	_set_modal_open(false)


func _on_yes_pressed() -> void:
	_set_modal_open(false)
	_switch_mode(GameManagerClass.GameMode.MAIN_MENU)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if confirm_dialog and confirm_dialog.visible:
		_on_no_pressed()
	elif not is_game_over:
		_on_quit_pressed()
	get_viewport().set_input_as_handled()


func get_next_puzzle_for_mode() -> Dictionary:
	var game_manager: Node = _get_game_manager()
	var mode: String = str(game_manager.get("selected_difficulty_mode")) if game_manager else "medium"
	if mode == "endless":
		return _get_endless_scaling_puzzle()
	var registry: Node = _get_puzzle_registry()
	if registry:
		var pool: Array = registry.call("get_puzzles_for_gauntlet", mode)
		if pool.is_empty():
			pool = registry.call("get_all_puzzles")
		if not pool.is_empty():
			return pool.pick_random()
	return {}


func _get_endless_scaling_puzzle() -> Dictionary:
	var target_tier: String = "easy"
	if score > 5000:
		target_tier = "boss"
	elif score > 2500:
		target_tier = "hard"
	elif score > 1000:
		target_tier = "medium"
	var registry: Node = _get_puzzle_registry()
	if registry:
		var pool: Array = registry.call("get_puzzles_for_gauntlet", target_tier)
		if pool.is_empty():
			pool = registry.call("get_all_puzzles")
		if not pool.is_empty():
			return pool.pick_random()
	return {}


func _on_child_puzzle_solved() -> void:
	if is_game_over or is_modal_open:
		return
	if _awaiting_victory_next:
		_queue_advance_after_victory()
		return
	_awaiting_victory_next = true
	is_round_active = false
	_set_child_input_enabled(false)
	if timer_label:
		timer_label.text = "Solved!"
	_watch_for_victory_screen()


func _watch_for_victory_screen() -> void:
	if not is_inside_tree():
		return
	await get_tree().create_timer(2.15).timeout
	if not is_inside_tree() or not _awaiting_victory_next or not is_instance_valid(active_puzzle):
		return
	var victory_screen: Node = _find_victory_screen(active_puzzle)
	if victory_screen and victory_screen.has_signal("start_next_nonogram_requested"):
		victory_screen.connect("start_next_nonogram_requested", Callable(self, "_on_victory_next_requested"), CONNECT_ONE_SHOT)


func _find_victory_screen(root: Node) -> Node:
	if root == null:
		return null
	if root.has_signal("start_next_nonogram_requested"):
		return root
	for child in root.get_children():
		var found: Node = _find_victory_screen(child as Node)
		if found:
			return found
	return null


func _on_victory_next_requested() -> void:
	_queue_advance_after_victory()


func _queue_advance_after_victory() -> void:
	if _advance_queued or is_game_over:
		return
	_advance_queued = true
	call_deferred("_advance_after_victory_deferred")


func _advance_after_victory_deferred() -> void:
	_advance_queued = false
	if not _awaiting_victory_next or is_game_over:
		return
	_awaiting_victory_next = false
	_complete_round()


func _on_puzzle_solved() -> void:
	# Public compatibility entry point used by tests and non-Victory callers.
	if is_game_over or is_modal_open:
		return
	if _awaiting_victory_next:
		_queue_advance_after_victory()
		return
	_complete_round()


func _complete_round() -> void:
	var time_spent: float = maxf(0.0, round_max_time - time_left)
	var time_ratio: float = clampf(time_spent / maxf(0.001, round_max_time), 0.0, 1.0)
	var bonus: int = 0
	if time_ratio <= 0.5:
		bonus = 2
	elif time_ratio <= 0.75:
		bonus = 1
	max_mistakes += bonus

	var game_manager: Node = _get_game_manager()
	if game_manager:
		if current_round == 10:
			game_manager.call("unlock_theme", "Wood")
		elif current_round == 20:
			game_manager.call("unlock_theme", "Marble")
		elif current_round == 30:
			game_manager.call("unlock_theme", "Neon Sci-Fi")

	var round_score: int = 100
	if current_wave_type == "blitz":
		round_score *= 2
	if current_wave_type == "boss":
		round_score *= 5
	score += round_score + int(maxf(0.0, time_left)) * 10
	current_round += 1
	_start_round()


func _on_child_game_over() -> void:
	_fail_gauntlet()

func _on_mistake_made(total_mistakes: int) -> void:
	if is_instance_valid(active_puzzle):
		current_health = int(active_puzzle.get("player_hp"))
	_update_hud_labels()
	if total_mistakes >= max_mistakes:
		_fail_gauntlet()


func _fail_gauntlet() -> void:
	if is_game_over:
		return
	is_round_active = false
	is_game_over = true
	is_modal_open = false
	if confirm_dialog:
		confirm_dialog.hide()
	if is_instance_valid(active_puzzle):
		active_puzzle.set("is_puzzle_active", false)
	_set_child_input_enabled(false)
	if game_over_title:
		game_over_title.text = "GAUNTLET FAILED"
	if game_over_message:
		game_over_message.text = "Game over\nScore: " + str(score)
	if game_over:
		game_over.show()
		if retry_btn:
			retry_btn.call_deferred("grab_focus")
	print("[EscapeGauntlet] Gauntlet Failed!")


func _win_gauntlet() -> void:
	if is_game_over:
		return
	is_round_active = false
	is_game_over = true
	is_modal_open = false
	if confirm_dialog:
		confirm_dialog.hide()
	_set_child_input_enabled(false)
	if game_over_title:
		game_over_title.text = "GAUNTLET CLEARED!"
	if game_over_message:
		game_over_message.text = "You survived the gauntlet.\nScore: " + str(score)
	if game_over:
		game_over.show()


func _on_retry_pressed() -> void:
	_switch_mode(GameManagerClass.GameMode.ESCAPE_GAUNTLET)


func _on_leave_pressed() -> void:
	_switch_mode(GameManagerClass.GameMode.MAIN_MENU)


func _switch_mode(mode: int) -> void:
	var game_manager: Node = _get_game_manager()
	if game_manager and game_manager.has_method("switch_mode"):
		game_manager.call("switch_mode", mode)


func _get_game_manager() -> Node:
	var scene_tree: SceneTree = get_tree()
	if scene_tree == null or scene_tree.root == null:
		return null
	return scene_tree.root.get_node_or_null("GameManager")


func _get_puzzle_registry() -> Node:
	var scene_tree: SceneTree = get_tree()
	if scene_tree == null or scene_tree.root == null:
		return null
	return scene_tree.root.get_node_or_null("PuzzleRegistry")


func _apply_responsive_layout() -> void:
	if not is_inside_tree():
		return
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	var insets: Vector4 = _get_safe_area_insets(viewport_size)
	var compact: bool = viewport_size.x < 520.0 or viewport_size.y < 560.0
	var stacked_hud: bool = viewport_size.x < 420.0
	var third_hud_row: bool = viewport_size.x < 300.0
	var base_edge: float = 12.0 if compact else 20.0
	var left_edge: float = insets.x + base_edge
	var right_edge: float = insets.z + base_edge
	var top_edge: float = insets.y + base_edge
	var bottom_edge: float = insets.w + base_edge
	var hud_width: float = 130.0 if compact else 150.0

	if quit_btn:
		quit_btn.anchor_left = 1.0
		quit_btn.anchor_right = 1.0
		quit_btn.anchor_top = 1.0
		quit_btn.anchor_bottom = 1.0
		var reserved_toolbar_height: float = 172.0
		var child_toolbar: Control = _get_child_toolbar()
		if child_toolbar and child_toolbar.size.y > 0.0:
			reserved_toolbar_height = child_toolbar.size.y
		quit_btn.offset_left = -right_edge - 96.0
		quit_btn.offset_right = -right_edge
		quit_btn.offset_top = -bottom_edge - reserved_toolbar_height - 8.0 - 48.0
		quit_btn.offset_bottom = -bottom_edge - reserved_toolbar_height - 8.0
		quit_btn.custom_minimum_size = Vector2(96.0, 48.0)
		quit_btn.focus_mode = Control.FOCUS_ALL
	if round_label:
		round_label.anchor_left = 0.5
		round_label.anchor_right = 0.5
		round_label.anchor_top = 0.0
		round_label.anchor_bottom = 0.0
		var round_width: float = minf(280.0, maxf(1.0, viewport_size.x - insets.x - insets.z - 24.0))
		round_label.offset_left = -round_width * 0.5
		round_label.offset_right = round_width * 0.5
		round_label.offset_top = top_edge
		round_label.offset_bottom = round_label.offset_top + 32.0
		round_label.add_theme_font_size_override("font_size", 16 if compact else 20)
	if timer_label:
		timer_label.anchor_left = 1.0
		timer_label.anchor_right = 1.0
		timer_label.anchor_top = 0.0
		timer_label.anchor_bottom = 0.0
		timer_label.offset_left = -right_edge - hud_width
		timer_label.offset_right = -right_edge
		timer_label.offset_top = top_edge + (34.0 if stacked_hud else 0.0)
		timer_label.offset_bottom = timer_label.offset_top + 32.0
		timer_label.add_theme_font_size_override("font_size", 16 if compact else 20)
	if health_label:
		health_label.anchor_left = 0.0
		health_label.anchor_right = 0.0
		health_label.anchor_top = 0.0
		health_label.anchor_bottom = 0.0
		health_label.offset_left = left_edge
		health_label.offset_right = left_edge + hud_width
		health_label.offset_top = top_edge + (34.0 if stacked_hud else 0.0)
		health_label.offset_bottom = health_label.offset_top + 32.0
		health_label.add_theme_font_size_override("font_size", 16 if compact else 20)
	if score_label:
		score_label.anchor_left = 1.0
		score_label.anchor_right = 1.0
		score_label.anchor_top = 0.0
		score_label.anchor_bottom = 0.0
		score_label.offset_left = -right_edge - hud_width
		score_label.offset_right = -right_edge
		score_label.offset_top = top_edge + (68.0 if third_hud_row else 34.0 if stacked_hud else 0.0)
		score_label.offset_bottom = score_label.offset_top + 32.0
		score_label.add_theme_font_size_override("font_size", 16 if compact else 20)

	if confirm_dialog:
		confirm_dialog.anchor_left = 0.0
		confirm_dialog.anchor_right = 1.0
		confirm_dialog.anchor_top = 0.0
		confirm_dialog.anchor_bottom = 1.0
		confirm_dialog.offset_left = 0.0
		confirm_dialog.offset_right = 0.0
		confirm_dialog.offset_top = 0.0
		confirm_dialog.offset_bottom = 0.0
	if confirm_card and confirm_content:
		var confirm_width: float = minf(340.0, maxf(1.0, viewport_size.x - insets.x - insets.z - 24.0))
		var preferred_confirm_height: float = 180.0 if compact else 200.0
		var confirm_height: float = minf(preferred_confirm_height, maxf(1.0, viewport_size.y - insets.y - insets.w - 24.0))
		confirm_card.offset_left = -confirm_width * 0.5
		confirm_card.offset_right = confirm_width * 0.5
		confirm_card.offset_top = -confirm_height * 0.5
		confirm_card.offset_bottom = confirm_height * 0.5
		confirm_content.offset_left = -confirm_width * 0.5 + 20.0
		confirm_content.offset_right = confirm_width * 0.5 - 20.0
		confirm_content.offset_top = -confirm_height * 0.5 + 16.0
		confirm_content.offset_bottom = confirm_height * 0.5 - 16.0
	var confirm_button_width: float = 80.0 if viewport_size.x < 300.0 else 90.0 if compact else 110.0
	if yes_btn:
		yes_btn.custom_minimum_size = Vector2(confirm_button_width, 48.0)
	if no_btn:
		no_btn.custom_minimum_size = Vector2(confirm_button_width, 48.0)
	if game_over:
		game_over.anchor_left = 0.0
		game_over.anchor_right = 1.0
		game_over.anchor_top = 0.0
		game_over.anchor_bottom = 1.0
		game_over.offset_left = 0.0
		game_over.offset_right = 0.0
		game_over.offset_top = 0.0
		game_over.offset_bottom = 0.0
	if game_over_card and game_over_content:
		var game_over_width: float = minf(380.0, maxf(1.0, viewport_size.x - insets.x - insets.z - 24.0))
		var preferred_game_over_height: float = 260.0 if compact else 300.0
		var game_over_height: float = minf(preferred_game_over_height, maxf(1.0, viewport_size.y - insets.y - insets.w - 24.0))
		game_over_card.offset_left = -game_over_width * 0.5
		game_over_card.offset_right = game_over_width * 0.5
		game_over_card.offset_top = -game_over_height * 0.5
		game_over_card.offset_bottom = game_over_height * 0.5
		game_over_content.offset_left = -game_over_width * 0.5 + 20.0
		game_over_content.offset_right = game_over_width * 0.5 - 20.0
		game_over_content.offset_top = -game_over_height * 0.5 + 16.0
		game_over_content.offset_bottom = game_over_height * 0.5 - 16.0
	if game_over_buttons:
		game_over_buttons.columns = 1 if viewport_size.x < 300.0 else 2
		for child in game_over_buttons.get_children():
			if child is Button:
				var game_over_button: Button = child as Button
				game_over_button.custom_minimum_size = Vector2(0.0, 48.0)
				game_over_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				game_over_button.focus_mode = Control.FOCUS_ALL


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
