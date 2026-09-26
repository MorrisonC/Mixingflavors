extends Node

const DailyChallengeServiceClass = preload("res://scripts/DailyChallengeService.gd")
const PuzzleManagerClass = preload("res://scripts/PuzzleManager.gd")
## The daily identity hashes (date, ruleset, catalog). Deriving the versions
## from PuzzleManager keeps the identity in step with the catalog the selector
## actually reads, instead of relying on two constants happening to be equal.
const DAILY_RULESET_VERSION: int = PuzzleManagerClass.RULESET_VERSION
const DAILY_CATALOG_VERSION: int = PuzzleManagerClass.CATALOG_VERSION

# Signal emitted when switching game modes or updating stats
signal mode_changed(new_mode_id)
signal stat_changed(stat_name, new_value)

# GameMode Identifiers
enum GameMode {
	MAIN_MENU = 0,
	VOXEL_LOGIC = 1,
	ESCAPE_GAUNTLET = 2,
	PUZZLE_SELECTION = 4,
	ARCHIVE = 6,
}

signal theme_changed(is_valentine)

var _valentine_theme_active: bool = false
var tutorial_completed: bool = false
var mode_payload: Dictionary = {}

# Core RPG Stats
var stats: Dictionary = {
	"perception": 2,
	"health": 100,
	"endurance": 100,
	"alchemy_discipline": 2,
	"lore_discipline": 1
}

# Cross-Mechanic Data Buffer (Passes state between modes)
var active_voxel_template: Array = []
var discovered_anchors: Array = []
var current_mode: GameMode = GameMode.MAIN_MENU

# Meta Progression
var unlocked_themes: Array = ["Classic"]
var trophy_gallery: Array = []

func unlock_theme(theme_name: String) -> void:
	if not unlocked_themes.has(theme_name):
		unlocked_themes.append(theme_name)
		var save_manager: Node = get_node_or_null("/root/SaveManager")
		if save_manager and save_manager.has_method("unlock_theme"):
			save_manager.call("unlock_theme", theme_name)
		print("[MetaProgression] Unlocked new theme: ", theme_name)

func add_trophy(puzzle_name: String) -> void:
	if not trophy_gallery.has(puzzle_name):
		trophy_gallery.append(puzzle_name)
		var save_manager: Node = get_node_or_null("/root/SaveManager")
		if save_manager and save_manager.has_method("add_trophy"):
			save_manager.call("add_trophy", puzzle_name)
		print("[MetaProgression] Added trophy to gallery: ", puzzle_name)
var selected_difficulty_mode: String = "medium"
var selected_run_seed: int = 0


# Scene File Paths (Ensure case-sensitivity matches your project files)
const MODE_SCENES: Dictionary = {
	GameMode.MAIN_MENU: "res://scenes/MainMenu.tscn",
	GameMode.VOXEL_LOGIC: "res://scenes/VoxelLogic.tscn",
	GameMode.ESCAPE_GAUNTLET: "res://scenes/EscapeGauntlet.tscn",
	GameMode.PUZZLE_SELECTION: "res://scenes/PuzzleSelection.tscn",
	GameMode.ARCHIVE: "res://scenes/ArchiveScreen.tscn"
}

func _ready() -> void:
	# SaveManager is autoloaded after GameManager, so it does not exist yet
	# during this node's _ready(). Defer the mirror so the reads actually land
	# instead of silently leaving the defaults in place all session.
	call_deferred("load_settings")
	print("[GameManager] Initialized successfully. Current Mode: MainMenu")

func load_settings() -> void:
	var save_manager: Node = get_node_or_null("/root/SaveManager")
	if save_manager and save_manager.has_method("get_settings"):
		var settings: Dictionary = save_manager.call("get_settings")
		tutorial_completed = bool(settings.get("tutorial_completed", false))
	if save_manager and save_manager.has_method("get_themes"):
		var saved_themes: Array = save_manager.call("get_themes")
		if not saved_themes.is_empty():
			unlocked_themes = saved_themes.duplicate()
	if save_manager and save_manager.has_method("get_trophies"):
		trophy_gallery = save_manager.call("get_trophies").duplicate()

