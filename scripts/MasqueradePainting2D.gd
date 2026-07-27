extends Control

var line_points: PackedVector2Array = []
var base_anchors: Array = [Vector2(200, 200), Vector2(400, 200), Vector2(300, 400)]
var hidden_anchors: Array = [Vector2(250, 150), Vector2(350, 350)] # Revealed by high Perception

@onready var info_label: Label = $InfoLabel

func _ready() -> void:
	var perception = GameManager.get_stat("perception")
	info_label.text = "Masquerade Painting Mode\nPerception Level: %d" % perception

	if perception > 1:
		info_label.text += " (Hidden Canvas Anchors Revealed!)"

func _draw() -> void:
	# Draw Base Anchors
	for pt in base_anchors:
		draw_circle(pt, 10.0, Color.BLUE)

	# Draw Hidden Anchors if Perception > 1
	if GameManager.get_stat("perception") > 1:
		for h_pt in hidden_anchors:
			draw_circle(h_pt, 12.0, Color.GOLD)

	# Draw user lines
	if line_points.size() > 1:
		draw_polyline(line_points, Color.GREEN, 3.0)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		line_points.append(event.position)
		queue_redraw()

func _on_back_button_pressed() -> void:
	GameManager.switch_mode(GameManager.GameMode.LONE_WOLF_NARRATIVE)
