extends Node3D
const GameManagerClass = preload("res://scripts/GameManager.gd")
const BRIDGE_SCRIPT_PATH: String = "res://scripts/test_bridge.gd"

@onready var ui_container: Control = $CanvasLayer/UIContainer
@onready var sub_viewport_container: SubViewportContainer = $SubViewportContainer
@onready var sub_viewport: SubViewport = $SubViewportContainer/SubViewport

var active_mode_instance: Node = null

func _ready() -> void:
	get_node("/root/GameManager").connect("mode_changed", Callable(self, "_on_mode_changed"))
	_install_debug_bridge_if_requested()
	# Boot into MainMenu automatically on startup
	_load_mode_scene(GameManagerClass.GameMode.MAIN_MENU)


func _install_debug_bridge_if_requested() -> void:
	if not (OS.is_debug_build() or OS.has_feature("e2e")):
		return
	# The Android presets exclude the bridge from the pack, so a debug Android
	# boot would otherwise log a resource-not-found error on every start.
	if not ResourceLoader.exists(BRIDGE_SCRIPT_PATH):
		return
	var bridge_script: Script = load(BRIDGE_SCRIPT_PATH) as Script
	if bridge_script == null:
		return
	var bridge: Node = bridge_script.new() as Node
	if bridge:
		bridge.name = "TestBridge"
		add_child(bridge)

func _on_mode_changed(new_mode: int) -> void:
	_load_mode_scene(new_mode)

func _load_mode_scene(mode: int) -> void:
	# Remove the old mode from the tree before adding the replacement. This
	# prevents one-frame duplicate headers and stale TestBridge lookups.
	if is_instance_valid(active_mode_instance):
		var previous_mode: Node = active_mode_instance
		active_mode_instance = null
		previous_mode.get_parent().remove_child(previous_mode)
		previous_mode.queue_free()

	var scene_path: String = GameManagerClass.MODE_SCENES.get(mode, "")
	if scene_path == "" or not ResourceLoader.exists(scene_path):
		push_error("[Main] Failed to load scene path: " + scene_path)
		return

	var scene_resource = load(scene_path)
	if scene_resource == null:
		push_error("[Main] Could not instantiate scene at: " + scene_path)
		return

	active_mode_instance = scene_resource.instantiate()

	# Route 2D UI nodes to Canvas UI, and 3D spatial nodes to SubViewport.
	# Do not keep an empty WebGL target rendering behind menus/compendium;
	# this is a meaningful mobile battery and startup win.
	var is_2d_mode: bool = active_mode_instance is Control
	if sub_viewport_container:
		sub_viewport_container.visible = not is_2d_mode
	if sub_viewport:
		sub_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED if is_2d_mode else SubViewport.UPDATE_ALWAYS
	if is_2d_mode:
		ui_container.add_child(active_mode_instance)
	else:
		sub_viewport.add_child(active_mode_instance)
