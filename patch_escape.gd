extends RefCounted

func apply_patch(file_path: String):
	var file = FileAccess.open(file_path, FileAccess.READ)
	var content = file.get_as_text()
	file.close()

	var new_content = content.replace("await get_tree().create_timer(3.0).timeout\n\tget_node(\"/root/GameManager\").switch_mode(GameManagerClass.GameMode.MAIN_MENU)", """
	var retry_btn = Button.new()
	retry_btn.text = "Retry"
	retry_btn.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	retry_btn.position.y += 100
	retry_btn.position.x -= 150
	retry_btn.custom_minimum_size = Vector2(100, 50)
	retry_btn.add_theme_font_size_override("font_size", 24)
	retry_btn.pressed.connect(func():
		get_node("/root/GameManager").switch_mode(GameManagerClass.GameMode.ESCAPE_GAUNTLET)
	)
	$CanvasLayer/UI.add_child(retry_btn)

	var leave_btn = Button.new()
	leave_btn.text = "Leave"
	leave_btn.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	leave_btn.position.y += 100
	leave_btn.position.x += 50
	leave_btn.custom_minimum_size = Vector2(100, 50)
	leave_btn.add_theme_font_size_override("font_size", 24)
	leave_btn.pressed.connect(func():
		get_node("/root/GameManager").switch_mode(GameManagerClass.GameMode.MAIN_MENU)
	)
	$CanvasLayer/UI.add_child(leave_btn)
""")

	file = FileAccess.open(file_path, FileAccess.WRITE)
	file.store_string(new_content)
	file.close()
