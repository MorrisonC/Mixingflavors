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

	var easy_btn = find_child("EasyButton", true, false)
	if easy_btn:
		easy_btn.pressed.connect(func(): _on_difficulty_selected("easy"))
	var medium_btn = find_child("MediumButton", true, false)
	if medium_btn:
		medium_btn.pressed.connect(func(): _on_difficulty_selected("medium"))
	var hard_btn = find_child("HardButton", true, false)
	if hard_btn:
		hard_btn.pressed.connect(func(): _on_difficulty_selected("hard"))
	var boss_btn = find_child("BossButton", true, false)
	if boss_btn:
		boss_btn.pressed.connect(func(): _on_difficulty_selected("boss"))
	var endless_btn = find_child("EndlessButton", true, false)
	if endless_btn:
		endless_btn.pressed.connect(func(): _on_difficulty_selected("endless"))
	var cancel_btn = find_child("CloseDifficultyButton", true, false)
	if cancel_btn:
		cancel_btn.pressed.connect(_hide_difficulty_modal)

func _hide_difficulty_modal() -> void:
	var difficulty_modal = get_node_or_null("DifficultyModal")
	if difficulty_modal:
		difficulty_modal.visible = false
	var title = get_node_or_null("Title")
	if title: title.visible = true
	var vbox = get_node_or_null("VBoxContainer")
	if vbox: vbox.visible = true

func _on_play_pressed() -> void:
	var difficulty_modal = get_node_or_null("DifficultyModal")
	if difficulty_modal:
		difficulty_modal.visible = true
		var title = get_node_or_null("Title")
		if title: title.visible = false
		var vbox = get_node_or_null("VBoxContainer")
		if vbox: vbox.visible = false
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
	_hide_difficulty_modal()
	get_node("/root/GameManager").selected_difficulty_mode = mode
	get_node("/root/GameManager").switch_mode(GameManagerClass.GameMode.ESCAPE_GAUNTLET)
