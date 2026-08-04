with open("scripts/GridManager.gd", "r") as f:
    content = f.read()

# Fix the duplicate signal connections causing "Signal 'pressed' is already connected..." errors.
orig = """	if chisel_btn:
		chisel_btn.pressed.connect(_on_chisel_mode_selected)
	var mark_btn = get_node_or_null("CanvasLayer/Control/MarginContainer/VBoxContainer/HBoxContainer/MarkButton")
	if mark_btn:
		mark_btn.pressed.connect(_on_mark_mode_selected)
	var undo_btn = get_node_or_null("CanvasLayer/Control/MarginContainer/VBoxContainer/HBoxContainer/UndoButton")
	if undo_btn:
		undo_btn.pressed.connect(func(): if self.has_method("undo_last_action"): self.call("undo_last_action"))"""

new_code = """	if chisel_btn and not chisel_btn.pressed.is_connected(_on_chisel_mode_selected):
		chisel_btn.pressed.connect(_on_chisel_mode_selected)
	var mark_btn = get_node_or_null("CanvasLayer/Control/MarginContainer/VBoxContainer/HBoxContainer/MarkButton")
	if mark_btn and not mark_btn.pressed.is_connected(_on_mark_mode_selected):
		mark_btn.pressed.connect(_on_mark_mode_selected)
	var undo_btn = get_node_or_null("CanvasLayer/Control/MarginContainer/VBoxContainer/HBoxContainer/UndoButton")
	if undo_btn and not undo_btn.pressed.is_connected(self.call.bind("undo_last_action")):
		undo_btn.pressed.connect(func(): if self.has_method("undo_last_action"): self.call("undo_last_action"))"""

content = content.replace(orig, new_code)

with open("scripts/GridManager.gd", "w") as f:
    f.write(content)
