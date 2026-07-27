extends Control
const GameManagerClass = preload("res://scripts/GameManager.gd")

@onready var narrative_text: RichTextLabel = $VBoxContainer/NarrativeText
@onready var stats_display: Label = $VBoxContainer/StatsLabel
@onready var choices_container: VBoxContainer = $VBoxContainer/ChoicesContainer

func _ready() -> void:
	_update_stats_ui()
	_render_intro_story()

func _update_stats_ui() -> void:
	stats_display.text = "Perception: %d | Lore: %d | Health: %d | Alchemy: %d" % [
		get_node("/root/GameManager").get_stat("perception"),
		get_node("/root/GameManager").get_stat("lore_discipline"),
		get_node("/root/GameManager").get_stat("health"),
		get_node("/root/GameManager").get_stat("alchemy_discipline")
	]

func _render_intro_story() -> void:
	narrative_text.text = "[b]Act I: The Sigil Discovery[/b]\n\n" + \
		"You stand before the old stone archway. Ancient runes flicker slightly in the dark. " + \
		"A complex 3D sigil blocks the doorway, requiring focused alchemy and chiseling to stabilize."

	_clear_choices()

	_add_choice("Investigate 3D Voxel Sigil (Enter Picross3D)", func():
		get_node("/root/GameManager").switch_mode(GameManagerClass.GameMode.PICROSS_3D)
	)

	if get_node("/root/GameManager").get_stat("perception") > 1:
		_add_choice("[Perception] Inspect Canvas Patterns (Enter Masquerade Painting)", func():
			get_node("/root/GameManager").switch_mode(GameManagerClass.GameMode.MASQUERADE_PAINTING)
		)

func _add_choice(button_text: String, callback: Callable) -> void:
	var btn = Button.new()
	btn.text = button_text
	btn.connect("pressed", callback)
	choices_container.add_child(btn)

func _clear_choices() -> void:
	for child in choices_container.get_children():
		child.queue_free()
