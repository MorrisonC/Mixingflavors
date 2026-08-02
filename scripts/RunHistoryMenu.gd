extends Control

@onready var container_hbox: HBoxContainer = $CanvasLayer/Panel/MarginContainer/MainLayout
@onready var mobile_tabs: TabContainer = $CanvasLayer/Panel/MarginContainer/MobileTabs
@onready var close_btn: Button = $CanvasLayer/Panel/CloseButton

# Desktop layouts
@onready var stats_panel_desktop: VBoxContainer = $CanvasLayer/Panel/MarginContainer/MainLayout/StatsPanel
@onready var history_panel_desktop: VBoxContainer = $CanvasLayer/Panel/MarginContainer/MainLayout/HistoryPanel

# Mobile layout wrappers
@onready var stats_tab: MarginContainer = $CanvasLayer/Panel/MarginContainer/MobileTabs/Stats
@onready var history_tab: MarginContainer = $CanvasLayer/Panel/MarginContainer/MobileTabs/History

# Actual UI components to be reparented
@onready var stats_content: VBoxContainer = $CanvasLayer/Panel/MarginContainer/MainLayout/StatsPanel/StatsContent
@onready var history_content: VBoxContainer = $CanvasLayer/Panel/MarginContainer/MainLayout/HistoryPanel/HistoryContent

@onready var total_runs_val: Label = stats_content.get_node("GridContainer/TotalRunsVal")
@onready var clear_rate_val: Label = stats_content.get_node("GridContainer/ClearRateVal")
@onready var avg_time_val: Label = stats_content.get_node("GridContainer/AvgTimeVal")
@onready var fastest_time_val: Label = stats_content.get_node("GridContainer/FastestTimeVal")

@onready var bar_easy: ColorRect = stats_content.get_node("ProgressBarContainer/Segments/Easy")
@onready var bar_medium: ColorRect = stats_content.get_node("ProgressBarContainer/Segments/Medium")
@onready var bar_hard: ColorRect = stats_content.get_node("ProgressBarContainer/Segments/Hard")

@onready var runs_list: VBoxContainer = history_content.get_node("ScrollContainer/RunsList")
@onready var filter_all: Button = history_content.get_node("Filters/BtnAll")
@onready var filter_easy: Button = history_content.get_node("Filters/BtnEasy")
@onready var filter_medium: Button = history_content.get_node("Filters/BtnMedium")
@onready var filter_hard: Button = history_content.get_node("Filters/BtnHard")
@onready var filter_endless: Button = history_content.get_node("Filters/BtnEndless")

var current_filter: String = "all"
var all_runs: Array = []

func _ready() -> void:
	close_btn.pressed.connect(func(): queue_free())

	filter_all.pressed.connect(func(): _set_filter("all"))
	filter_easy.pressed.connect(func(): _set_filter("easy"))
	filter_medium.pressed.connect(func(): _set_filter("medium"))
	filter_hard.pressed.connect(func(): _set_filter("hard"))
	filter_endless.pressed.connect(func(): _set_filter("endless"))

	get_viewport().size_changed.connect(_on_resized)

	_load_data()
	_update_ui()
	_on_resized()

func _load_data() -> void:
	if get_node_or_null("/root/RunHistoryManager"):
		all_runs = get_node("/root/RunHistoryManager").get_all_runs()

		# Reverse array so newest is first
		var reversed = []
		for i in range(all_runs.size() - 1, -1, -1):
			reversed.append(all_runs[i])
		all_runs = reversed

func _update_ui() -> void:
	_update_stats()
	_populate_runs()

func _update_stats() -> void:
	if not get_node_or_null("/root/RunHistoryManager"): return

	var stats = get_node("/root/RunHistoryManager").get_aggregate_stats()
	total_runs_val.text = str(stats["total_runs"])
	clear_rate_val.text = str(round(stats["clear_rate"] * 100)) + "%"
	avg_time_val.text = _format_time(stats["avg_run_time"])
	fastest_time_val.text = _format_time(stats["fastest_run_time"])

	var total = stats["total_puzzles_by_tier"]["easy"] + stats["total_puzzles_by_tier"]["medium"] + stats["total_puzzles_by_tier"]["hard"] + stats["total_puzzles_by_tier"]["boss"]

	if total > 0:
		var easy_ratio = float(stats["total_puzzles_by_tier"]["easy"]) / total
		var med_ratio = float(stats["total_puzzles_by_tier"]["medium"]) / total
		var hard_ratio = float(stats["total_puzzles_by_tier"]["hard"] + stats["total_puzzles_by_tier"]["boss"]) / total

		bar_easy.size_flags_stretch_ratio = easy_ratio
		bar_medium.size_flags_stretch_ratio = med_ratio
		bar_hard.size_flags_stretch_ratio = hard_ratio

		bar_easy.visible = easy_ratio > 0
		bar_medium.visible = med_ratio > 0
		bar_hard.visible = hard_ratio > 0
	else:
		bar_easy.size_flags_stretch_ratio = 1
		bar_medium.visible = false
		bar_hard.visible = false

