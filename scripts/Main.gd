extends Node3D
const GameManagerClass = preload("res://scripts/GameManager.gd")

@onready var ui_container: Control = $CanvasLayer/UIContainer
@onready var sub_viewport: SubViewport = $SubViewportContainer/SubViewport

var active_mode_instance: Node = null

func _ready() -> void:
	get_node("/root/GameManager").connect("mode_changed", Callable(self, "_on_mode_changed"))
	# Boot into MainMenu automatically on startup
	_load_mode_scene(GameManagerClass.GameMode.MAIN_MENU)

func _on_mode_changed(new_mode: int) -> void:
	_load_mode_scene(new_mode)

func _load_mode_scene(mode: int) -> void:
	# Clean up active node
	if is_instance_valid(active_mode_instance):
		active_mode_instance.queue_free()
		active_mode_instance = null

	var scene_path: String = GameManagerClass.MODE_SCENES.get(mode, "")
	if scene_path == "" or not ResourceLoader.exists(scene_path):
		push_error("[Main] Failed to load scene path: " + scene_path)
		return

	var scene_resource = load(scene_path)
	if scene_resource == null:
		push_error("[Main] Could not instantiate scene at: " + scene_path)
		return

	active_mode_instance = scene_resource.instantiate()

	# Route 2D UI nodes to Canvas UI, and 3D spatial nodes to SubViewport
	if active_mode_instance is Control:
		ui_container.add_child(active_mode_instance)
	else:
		sub_viewport.add_child(active_mode_instance)

		# Workaround for CanvasLayers in 3D views failing to composite/render
		# If the loaded scene has a CanvasLayer child (like EscapeGauntlet HUD), reparent it to Main's CanvasLayer
		for child in active_mode_instance.get_children():
			if child is CanvasLayer:
				active_mode_instance.remove_child(child)
				ui_container.add_child(child)
