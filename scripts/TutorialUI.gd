extends CanvasLayer
class_name TutorialUI

@onready var banner_label: Label = $MarginContainer/VBoxContainer/BannerPanel/MarginContainer/BannerLabel
@onready var skip_button: Button = $MarginContainer/VBoxContainer/TopRow/SkipButton
@onready var tool_highlight: ColorRect = $ToolHighlight
@onready var slicer_highlight: ColorRect = $SlicerHighlight

var tutorial_manager: TutorialManager

func _ready() -> void:
	if skip_button:
		skip_button.pressed.connect(_on_skip_pressed)

	# Setup pulsing highlights
	_setup_pulsing(tool_highlight)
	_setup_pulsing(slicer_highlight)

	if tool_highlight:
		tool_highlight.hide()
	if slicer_highlight:
		slicer_highlight.hide()

func _setup_pulsing(node: Node) -> void:
	if not node: return
	var tween = create_tween().set_loops()
	tween.tween_property(node, "modulate:a", 0.2, 0.8).set_trans(Tween.TRANS_SINE)
	tween.tween_property(node, "modulate:a", 0.6, 0.8).set_trans(Tween.TRANS_SINE)

func setup(manager: TutorialManager) -> void:
	tutorial_manager = manager
	tutorial_manager.hud_banner_label = banner_label
	tutorial_manager.tool_highlight_rect = tool_highlight
	tutorial_manager.slicer_slider_highlight = slicer_highlight

	tutorial_manager.step_advanced.connect(_on_step_advanced)

	# Initialize first step
	_on_step_advanced(int(tutorial_manager.current_step), tutorial_manager.step_instructions.get(tutorial_manager.current_step, ""))

func _on_step_advanced(step_index: int, instruction: String) -> void:
	if banner_label:
		banner_label.text = instruction
		# Animate the banner
		banner_label.pivot_offset = banner_label.size / 2
		var tween = create_tween()
		tween.tween_property(banner_label, "scale", Vector2(1.1, 1.1), 0.2).set_trans(Tween.TRANS_SINE)
		tween.tween_property(banner_label, "scale", Vector2(1.0, 1.0), 0.2).set_trans(Tween.TRANS_SINE)

		# Show completion text if not first step
		if step_index > 0:
			_show_floating_text("Great job!")

func _show_floating_text(text: String) -> void:
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 32)
	label.add_theme_color_override("font_color", Color.YELLOW)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)

	add_child(label)

	var viewport_size = get_viewport().get_visible_rect().size
	label.position = Vector2(viewport_size.x / 2.0 - 50, viewport_size.y / 2.0)

	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 100, 1.0)
	tween.tween_property(label, "modulate:a", 0.0, 1.0)
	tween.chain().tween_callback(label.queue_free)

func _on_skip_pressed() -> void:
	if is_instance_valid(GameManager):
		GameManager.tutorial_completed = true
		GameManager.save_settings()
		GameManager.switch_mode(GameManager.GameMode.PUZZLE_SELECTION)