func _populate_runs() -> void:
	for child in runs_list.get_children():
		child.queue_free()

	for run in all_runs:
		if current_filter != "all" and run.get("mode", "") != current_filter:
			continue

		var card = _create_run_card(run)
		runs_list.add_child(card)

	# Update filter button colors
	var normal = Color(0.9, 0.9, 0.9)
	var active = Color(1.0, 0.5, 0.5)

	filter_all.modulate = active if current_filter == "all" else normal
	filter_easy.modulate = active if current_filter == "easy" else normal
	filter_medium.modulate = active if current_filter == "medium" else normal
	filter_hard.modulate = active if current_filter == "hard" else normal
	filter_endless.modulate = active if current_filter == "endless" else normal

func _set_filter(f: String) -> void:
	current_filter = f
	_populate_runs()

func _create_run_card(run: Dictionary) -> Control:
	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.2, 0.2, 0.8)
	style.corner_radius_top_left = 5
	style.corner_radius_top_right = 5
	style.corner_radius_bottom_left = 5
	style.corner_radius_bottom_right = 5
	panel.add_theme_stylebox_override("panel", style)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)

	var main_vbox = VBoxContainer.new()

	# Header
	var header = HBoxContainer.new()
	var date_lbl = Label.new()
	date_lbl.text = run.get("timestamp", "").split("T")[0]
	date_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var mode_lbl = Label.new()
	mode_lbl.text = run.get("mode", "unknown").to_upper() + " | " + run.get("status", "unknown").to_upper()
	mode_lbl.add_theme_color_override("font_color", Color(1, 0.8, 0.4) if run.get("status") == "completed" else Color(0.8, 0.3, 0.3))

	header.add_child(date_lbl)
	header.add_child(mode_lbl)

	# Stats
	var stats_hbox = HBoxContainer.new()
	var time_lbl = Label.new()
	time_lbl.text = "Time: " + _format_time(run.get("total_time_seconds", 0))
	time_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var score_lbl = Label.new()
	score_lbl.text = "Score: " + str(run.get("final_score", 0))
	score_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var waves_lbl = Label.new()
	waves_lbl.text = "Waves: " + str(run.get("waves_cleared", 0))

	stats_hbox.add_child(time_lbl)
	stats_hbox.add_child(score_lbl)
	stats_hbox.add_child(waves_lbl)

	# Breakdown
	var bd = run.get("difficulty_breakdown", {})
	var bd_lbl = Label.new()
	bd_lbl.text = "E: " + str(bd.get("easy", 0)) + " | M: " + str(bd.get("medium", 0)) + " | H: " + str(bd.get("hard", 0))
	bd_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))

	main_vbox.add_child(header)
	main_vbox.add_child(stats_hbox)
	main_vbox.add_child(bd_lbl)

	# Expandable Details
	var details = VBoxContainer.new()
	details.visible = false
	var hs = HSeparator.new()
	details.add_child(hs)

	var puzzles = run.get("puzzles_solved", [])
	for p in puzzles:
		var p_hbox = HBoxContainer.new()
		var p_name = Label.new()
		p_name.text = p.get("name", "Puzzle")
		p_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var p_time = Label.new()
		p_time.text = _format_time(p.get("time_seconds", 0)) + " / " + _format_time(p.get("par_time", 0))
		p_hbox.add_child(p_name)
		p_hbox.add_child(p_time)
		details.add_child(p_hbox)

	main_vbox.add_child(details)

	var btn = Button.new()
	btn.text = "Toggle Details"
	btn.pressed.connect(func(): details.visible = !details.visible)
	main_vbox.add_child(btn)

	margin.add_child(main_vbox)
	panel.add_child(margin)
	vbox.add_child(panel)

	return vbox

func _format_time(seconds: float) -> String:
	var mins = int(seconds) / 60
	var secs = int(seconds) % 60
	return "%02d:%02d" % [mins, secs]

func _on_resized() -> void:
	var size = get_viewport().get_visible_rect().size
	if size.x > 768 and size.x > size.y:
		# Desktop mode
		container_hbox.visible = true
		mobile_tabs.visible = false

		# Move content back to desktop containers
		if stats_content.get_parent() != stats_panel_desktop:
			stats_content.get_parent().remove_child(stats_content)
			stats_panel_desktop.add_child(stats_content)

		if history_content.get_parent() != history_panel_desktop:
			history_content.get_parent().remove_child(history_content)
			history_panel_desktop.add_child(history_content)
	else:
		# Mobile mode
		container_hbox.visible = false
		mobile_tabs.visible = true

		# Move content to mobile tabs
		if stats_content.get_parent() != stats_tab:
			stats_content.get_parent().remove_child(stats_content)
			stats_tab.add_child(stats_content)

		if history_content.get_parent() != history_tab:
			history_content.get_parent().remove_child(history_content)
			history_tab.add_child(history_content)
