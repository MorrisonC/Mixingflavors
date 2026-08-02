extends Control

const GameManagerClass = preload("res://scripts/GameManager.gd")

@onready var play_button: Button = $VBoxContainer/PlayButton
@onready var editor_button: Button = $VBoxContainer/EditorButton
@onready var settings_button: Button = $VBoxContainer/SettingsButton

func _ready() -> void:
	play_button.pressed.connect(_on_play_pressed)
	editor_button.pressed.connect(_on_editor_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	
	var select_btn = get_node_or_null("VBoxContainer/SelectButton")
	if select_btn:
		select_btn.pressed.connect(_on_select_pressed)
	var editor_btn = get_node_or_null("VBoxContainer/EditorButton")
	if editor_btn:
		editor_btn.queue_free()

	var title = get_node_or_null("Title")
	if title:
		title.pivot_offset = title.size / 2
		var tween = create_tween().set_loops()
		tween.tween_property(title, "scale", Vector2(1.05, 1.05), 1.0).set_trans(Tween.TRANS_SINE)
		tween.tween_property(title, "scale", Vector2(1.0, 1.0), 1.0).set_trans(Tween.TRANS_SINE)

	var easy_btn = get_node_or_null("DifficultyModal/VBoxContainer/EasyButton")
	if easy_btn:
		easy_btn.pressed.connect(func(): _on_difficulty_selected("easy"))
	var medium_btn = get_node_or_null("DifficultyModal/VBoxContainer/MediumButton")
	if medium_btn:
		medium_btn.pressed.connect(func(): _on_difficulty_selected("medium"))
	var hard_btn = get_node_or_null("DifficultyModal/VBoxContainer/HardButton")
	if hard_btn:
		hard_btn.pressed.connect(func(): _on_difficulty_selected("hard"))
	var endless_btn = get_node_or_null("DifficultyModal/VBoxContainer/EndlessButton")
	if endless_btn:
		endless_btn.pressed.connect(func(): _on_difficulty_selected("endless"))
	var cancel_btn = get_node_or_null("DifficultyModal/VBoxContainer/CloseDifficultyButton")
	if cancel_btn:
		cancel_btn.pressed.connect(func(): get_node("DifficultyModal").visible = false)

func _on_play_pressed() -> void:
	var difficulty_modal = get_node_or_null("DifficultyModal")
	if difficulty_modal:
		difficulty_modal.visible = true
	else:
		get_node("/root/GameManager").switch_mode(GameManagerClass.GameMode.ESCAPE_GAUNTLET)

func _on_select_pressed() -> void:
	get_node("/root/GameManager").switch_mode(GameManagerClass.GameMode.PUZZLE_SELECTION)

func _on_editor_pressed() -> void:
	get_node("/root/GameManager").switch_mode(GameManagerClass.GameMode.PUZZLE_EDITOR)

func _on_settings_pressed() -> void:
	# Show settings menu
	var settings_menu = get_node_or_null("SettingsPanel")
	if settings_menu:
		settings_menu.show()

func _on_difficulty_selected(mode: String) -> void:
	var difficulty_modal = get_node_or_null("DifficultyModal")
	if difficulty_modal:
		difficulty_modal.visible = false
	get_node("/root/GameManager").selected_difficulty_mode = mode
	get_node("/root/GameManager").switch_mode(GameManagerClass.GameMode.ESCAPE_GAUNTLET)
