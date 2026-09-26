extends Node3D

const GameManagerClass = preload("res://scripts/GameManager.gd")
const PuzzleManagerClass = preload("res://scripts/PuzzleManager.gd")
const DailyChallengeServiceClass = preload("res://scripts/DailyChallengeService.gd")
const RunHistoryServiceClass = preload("res://scripts/RunHistoryService.gd")
const VoxelLogicScene: PackedScene = preload("res://scenes/VoxelLogic.tscn")
const BASE_ROUND_TIME: float = 120.0
const DAILY_CHALLENGE_DEPTH: int = 31
# Frames polled one scan per frame while the result card is expected. Past that
# the watcher slows down so an unusually slow reveal cannot cost a recursive
# tree scan every frame for the rest of the round.
const VICTORY_WATCH_FAST_FRAMES: int = 300
const VICTORY_WATCH_SLOW_INTERVAL: int = 15
# The parent HUD, and with it the Leave/Quit button, is hidden while the result
# card plays. After this long the HUD is handed back to the player even if the
# card never arrives, so a touch player can always leave the run.
var victory_card_grace_seconds: float = 30.0

var current_round: int = 1
var max_rounds: int = 999999
var time_left: float = BASE_ROUND_TIME
var current_wave_type: String = "normal"
var score: int = 0
var round_max_time: float = BASE_ROUND_TIME
var run_seed: int = 0
var puzzle_manager: Node = null
var gauntlet_manager: Node = null
var max_mistakes: int = 3
var current_health: int = 3
var active_puzzle: Node3D = null
var is_round_active: bool = true
var is_game_over: bool = false
var is_modal_open: bool = false
var _awaiting_victory_next: bool = false
var _victory_reveal_owns_hud: bool = false
var _advance_queued: bool = false
var is_daily_challenge: bool = false
var daily_id: int = -1
var daily_date: String = ""
var daily_ruleset_version: int = GameManagerClass.DAILY_RULESET_VERSION
var daily_catalog_version: int = GameManagerClass.DAILY_CATALOG_VERSION
var _daily_result_recorded: bool = false
var run_puzzle_ids: Array[String] = []
var run_session_token: String = ""
var pending_clear_preview: Dictionary = {}

@onready var timer_label: Label = $CanvasLayer/UI/TimerLabel
@onready var round_label: Label = $CanvasLayer/UI/RoundLabel
@onready var health_label: Label = $CanvasLayer/UI/HealthLabel
@onready var score_label: Label = $CanvasLayer/UI/ScoreLabel
@onready var bank_label: Label = $CanvasLayer/UI/BankLabel
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
	run_session_token = "%d-%d" % [Time.get_ticks_msec(), get_instance_id()]
	quit_btn.pressed.connect(_on_quit_pressed)
	no_btn.pressed.connect(_on_no_pressed)
	yes_btn.pressed.connect(_on_yes_pressed)
	retry_btn.pressed.connect(_on_retry_pressed)
	leave_btn.pressed.connect(_on_leave_pressed)
	get_viewport().size_changed.connect(_apply_responsive_layout)
	call_deferred("_apply_responsive_layout")
	_initialize_run_services()
	_start_round()


func _initialize_run_services() -> void:
	puzzle_manager = get_node_or_null("/root/PuzzleManager") as Node
	gauntlet_manager = get_node_or_null("/root/GauntletManager") as Node
	var game_manager: Node = _get_game_manager()
	if game_manager:
		run_seed = int(game_manager.get("selected_run_seed"))
		var mode_payload: Variant = game_manager.get("mode_payload")
		if mode_payload is Dictionary:
			var payload: Dictionary = mode_payload as Dictionary
			is_daily_challenge = bool(payload.get("daily_challenge", false))
			daily_id = int(payload.get("daily_id", -1))
			daily_date = str(payload.get("daily_date", ""))
			daily_ruleset_version = int(payload.get("daily_ruleset_version", GameManagerClass.DAILY_RULESET_VERSION))
			daily_catalog_version = int(payload.get("daily_catalog_version", GameManagerClass.DAILY_CATALOG_VERSION))
		if is_daily_challenge:
			max_rounds = DAILY_CHALLENGE_DEPTH
		if gauntlet_manager and gauntlet_manager.has_method("set_puzzle_manager"):
			gauntlet_manager.call("set_puzzle_manager", puzzle_manager)
		if gauntlet_manager and gauntlet_manager.has_method("start_run"):
			var difficulty: String = str(game_manager.get("selected_difficulty_mode"))
			gauntlet_manager.call("start_run", difficulty, run_seed)
			current_round = int(gauntlet_manager.get("depth"))
			time_left = float(gauntlet_manager.get("time_left"))
			round_max_time = float(gauntlet_manager.get("round_time_limit"))


func _process(delta: float) -> void:
	if not is_round_active or is_game_over or is_modal_open or _awaiting_victory_next:
		return
	if gauntlet_manager and gauntlet_manager.has_method("tick"):
		gauntlet_manager.call("tick", delta)
		time_left = float(gauntlet_manager.get("time_left"))
		current_round = int(gauntlet_manager.get("depth"))
		score = int(gauntlet_manager.get("score"))
	else:
		time_left = maxf(0.0, time_left - maxf(0.0, delta))
	if timer_label:
		timer_label.text = "Time: " + str(int(ceil(time_left))) + "s"
	if time_left <= 0.0:
		_fail_gauntlet()