func save_settings() -> void:
	var save_manager: Node = get_node_or_null("/root/SaveManager")
	if save_manager and save_manager.has_method("set_setting"):
		save_manager.call("set_setting", "tutorial_completed", tutorial_completed)

func set_stat(stat_name: String, value: int) -> void:
	if stats.has(stat_name):
		stats[stat_name] = value
		emit_signal("stat_changed", stat_name, value)
		print("[GameManager] Stat updated: ", stat_name, " = ", value)

func get_stat(stat_name: String) -> int:
	return stats.get(stat_name, 0)

static func is_valentine_theme() -> bool:
	var gm = Engine.get_main_loop().root.get_node_or_null("GameManager")
	if gm:
		return gm._valentine_theme_active
	return false

func set_valentine_theme(active: bool) -> void:
	if _valentine_theme_active != active:
		_valentine_theme_active = active
		emit_signal("theme_changed", active)

# Main Scene-Switching Logic
func begin_run(difficulty: String, requested_seed: int = -1) -> int:
	var normalized_difficulty: String = difficulty.strip_edges().to_lower()
	if not (normalized_difficulty in ["easy", "medium", "hard", "endless"]):
		normalized_difficulty = "endless"
	var run_seed: int = requested_seed
	if run_seed < 0:
		run_seed = int(Time.get_unix_time_from_system()) & 0x7fffffff
	selected_difficulty_mode = normalized_difficulty
	selected_run_seed = run_seed
	switch_mode(GameMode.ESCAPE_GAUNTLET, {
		"difficulty": normalized_difficulty,
		"run_seed": run_seed,
	})
	return run_seed


func retry_seed(seed_value: int, difficulty: String = "endless") -> int:
	return begin_run(difficulty, seed_value)


func new_random_run(difficulty: String = "endless") -> int:
	return begin_run(difficulty)


func get_utc_date_string() -> String:
	var utc: Dictionary = Time.get_datetime_dict_from_system(true)
	return "%04d-%02d-%02d" % [int(utc.get("year", 1970)), int(utc.get("month", 1)), int(utc.get("day", 1))]


func begin_daily_challenge() -> Dictionary:
	var service: RefCounted = DailyChallengeServiceClass.new()
	var identity: Dictionary = service.call("derive_daily", get_utc_date_string(), DAILY_RULESET_VERSION, DAILY_CATALOG_VERSION)
	if not bool(identity.get("success", false)):
		return identity
	var run_seed: int = int(identity.get("seed", 0))
	selected_difficulty_mode = "endless"
	selected_run_seed = run_seed
	switch_mode(GameMode.ESCAPE_GAUNTLET, {
		"difficulty": "endless",
		"run_seed": run_seed,
		"daily_challenge": true,
		"daily_id": int(identity.get("daily_id", 0)),
		"daily_date": str(identity.get("utc_date", get_utc_date_string())),
		"daily_ruleset_version": DAILY_RULESET_VERSION,
		"daily_catalog_version": DAILY_CATALOG_VERSION,
	})
	return identity


func switch_mode(target_mode: GameMode, payload: Dictionary = {}) -> void:
	current_mode = target_mode
	mode_payload = payload.duplicate(true)

	if payload.has("difficulty"):
		var requested_difficulty: String = str(payload["difficulty"]).to_lower()
		if requested_difficulty in ["easy", "medium", "hard", "endless"]:
			selected_difficulty_mode = requested_difficulty
	if payload.has("run_seed"):
		selected_run_seed = int(payload["run_seed"])

	# Process cross-mechanic payload if passed
	if payload.has("voxel_template"):
		active_voxel_template = payload["voxel_template"]
	if payload.has("anchors"):
		discovered_anchors = payload["anchors"]

	emit_signal("mode_changed", target_mode)
	print("[GameManager] Switched to mode: ", target_mode)
