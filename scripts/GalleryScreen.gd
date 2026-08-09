extends Control

const CATEGORIES = ["All", "Animals", "Buildings", "Nature", "Fantasy", "Special"]

var gallery_data: Array = []

@onready var grid = $MarginContainer/VBoxContainer/ScrollContainer/GridContainer
@onready var tabs_container = $MarginContainer/VBoxContainer/Tabs

func _ready() -> void:
	$MarginContainer/VBoxContainer/TopBar/BackButton.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/MainMenu.tscn"))

	_load_gallery_data()

	for cat in CATEGORIES:
		var btn = Button.new()
		btn.text = cat
		btn.custom_minimum_size = Vector2(100, 40)
		btn.pressed.connect(_on_tab_pressed.bind(cat))
		tabs_container.add_child(btn)

	_populate_grid("All")

func _load_gallery_data() -> void:
	# Real implementation would load from a manifest or saved data. For this patch, we populate
	# the list using the requested data mapping.
	var raw_items = [
		{"name": "Penguin", "cat": "Animals", "thumb": "res://assets/gallery/thumbnails/penguin.jpg"},
		{"name": "Bunny", "cat": "Animals", "thumb": "res://assets/gallery/thumbnails/bunny.jpg"},
		{"name": "Turtle", "cat": "Animals", "thumb": "res://assets/gallery/thumbnails/turtle.png"},
		{"name": "Fox", "cat": "Animals", "thumb": "res://assets/gallery/thumbnails/fox.png"},
		{"name": "Boar", "cat": "Animals", "thumb": "res://assets/gallery/thumbnails/boar.png"},
		{"name": "Spider", "cat": "Animals", "thumb": "res://assets/gallery/thumbnails/spider.png"},
		{"name": "Butterfly", "cat": "Animals", "thumb": "res://assets/gallery/thumbnails/butterfly.png"},
		{"name": "Bee", "cat": "Animals", "thumb": "res://assets/gallery/thumbnails/bee.png"},
		{"name": "Seahorse", "cat": "Animals", "thumb": "res://assets/gallery/thumbnails/seahorse.png"},
		{"name": "Octopus", "cat": "Animals", "thumb": "res://assets/gallery/thumbnails/octopus.png"},
		{"name": "Crab", "cat": "Animals", "thumb": "res://assets/gallery/thumbnails/crab.png"},
		{"name": "Shark", "cat": "Animals", "thumb": "res://assets/gallery/thumbnails/shark.png"},

		{"name": "Lighthouse", "cat": "Buildings", "thumb": "res://assets/gallery/thumbnails/lighthouse.jpg"},
		{"name": "Pirate Ship", "cat": "Buildings", "thumb": "res://assets/gallery/thumbnails/pirate_ship.jpg"},
		{"name": "Cottage", "cat": "Buildings", "thumb": "res://assets/gallery/thumbnails/cottage.jpg"},
		{"name": "Tree House", "cat": "Buildings", "thumb": "res://assets/gallery/thumbnails/tree_house.jpg"},
		{"name": "Tower", "cat": "Buildings", "thumb": "res://assets/gallery/thumbnails/tower.jpg"},
		{"name": "Windmill", "cat": "Buildings", "thumb": "res://assets/gallery/thumbnails/windmill.jpg"},

		{"name": "Potted Cactus", "cat": "Nature", "thumb": "res://assets/gallery/thumbnails/potted_cactus.png"},
		{"name": "Fern", "cat": "Nature", "thumb": "res://assets/gallery/thumbnails/fern.png"},
		{"name": "Red Mushrooms", "cat": "Nature", "thumb": "res://assets/gallery/thumbnails/red_mushrooms.png"},
		{"name": "Palm Island", "cat": "Nature", "thumb": "res://assets/gallery/thumbnails/palm_island.png"},

		{"name": "Dragon", "cat": "Fantasy", "thumb": "res://assets/gallery/thumbnails/dragon.jpg"},
		{"name": "Blue Mushrooms", "cat": "Fantasy", "thumb": "res://assets/gallery/thumbnails/blue_mushrooms.png"},
		{"name": "Crystal Plant", "cat": "Fantasy", "thumb": "res://assets/gallery/thumbnails/crystal_plant.png"},
		{"name": "Cactus Creature", "cat": "Fantasy", "thumb": "res://assets/gallery/thumbnails/cactus_creature.png"},
		{"name": "Sandworm", "cat": "Fantasy", "thumb": "res://assets/gallery/thumbnails/sandworm.png"},

		{"name": "Robot", "cat": "Special", "thumb": "res://assets/gallery/thumbnails/robot.jpg"},
		{"name": "Hot Air Balloon", "cat": "Special", "thumb": "res://assets/gallery/thumbnails/hot_air_balloon.jpg"},
		{"name": "Treasure Chest", "cat": "Special", "thumb": "res://assets/gallery/thumbnails/treasure_chest.jpg"},
		{"name": "Obelisk", "cat": "Special", "thumb": "res://assets/gallery/thumbnails/obelisk.png"},
		{"name": "Broken Vase", "cat": "Special", "thumb": "res://assets/gallery/thumbnails/broken_vase.png"},
		{"name": "Scroll", "cat": "Special", "thumb": "res://assets/gallery/thumbnails/scroll.png"},
		{"name": "Telescope", "cat": "Special", "thumb": "res://assets/gallery/thumbnails/telescope.png"},
		{"name": "Globe", "cat": "Special", "thumb": "res://assets/gallery/thumbnails/globe.png"}
	]

	for data in raw_items:
		var entry = GalleryEntry.new()
		entry.model_name = data["name"]
		entry.category = data["cat"]
		entry.thumbnail = load(data["thumb"])
		# Simulation: Let's unlock a few items
		entry.unlocked = data["name"] in ["Penguin", "Lighthouse", "Tree House", "Potted Cactus", "Dragon", "Robot"]
		gallery_data.append(entry)

func _on_tab_pressed(category: String) -> void:
	_populate_grid(category)

func _populate_grid(filter_cat: String) -> void:
	for child in grid.get_children():
		child.queue_free()

	for item in gallery_data:
		if filter_cat == "All" or item.category == filter_cat:
			var panel = PanelContainer.new()
			panel.custom_minimum_size = Vector2(200, 240)

			var vbox = VBoxContainer.new()
			panel.add_child(vbox)

			var tex = TextureRect.new()
			if item.unlocked:
				tex.texture = item.thumbnail
			else:
				# Show a locked indicator. Using a plain texture/color for missing lock logic gracefully.
				var placeholder = PlaceholderTexture2D.new()
				placeholder.size = Vector2(200, 200)
				tex.texture = placeholder
				tex.modulate = Color(0.2, 0.2, 0.2)

			tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tex.custom_minimum_size = Vector2(200, 200)
			vbox.add_child(tex)

			var lbl = Label.new()
			lbl.text = item.model_name if item.unlocked else "???"
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			vbox.add_child(lbl)

			grid.add_child(panel)