func _update_hud_labels() -> void:
	if health_label:
		health_label.text = "HP: %d/%d" % [current_health, max_mistakes]
	if score_label:
		score_label.text = "Score: " + str(score)
	if bank_label:
		var banked_time: float = float(gauntlet_manager.get("banked_time")) if gauntlet_manager else 0.0
		bank_label.text = "Reserve: " + str(int(floor(banked_time))) + "s"


func _start_round() -> void:
	if is_game_over:
		return
	if is_instance_valid(active_puzzle):
		var old_parent: Node = active_puzzle.get_parent()
		if old_parent != null:
			old_parent.remove_child(active_puzzle)
		active_puzzle.queue_free()
	active_puzzle = VoxelLogicScene.instantiate() as Node3D
	var selected_puzzle: Dictionary = get_next_puzzle_for_mode()
	if selected_puzzle.is_empty():
		push_error("[EscapeGauntlet] No validated puzzle was available for depth %d" % current_round)
		selected_puzzle = _load_fallback_puzzle()
	var selected_id: String = str(selected_puzzle.get("id", ""))
	if not selected_id.is_empty():
		run_puzzle_ids.append(selected_id)
	active_puzzle.set("custom_puzzle_data", selected_puzzle)
	active_puzzle.set("current_floor", current_round)

	if current_round % 10 == 0:
		current_wave_type = "boss"
	elif current_round % 4 == 0:
		current_wave_type = "blitz"
	elif current_round % 5 == 0:
		current_wave_type = "fog"
	else:
		current_wave_type = "normal"

	var puzzle_data_value: Variant = active_puzzle.get("custom_puzzle_data")
	var puzzle_data: Dictionary = puzzle_data_value as Dictionary if puzzle_data_value is Dictionary else {}
	if puzzle_data == null:
		puzzle_data = {}

	var round_text: String = ("Daily %d/%d" % [current_round, DAILY_CHALLENGE_DEPTH]) if is_daily_challenge else ("Round %d" % current_round)
	# Keep the internal wave classification for compatibility, but do not
	# advertise cosmetic labels as mechanics. BLITZ/FOG/BOSS return only after
	# GauntletManager exposes tested rules and counterplay.
	if round_label:
		round_label.text = round_text

	var par_time: float = float(puzzle_data.get("par_time_seconds", BASE_ROUND_TIME))
	if current_wave_type == "blitz":
		par_time *= 0.5
	if gauntlet_manager and gauntlet_manager.has_method("get_state"):
		var run_state: Dictionary = gauntlet_manager.call("get_state")
		round_max_time = maxf(BASE_ROUND_TIME, float(run_state.get("round_time_limit", BASE_ROUND_TIME)))
		time_left = maxf(0.0, float(run_state.get("time_left", round_max_time)))
	else:
		# The service is authoritative. If it is unavailable, fail closed to
		# the documented round contract instead of granting a puzzle par-time
		# extension that could differ between scenes.
		push_warning("[EscapeGauntlet] GauntletManager unavailable; using fixed 120-second fallback")
		round_max_time = BASE_ROUND_TIME
		time_left = BASE_ROUND_TIME
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
	_set_parent_hud_visible(true)
	_set_child_input_enabled(true)
	var audio_manager: Node = get_node_or_null("/root/AudioManager")
	if audio_manager and audio_manager.has_method("play_round_start_sfx"):
		audio_manager.call("play_round_start_sfx")
	is_round_active = true
	is_game_over = false
	is_modal_open = false
	current_health = max_mistakes
	_awaiting_victory_next = false
	_advance_queued = false
	pending_clear_preview = {}
	_update_hud_labels()
	_apply_responsive_layout()


func _set_parent_hud_visible(visible_state: bool) -> void:
	var parent_hud: Control = get_node_or_null("CanvasLayer/UI") as Control
	if parent_hud:
		parent_hud.visible = visible_state
	# This is the only place that decides whether a round reveal currently owns a
	# hidden parent HUD. Anything that gives the HUD back (round start, win,
	# failure, or an abandoned victory wait) clears the lock, so the HUD can
	# never stay hidden behind a stale lock while _awaiting_victory_next is true.
	_victory_reveal_owns_hud = not visible_state and _awaiting_victory_next


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
	# Keep the container itself opaque to input. Passing touches through when
	# enabled let a tap on an empty toolbar cell - the second row is mostly
	# empty in a 5-column layout - reach the puzzle's touch Control, where it
	# resolved to no voxel yet still opened the double-tap window and swallowed
	# the player's next real chisel. Per-button disabling below is enough.
	toolbar.mouse_filter = Control.MOUSE_FILTER_STOP
	for child in toolbar.get_children():
		if child is Button:
			(child as Button).disabled = not enabled


func _on_quit_pressed() -> void:
	if is_game_over:
		return
	_set_parent_hud_visible(true)
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
			call_deferred("_safe_focus", yes_btn)
	else:
		_set_child_input_enabled(is_round_active and not _awaiting_victory_next)
		if quit_btn:
			call_deferred("_safe_focus", quit_btn)


func _safe_focus(control: Control) -> void:
	if is_inside_tree() and is_instance_valid(control) and control.is_inside_tree() and control.is_visible_in_tree():
		control.grab_focus()


func _on_no_pressed() -> void:
	_set_modal_open(false)
	if _awaiting_victory_next and _victory_reveal_owns_hud:
		_set_parent_hud_visible(false)


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
	# The domain service owns selection. The scene only renders the puzzle it
	# already selected for the current depth; this prevents sequence drift when
	# catalog or fallback behavior changes.
	if gauntlet_manager and gauntlet_manager.has_method("get_state"):
		var run_state: Dictionary = gauntlet_manager.call("get_state")
		var service_depth: int = int(run_state.get("depth", current_round))
		var active_puzzle: Variant = run_state.get("active_puzzle", {})
		if service_depth == current_round and active_puzzle is Dictionary and not (active_puzzle as Dictionary).is_empty():
			return (active_puzzle as Dictionary).duplicate(true)
	var game_manager: Node = _get_game_manager()
	var mode: String = str(game_manager.get("selected_difficulty_mode")) if game_manager else "endless"
	var selected_seed: int = run_seed
	if game_manager:
		selected_seed = int(game_manager.get("selected_run_seed"))
	if puzzle_manager == null:
		puzzle_manager = get_node_or_null("/root/PuzzleManager") as Node
	if puzzle_manager and puzzle_manager.has_method("get_puzzle_for_round"):
		var selected: Variant = puzzle_manager.call("get_puzzle_for_round", selected_seed, current_round, mode)
		if selected is Dictionary and not (selected as Dictionary).is_empty():
			return (selected as Dictionary).duplicate(true)
	return _load_fallback_puzzle()


func _get_endless_scaling_puzzle() -> Dictionary:
	var target_tier: String = "easy"
	if current_round <= 10:
		target_tier = "easy"
	elif current_round <= 30:
		target_tier = "medium"
	else:
		target_tier = "hard"
	if puzzle_manager and puzzle_manager.has_method("get_puzzles_for_tier"):
		var pool: Array = puzzle_manager.call("get_puzzles_for_tier", target_tier)
		if not pool.is_empty():
			var index: int = absi(run_seed + current_round * 17) % pool.size()
			return (pool[index] as Dictionary).duplicate(true)
	return _load_fallback_puzzle()


func _load_fallback_puzzle() -> Dictionary:
	if puzzle_manager and puzzle_manager.has_method("get_fallback_puzzle"):
		var fallback: Variant = puzzle_manager.call("get_fallback_puzzle")
		if fallback is Dictionary and not (fallback as Dictionary).is_empty():
			return (fallback as Dictionary).duplicate(true)
	var fallback_path: String = "res://data/puzzles/tutorial_star.json"
	if not FileAccess.file_exists(fallback_path):
		return {}
	var file: FileAccess = FileAccess.open(fallback_path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed as Dictionary if parsed is Dictionary else {}


func _on_child_puzzle_solved() -> void:
	if is_game_over or is_modal_open:
		return
	if _awaiting_victory_next:
		_queue_advance_after_victory()
		return
	_prepare_victory_preview()
	_awaiting_victory_next = true
	is_round_active = false
	_set_parent_hud_visible(false)
	_set_child_input_enabled(false)
	if timer_label:
		timer_label.text = "Solved!"
	_watch_for_victory_screen()


func _prepare_victory_preview() -> void:
	pending_clear_preview = {}
	if not gauntlet_manager or not gauntlet_manager.has_method("preview_clear"):
		return
	var par_time: float = BASE_ROUND_TIME
	if is_instance_valid(active_puzzle):
		var puzzle_data: Variant = active_puzzle.get("custom_puzzle_data")
		if puzzle_data is Dictionary:
			par_time = float((puzzle_data as Dictionary).get("par_time_seconds", BASE_ROUND_TIME))
	var preview: Variant = gauntlet_manager.call("preview_clear", par_time)
	if preview is Dictionary and not (preview as Dictionary).is_empty():
		pending_clear_preview = (preview as Dictionary).duplicate(true)
		if is_instance_valid(active_puzzle):
			active_puzzle.set("victory_preview", pending_clear_preview)


func _watch_for_victory_screen() -> void:
	if not is_inside_tree():
		return
	# The child waits for its reveal animation before creating the result card.
	# Poll by frame rather than guessing a 2.15-second delay: the Continue
	# signal must be connected before the player can press the first frame.
	# This wait has no deadline. Abandoning it used to strand the player with a
	# hidden parent HUD - and therefore without the Leave/Quit button - while
	# _awaiting_victory_next stayed true, leaving only ui_cancel as an escape.
	# Instead the wait runs until the card shows up, and the HUD is handed back
	# to the player if the card is overdue or the wait is abandoned.
	var release_at_msec: int = Time.get_ticks_msec() + int(maxf(0.0, victory_card_grace_seconds) * 1000.0)
	var scan_count: int = 0
	var poll_delay: int = 0
	while is_inside_tree() and _awaiting_victory_next and is_instance_valid(active_puzzle):
		if poll_delay <= 0:
			scan_count += 1
			var victory_screen: Node = _find_victory_screen(active_puzzle)
			if victory_screen != null and victory_screen.has_signal("start_next_nonogram_requested"):
				if not victory_screen.is_connected("start_next_nonogram_requested", Callable(self, "_on_victory_next_requested")):
					victory_screen.connect("start_next_nonogram_requested", Callable(self, "_on_victory_next_requested"), CONNECT_ONE_SHOT)
				return
			if Time.get_ticks_msec() >= release_at_msec:
				_release_victory_hud_lock()
			poll_delay = 0 if scan_count <= VICTORY_WATCH_FAST_FRAMES else VICTORY_WATCH_SLOW_INTERVAL - 1
		poll_delay -= 1
		await get_tree().process_frame
	_release_victory_hud_lock()


func _release_victory_hud_lock() -> void:
	# A reveal that can no longer hand control to its result card must give the
	# player back the parent HUD, which carries the Leave/Quit button. Clearing
	# the lock also stops _on_no_pressed from hiding the HUD again after the
	# player dismisses the quit dialog.
	if not _victory_reveal_owns_hud or not is_inside_tree():
		return
	push_warning("[EscapeGauntlet] Victory card did not appear; restoring round controls so the player can leave")
	_set_parent_hud_visible(true)
	_set_child_input_enabled(true)


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
	if pending_clear_preview.is_empty():
		_prepare_victory_preview()
	var time_spent: float = maxf(0.0, round_max_time - time_left)
	var time_ratio: float = clampf(time_spent / maxf(0.001, round_max_time), 0.0, 1.0)
	var par_time: float = BASE_ROUND_TIME
	if is_instance_valid(active_puzzle):
		var puzzle_data: Variant = active_puzzle.get("custom_puzzle_data")
		if puzzle_data is Dictionary:
			par_time = float((puzzle_data as Dictionary).get("par_time_seconds", BASE_ROUND_TIME))

	if gauntlet_manager and gauntlet_manager.has_method("register_clear"):
		# Keep the service authoritative while allowing legacy callers/tests to
		# seed the displayed depth before completing a round.
		gauntlet_manager.set("depth", current_round)
		var clear_result: Dictionary = gauntlet_manager.call("register_clear", par_time)
		if clear_result.is_empty():
			# The service refused the clear (a stopped run, or an empty projection).
			# Falling through would pay the round reward, log the achievement and
			# re-run the same depth forever, because only a non-empty result
			# advances the run. Fail the gauntlet instead of paying out.
			push_warning("[EscapeGauntlet] GauntletManager.register_clear returned an empty result for depth %d; failing the run instead of awarding the round" % current_round)
			_fail_gauntlet()
			return
		current_round = int(gauntlet_manager.get("depth"))
		score = int(gauntlet_manager.get("score"))
		round_max_time = float(gauntlet_manager.get("round_time_limit"))
		time_left = float(gauntlet_manager.get("time_left"))
		pending_clear_preview = {}
	else:
		var bonus: int = 0
		if time_ratio <= 0.5:
			bonus = 2
		elif time_ratio <= 0.75:
			bonus = 1
		max_mistakes += bonus
		var round_score: int = 100
		if current_wave_type == "blitz":
			round_score *= 2
		if current_wave_type == "boss":
			round_score *= 5
		score += round_score + int(maxf(0.0, time_left)) * 10
		current_round += 1

	var game_manager: Node = _get_game_manager()
	if game_manager:
		if current_round == 10:
			game_manager.call("unlock_theme", "Wood")
		elif current_round == 20:
			game_manager.call("unlock_theme", "Marble")
		elif current_round == 30:
			game_manager.call("unlock_theme", "Neon Sci-Fi")
	var save_manager: Node = get_node_or_null("/root/SaveManager")
	if save_manager and is_instance_valid(active_puzzle) and save_manager.has_method("add_shards"):
		var banked_shards: int = int(save_manager.call("add_shards", 100))
		if banked_shards <= 0 and save_manager.has_method("get_persistence_status"):
			# The reward could not be stored, so it is not awarded. Say so
			# instead of letting the next load silently erase it.
			var status: Dictionary = save_manager.call("get_persistence_status")
			push_warning("[EscapeGauntlet] Round reward was not stored (%s); it has not been credited" % str(status.get("last_save_error", "unknown")))
	if save_manager and save_manager.has_method("record_achievement_event"):
		var completed_round: int = maxi(1, current_round - 1)
		var event_type: String = "boss_round_cleared" if current_wave_type == "boss" else "round_cleared"
		save_manager.call("record_achievement_event", {
			"type": event_type,
			"event_id": "%s:%d:%d" % ["daily" if is_daily_challenge else "run", run_seed, completed_round],
			"depth": completed_round,
			"streak": int(gauntlet_manager.get("streak")) if gauntlet_manager else 0,
			"mistakes": int(gauntlet_manager.get("mistakes")) if gauntlet_manager else 0,
		})
	if is_daily_challenge and current_round >= DAILY_CHALLENGE_DEPTH:
		_record_daily_result(true)
		_win_gauntlet()
		return
	_start_round()


func _on_child_game_over() -> void:
	_fail_gauntlet()

func _on_mistake_made(total_mistakes: int) -> void:
	if gauntlet_manager and gauntlet_manager.has_method("register_mistake"):
		gauntlet_manager.call("register_mistake")
		time_left = float(gauntlet_manager.get("time_left"))
	if is_instance_valid(active_puzzle):
		var health_value: Variant = active_puzzle.get("player_hp")
		if health_value != null:
			current_health = int(health_value)
	_update_hud_labels()
	var authoritative_round_mistakes: int = int(gauntlet_manager.get("round_mistakes")) if gauntlet_manager else total_mistakes
	if authoritative_round_mistakes >= max_mistakes or (gauntlet_manager and not bool(gauntlet_manager.get("is_running"))):
		_fail_gauntlet()


func heal_round_mistake() -> void:
	if gauntlet_manager and gauntlet_manager.has_method("refund_round_mistake"):
		gauntlet_manager.call("refund_round_mistake")


func _fail_gauntlet() -> void:
	if is_game_over:
		return
	if gauntlet_manager and gauntlet_manager.has_method("fail_run"):
		gauntlet_manager.call("fail_run", "time_or_mistake")
	if is_daily_challenge:
		_record_daily_result(false)
	_record_run_summary(false)
	is_round_active = false
	is_game_over = true
	is_modal_open = false
	if confirm_dialog:
		confirm_dialog.hide()
	if is_instance_valid(active_puzzle):
		active_puzzle.set("is_puzzle_active", false)
	_set_child_input_enabled(false)
	# The parent HUD is hidden while a round reveal plays. Restore its
	# CanvasLayer before showing the terminal result, exactly like _win_gauntlet:
	# otherwise show() is a no-op from the player's perspective and the Leave
	# button stays unreachable, which is how a mid-reveal failure used to strand
	# touch players on a blank screen.
	_set_parent_hud_visible(true)
	var save_manager: Node = get_node_or_null("/root/SaveManager")
	if save_manager and save_manager.has_method("record_run_result"):
		var best_streak: int = int(gauntlet_manager.get("streak")) if gauntlet_manager else 0
		save_manager.call("record_run_result", current_round, false, best_streak)
	if game_over_title:
		game_over_title.text = "GAUNTLET FAILED"
	if game_over_message:
		game_over_message.text = "Game over\nScore: " + str(score)
	if game_over:
		game_over.show()
		if retry_btn:
			call_deferred("_safe_focus", retry_btn)
	print("[EscapeGauntlet] Gauntlet Failed!")


func _record_run_summary(completed: bool) -> Dictionary:
	var save_manager: Node = get_node_or_null("/root/SaveManager")
	if save_manager == null or not save_manager.has_method("record_run_summary"):
		return {"success": false, "error_code": "NO_SAVE_MANAGER", "message": "Run history is unavailable."}
	var game_manager: Node = _get_game_manager()
	var difficulty: String = str(game_manager.get("selected_difficulty_mode")) if game_manager else "endless"
	var catalog_version: int = GameManagerClass.DAILY_CATALOG_VERSION
	if puzzle_manager != null and puzzle_manager.has_method("get_catalog_version"):
		catalog_version = int(puzzle_manager.call("get_catalog_version"))
	# RunHistoryService defines sequence_fingerprint as the hash of THIS run's
	# puzzle ids. It is not the catalog hash: the two serialize different JSON
	# (array of strings vs array of dictionaries), so they can never match, and
	# supplying the catalog hash made every record_run fail with
	# SEQUENCE_FINGERPRINT_MISMATCH. That silently discarded the entire run
	# history, including puzzle_ids and is_daily.
	var sequence_fingerprint: String = RunHistoryServiceClass.fingerprint_sequence(run_puzzle_ids)
	var summary: Dictionary = {
		"run_id": "%s:%d" % [run_session_token, current_round],
		"seed": run_seed,
		"difficulty": difficulty,
		# Both versions are part of the validated run identity, so they come
		# from the canonical constants rather than literals.
		"ruleset_version": GameManagerClass.DAILY_RULESET_VERSION,
		"catalog_version": catalog_version,
		"depth": maxi(1, run_puzzle_ids.size()),
		"score": maxi(0, score),
		"streak": maxi(0, int(gauntlet_manager.get("streak")) if gauntlet_manager else 0),
		"mistakes": maxi(0, int(gauntlet_manager.get("mistakes")) if gauntlet_manager else 0),
		"completed": completed,
		"puzzle_ids": run_puzzle_ids.duplicate(true),
		"is_daily": is_daily_challenge,
		"completed_at": int(Time.get_unix_time_from_system()),
	}
	if not sequence_fingerprint.is_empty():
		summary["sequence_fingerprint"] = sequence_fingerprint
	if is_daily_challenge and daily_id >= 0 and not daily_date.is_empty():
		# Without these, run history cannot attribute a daily run to its date.
		# Guard the values: a malformed one would make the service reject the
		# whole record, losing the run rather than just the daily attribution.
		summary["daily_id"] = daily_id
		summary["daily_date"] = daily_date
	var record_result: Dictionary = save_manager.call("record_run_summary", summary)
	if not bool(record_result.get("success", false)):
		# A rejected summary means the run is not in the player's history and
		# the share button stays disabled. Say so instead of dropping it.
		push_warning("[EscapeGauntlet] Run history rejected (%s): %s" % [
			str(record_result.get("error_code", "unknown")),
			str(record_result.get("message", "")),
		])
	return record_result


func _record_daily_result(completed: bool) -> Dictionary:
	if _daily_result_recorded or not is_daily_challenge or daily_date.is_empty():
		return {}
	var save_manager: Node = get_node_or_null("/root/SaveManager")
	if save_manager == null or not save_manager.has_method("get_daily_results") or not save_manager.has_method("save_daily_results"):
		return {}
	var service: RefCounted = DailyChallengeServiceClass.new()
	var load_result: Dictionary = service.call("load_local_results", save_manager.call("get_daily_results"))
	if not bool(load_result.get("success", false)):
		# load_local_results is transactional: one malformed stored record
		# disables daily recording for the whole profile. Warn, because silence
		# here is indistinguishable from "nothing was earned".
		push_warning("[EscapeGauntlet] Daily result not recorded: stored results rejected (%s)" % str(load_result.get("error_code", "unknown")))
		return {}
	# Score from the authoritative mistake counter, not the mirrored HP. HP can
	# be restored, so a run that made mistakes could still read as 3 stars, and
	# a 2-star band was unreachable.
	var run_mistakes: int = maxi(0, int(gauntlet_manager.get("mistakes")) if gauntlet_manager else 0)
	var stars: int = 0
	if completed:
		stars = 3 if run_mistakes == 0 else 2 if run_mistakes == 1 else 1
	var completed_depth: int = maxi(1, run_puzzle_ids.size())
	var record: Dictionary = service.call("record_result", daily_date, daily_ruleset_version, daily_catalog_version, {
		"completed": completed,
		"score": score,
		"depth": completed_depth,
		"stars": stars,
		"mistakes": run_mistakes,
	})
	if not bool(record.get("success", false)):
		push_warning("[EscapeGauntlet] Daily result not recorded: service rejected it (%s)" % str(record.get("error_code", "unknown")))
		return {}
	if not bool(save_manager.call("save_daily_results", service.call("get_local_results"))):
		push_warning("[EscapeGauntlet] Daily result not recorded: results could not be stored")
		return {}
	_daily_result_recorded = true
	return record


func _win_gauntlet() -> void:
	if is_game_over:
		return
	var completed_depth: int = maxi(1, run_puzzle_ids.size())
	if is_daily_challenge:
		_record_daily_result(true)
	_record_run_summary(true)
	var save_manager: Node = get_node_or_null("/root/SaveManager")
	if save_manager and save_manager.has_method("record_run_result"):
		save_manager.call("record_run_result", completed_depth, true, int(gauntlet_manager.get("streak")) if gauntlet_manager else 0)
	if save_manager and save_manager.has_method("record_achievement_event"):
		save_manager.call("record_achievement_event", {
			"type": "run_completed",
			"event_id": "%s:%d:complete" % ["daily" if is_daily_challenge else "run", run_seed],
			"depth": completed_depth,
			"streak": int(gauntlet_manager.get("streak")) if gauntlet_manager else 0,
			"mistakes": int(gauntlet_manager.get("mistakes")) if gauntlet_manager else 0,
		})
	is_round_active = false
	is_game_over = true
	is_modal_open = false
	if confirm_dialog:
		confirm_dialog.hide()
	_set_child_input_enabled(false)
	if game_over_title:
		game_over_title.text = "GAUNTLET CLEARED!"
	if game_over_message:
		var final_message: String = "You survived the gauntlet.\nDepth: %d  •  Score: %s" % [completed_depth, _format_score(score)]
		final_message += "\nSeed: %d" % run_seed
		if is_daily_challenge:
			final_message += "\nDaily challenge complete"
		if save_manager and save_manager.has_method("get_latest_run") and save_manager.has_method("create_run_share_token"):
			var latest_run: Dictionary = save_manager.call("get_latest_run")
			if not latest_run.is_empty():
				var final_share: Dictionary = save_manager.call("create_run_share_token", latest_run)
				if bool(final_share.get("success", false)):
					final_message += "\nReplay: " + str(final_share.get("token", ""))
		game_over_message.text = final_message
	# The parent HUD is hidden while a round reveal is playing. Restore its
	# CanvasLayer before showing the terminal result; otherwise show() is a
	# no-op from the player's perspective because an ancestor remains hidden.
	_set_parent_hud_visible(true)
	if game_over:
		game_over.show()
		if retry_btn:
			call_deferred("_safe_focus", retry_btn)


func _format_score(value: int) -> String:
	var digits: String = str(maxi(0, value))
	var modulo: int = digits.length() % 3
	var result: String = ""
	for index in range(digits.length()):
		if index != 0 and index % 3 == modulo:
			result += ","
		result += digits[index]
	return result


func _on_retry_pressed() -> void:
	retry_victory_seed()


func _on_leave_pressed() -> void:
	_switch_mode(GameManagerClass.GameMode.MAIN_MENU)


func retry_victory_seed() -> void:
	var game_manager: Node = _get_game_manager()
	if game_manager == null:
		return
	# Retrying a finished daily must re-issue the daily, not replay the same
	# sequence as a plain endless run under the daily's seed. The daily record
	# itself is not corrupted (the daily guard rejects the non-daily retry), but
	# the daily's identity became a freely grindable non-daily seed.
	if is_daily_challenge and not daily_date.is_empty() and game_manager.has_method("begin_daily_challenge"):
		game_manager.call("begin_daily_challenge")
		return
	var difficulty: String = str(game_manager.get("selected_difficulty_mode")) if game_manager.get("selected_difficulty_mode") != null else "endless"
	if game_manager.has_method("begin_run"):
		game_manager.call("begin_run", difficulty, run_seed)
	else:
		game_manager.set("selected_run_seed", run_seed)
		_switch_mode(GameManagerClass.GameMode.ESCAPE_GAUNTLET)


func start_new_victory_run() -> void:
	var game_manager: Node = _get_game_manager()
	if game_manager and game_manager.has_method("begin_run"):
		var difficulty: String = str(game_manager.get("selected_difficulty_mode")) if game_manager.get("selected_difficulty_mode") != null else "endless"
		game_manager.call("begin_run", difficulty)


func get_victory_context() -> Dictionary:
	var game_manager: Node = _get_game_manager()
	var difficulty: String = str(game_manager.get("selected_difficulty_mode")) if game_manager else "endless"
	var result: Dictionary = pending_clear_preview.duplicate(true)
	result["seed"] = run_seed
	result["difficulty"] = difficulty
	result["round"] = current_round
	result["is_daily"] = is_daily_challenge
	result["daily_id"] = daily_id
	var puzzle_id: String = ""
	if is_instance_valid(active_puzzle):
		var puzzle_data: Variant = active_puzzle.get("custom_puzzle_data")
		if puzzle_data is Dictionary:
			puzzle_id = str((puzzle_data as Dictionary).get("id", ""))
	result["puzzle_id"] = puzzle_id
	return result


func _switch_mode(mode: int) -> void:
	var game_manager: Node = _get_game_manager()
	if game_manager and game_manager.has_method("switch_mode"):
		game_manager.call("switch_mode", mode)


func _get_game_manager() -> Node:
	var scene_tree: SceneTree = get_tree()
	if scene_tree == null or scene_tree.root == null:
		return null
	return scene_tree.root.get_node_or_null("GameManager")


func _apply_responsive_layout() -> void:
	if not is_inside_tree():
		return
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	var insets: Vector4 = _get_safe_area_insets(viewport_size)
	var display_size: Vector2 = _get_display_size()
	var ui_scale: float = _get_ui_scale(viewport_size, display_size)
	var compact: bool = display_size.x < 520.0 or display_size.y < 560.0
	var base_edge: float = (12.0 if compact else 20.0) * ui_scale
	var left_edge: float = insets.x + base_edge
	var right_edge: float = insets.z + base_edge
	var top_edge: float = insets.y + base_edge
	var bottom_edge: float = insets.w + base_edge
	var hud_width: float = (130.0 if compact else 150.0) * ui_scale

	if quit_btn:
		quit_btn.anchor_left = 1.0
		quit_btn.anchor_right = 1.0
		quit_btn.anchor_top = 1.0
		quit_btn.anchor_bottom = 1.0
		var reserved_toolbar_height: float = 172.0
		var child_toolbar: Control = _get_child_toolbar()
		if child_toolbar and child_toolbar.size.y > 0.0:
			reserved_toolbar_height = child_toolbar.size.y
		quit_btn.offset_left = -right_edge - 96.0 * ui_scale
		quit_btn.offset_right = -right_edge
		quit_btn.offset_top = -bottom_edge - reserved_toolbar_height - 8.0 * ui_scale - 48.0 * ui_scale
		quit_btn.offset_bottom = -bottom_edge - reserved_toolbar_height - 8.0 * ui_scale
		quit_btn.custom_minimum_size = Vector2(96.0 * ui_scale, 48.0 * ui_scale)
		quit_btn.focus_mode = Control.FOCUS_ALL
	if round_label:
		round_label.anchor_left = 0.5
		round_label.anchor_right = 0.5
		round_label.anchor_top = 0.0
		round_label.anchor_bottom = 0.0
		var round_width: float = minf(280.0 * ui_scale, maxf(1.0, viewport_size.x - insets.x - insets.z - 24.0 * ui_scale))
		round_label.offset_left = -round_width * 0.5
		round_label.offset_right = round_width * 0.5
		round_label.offset_top = top_edge
		round_label.offset_bottom = round_label.offset_top + 32.0 * ui_scale
		round_label.add_theme_font_size_override("font_size", int((16 if compact else 20) * ui_scale))
	if timer_label:
		timer_label.anchor_left = 1.0
		timer_label.anchor_right = 1.0
		timer_label.anchor_top = 0.0
		timer_label.anchor_bottom = 0.0
		timer_label.offset_left = -right_edge - hud_width
		timer_label.offset_right = -right_edge
		timer_label.offset_top = top_edge + 34.0 * ui_scale
		timer_label.offset_bottom = timer_label.offset_top + 32.0 * ui_scale
		timer_label.add_theme_font_size_override("font_size", int((16 if compact else 20) * ui_scale))
	if health_label:
		health_label.anchor_left = 0.0
		health_label.anchor_right = 0.0
		health_label.anchor_top = 0.0
		health_label.anchor_bottom = 0.0
		health_label.offset_left = left_edge
		health_label.offset_right = left_edge + hud_width
		health_label.offset_top = top_edge + 34.0 * ui_scale
		health_label.offset_bottom = health_label.offset_top + 32.0 * ui_scale
		health_label.add_theme_font_size_override("font_size", int((16 if compact else 20) * ui_scale))
	if score_label:
		score_label.anchor_left = 1.0
		score_label.anchor_right = 1.0
		score_label.anchor_top = 0.0
		score_label.anchor_bottom = 0.0
		score_label.offset_left = -right_edge - hud_width
		score_label.offset_right = -right_edge
		score_label.offset_top = top_edge + 68.0 * ui_scale
		score_label.offset_bottom = score_label.offset_top + 32.0 * ui_scale
		score_label.add_theme_font_size_override("font_size", int((16 if compact else 20) * ui_scale))
	if bank_label:
		bank_label.anchor_left = 1.0
		bank_label.anchor_right = 1.0
		bank_label.anchor_top = 0.0
		bank_label.anchor_bottom = 0.0
		bank_label.offset_left = -right_edge - hud_width
		bank_label.offset_right = -right_edge
		bank_label.offset_top = top_edge + 102.0 * ui_scale
		bank_label.offset_bottom = bank_label.offset_top + 32.0 * ui_scale
		bank_label.add_theme_font_size_override("font_size", int((16 if compact else 20) * ui_scale))

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
		var confirm_width: float = minf(340.0 * ui_scale, maxf(1.0, viewport_size.x - insets.x - insets.z - 24.0 * ui_scale))
		var preferred_confirm_height: float = (180.0 if compact else 200.0) * ui_scale
		var confirm_height: float = minf(preferred_confirm_height, maxf(1.0, viewport_size.y - insets.y - insets.w - 24.0 * ui_scale))
		confirm_card.offset_left = -confirm_width * 0.5
		confirm_card.offset_right = confirm_width * 0.5
		confirm_card.offset_top = -confirm_height * 0.5
		confirm_card.offset_bottom = confirm_height * 0.5
		confirm_content.offset_left = -confirm_width * 0.5 + 20.0 * ui_scale
		confirm_content.offset_right = confirm_width * 0.5 - 20.0 * ui_scale
		confirm_content.offset_top = -confirm_height * 0.5 + 16.0 * ui_scale
		confirm_content.offset_bottom = confirm_height * 0.5 - 16.0 * ui_scale
	var confirm_button_width: float = (80.0 if display_size.x < 300.0 else 90.0 if compact else 110.0) * ui_scale
	if yes_btn:
		yes_btn.custom_minimum_size = Vector2(confirm_button_width, 48.0 * ui_scale)
	if no_btn:
		no_btn.custom_minimum_size = Vector2(confirm_button_width, 48.0 * ui_scale)
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
		var game_over_width: float = minf(380.0 * ui_scale, maxf(1.0, viewport_size.x - insets.x - insets.z - 24.0 * ui_scale))
		var preferred_game_over_height: float = (260.0 if compact else 300.0) * ui_scale
		var game_over_height: float = minf(preferred_game_over_height, maxf(1.0, viewport_size.y - insets.y - insets.w - 24.0 * ui_scale))
		game_over_card.offset_left = -game_over_width * 0.5
		game_over_card.offset_right = game_over_width * 0.5
		game_over_card.offset_top = -game_over_height * 0.5
		game_over_card.offset_bottom = game_over_height * 0.5
		game_over_content.offset_left = -game_over_width * 0.5 + 20.0 * ui_scale
		game_over_content.offset_right = game_over_width * 0.5 - 20.0 * ui_scale
		game_over_content.offset_top = -game_over_height * 0.5 + 16.0 * ui_scale
		game_over_content.offset_bottom = game_over_height * 0.5 - 16.0 * ui_scale
	if game_over_buttons:
		game_over_buttons.columns = 1 if display_size.x < 300.0 else 2
		for child in game_over_buttons.get_children():
			if child is Button:
				var game_over_button: Button = child as Button
				game_over_button.custom_minimum_size = Vector2(0.0, 48.0 * ui_scale)
				game_over_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				game_over_button.focus_mode = Control.FOCUS_ALL


func _get_display_size() -> Vector2:
	var window_size := Vector2(DisplayServer.window_get_size())
	return window_size if window_size.x > 0.0 and window_size.y > 0.0 else get_viewport().get_visible_rect().size


func _get_ui_scale(viewport_size: Vector2, display_size: Vector2) -> float:
	if display_size.x <= 0.0 or display_size.y <= 0.0:
		return 1.0
	return clampf(maxf(viewport_size.x / display_size.x, viewport_size.y / display_size.y), 1.0, 4.0)


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
