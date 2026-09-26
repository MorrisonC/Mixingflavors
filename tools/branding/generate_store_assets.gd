extends SceneTree
## Rasterizes the SVG masters in assets/branding into the exact pixel sizes
## Google Play and Android require, and asserts the properties each surface
## needs (no alpha where Google forbids it, opaque background for the adaptive
## layer, a real safe zone in the themed layer).
##
## Run with:
##   godot --headless --path . -s tools/branding/generate_store_assets.gd
##
## The SVGs stay the editable source of truth; the PNGs are the artifacts that
## get uploaded to Play Console and baked into the Android launcher.

const BRANDING_DIR := "res://assets/branding"
const PLAY_DIR := "res://store/play"
const LAUNCHER_DIR := "res://assets/branding/launcher"

## Every entry: master SVG -> output path + size + whether the result must be
## fully opaque (no alpha channel at all).
const TARGETS: Array = [
	{"svg": "icon_master.svg", "out": PLAY_DIR + "/play_icon_512.png", "size": 512, "opaque": true},
	{"svg": "icon_master.svg", "out": PLAY_DIR + "/play_icon_1024.png", "size": 1024, "opaque": true},
	{"svg": "icon_master.svg", "out": LAUNCHER_DIR + "/launcher_legacy_512.png", "size": 512, "opaque": true},
	{"svg": "icon_master.svg", "out": LAUNCHER_DIR + "/adaptive_background_432.png", "size": 432, "opaque": true},
	{"svg": "icon_foreground.svg", "out": LAUNCHER_DIR + "/adaptive_foreground_432.png", "size": 432, "opaque": false},
	{"svg": "icon_monochrome.svg", "out": LAUNCHER_DIR + "/adaptive_monochrome_432.png", "size": 432, "opaque": false},
	{"svg": "icon_foreground.svg", "out": LAUNCHER_DIR + "/launcher_192.png", "size": 192, "opaque": false},
	{"svg": "icon_master.svg", "out": LAUNCHER_DIR + "/splash_logo_512.png", "size": 512, "opaque": true},
	{"svg": "feature_graphic.svg", "out": PLAY_DIR + "/feature_graphic_1024x500.png", "size": 1024, "opaque": true},
	# Web/PWA icons. The web build is a shipping target, and a missing favicon
	# reads as a broken page in a browser tab.
	{"svg": "icon_master.svg", "out": PLAY_DIR + "/web_icon_512.png", "size": 512, "opaque": true},
	{"svg": "icon_master.svg", "out": PLAY_DIR + "/web_icon_192.png", "size": 192, "opaque": true},
	{"svg": "icon_master.svg", "out": PLAY_DIR + "/web_icon_180.png", "size": 180, "opaque": true},
	{"svg": "icon_master.svg", "out": PLAY_DIR + "/web_icon_144.png", "size": 144, "opaque": true},
]

## Play Console listing copy. Kept beside the graphics so a re-upload never
## ships an image with stale text.
const LISTING: Dictionary = {
	"title": "Mixing Flavors: Voxel Gauntlet",
	"short_description": "Carve the hidden sculpture out of every voxel cube before the clock runs out.",
	"full_description": """Mixing Flavors: Voxel Gauntlet is a 3D Picross time-attack game.

Every cube hides one sculpture. The numbers on each face tell you exactly how
many blocks must stay in that line, so the puzzle is a deduction, never a guess.

DEDUCE - Read the clues on every face. A 0 means the whole line is empty. A red
? means a line you cannot read yet.
CARVE - Hammer away the blocks the clues prove are empty. Chiselling a block
that belongs to the sculpture costs you HP.
REVEAL - Mark what must stay, slice the cube open to reach the blocks buried in
the middle, and the sculpture is revealed.

HOW A RUN WORKS
- One floor at a time against a 120-second clock.
- Clear with time to spare and the clock is banked for a rescue run.
- Mark blocks you have already deduced so slicing never costs you a surprise.
- Undo reverses your last move, mistakes included.
- Hint lights one provably safe cell whenever its cooldown is ready.

DESIGNED FOR SHORT SESSIONS
Landscape-first on phone and on the web, fully offline, no energy timers, no
ads, no forced purchases. Play one floor in a queue, or chase a deeper personal
best.

Content is deterministic: the same seed always produces the same puzzle
sequence, so a run can be retried, shared, or replayed exactly.""",
}


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PLAY_DIR))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(LAUNCHER_DIR))
	var failures: Array[String] = []
	for target in TARGETS:
		failures.append_array(_render(target))
	_write_listing_copy()
	if failures.is_empty():
		print("[brand] all store assets generated and verified")
		quit(0)
		return
	for failure in failures:
		push_error("[brand] " + failure)
	quit(1)


func _render(target: Dictionary) -> Array[String]:
	var svg_path: String = BRANDING_DIR + "/" + str(target["svg"])
	var out_path: String = str(target["out"])
	var size: int = int(target["size"])
	var want_opaque: bool = bool(target["opaque"])

	var texture: Texture2D = load(svg_path) as Texture2D
	if texture == null:
		return ["could not load " + svg_path]
	var source: Image = texture.get_image()
	if source == null:
		return ["no image data in " + svg_path]
	if source.is_compressed():
		source.decompress()

	var width: int = size
	var height: int = size
	if str(target["svg"]) == "feature_graphic.svg":
		# The feature graphic is the one non-square artifact; keep its 2.048:1
		# aspect instead of stretching it into a square.
		height = int(round(size * 500.0 / 1024.0))

	var image: Image = Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	if want_opaque:
		# Play rejects an icon with an alpha channel. Composite onto the deep
		# indigo corner of the gradient so a stray transparent edge in the SVG
		# still yields a fully opaque PNG.
		image.fill(Color(0.075, 0.094, 0.267, 1.0))
	var scaled: Image = source.duplicate() as Image
	scaled.resize(width, height, Image.INTERPOLATE_LANCZOS)
	image.blend_rect(scaled, Rect2i(Vector2i.ZERO, Vector2i(width, height)), Vector2i.ZERO)

	var problems: Array[String] = []
	problems.append_array(_check(image, target, want_opaque))
	var err: int = image.save_png(out_path)
	if err != OK:
		problems.append("save failed (%d) for %s" % [err, out_path])
	else:
		print("[brand] %s  %dx%d" % [out_path, width, height])
	return problems


func _check(image: Image, target: Dictionary, want_opaque: bool) -> Array[String]:
	var problems: Array[String] = []
	var name: String = str(target["out"]).get_file()
	if want_opaque:
		var transparent: int = 0
		for y in range(0, image.get_height(), 8):
			for x in range(0, image.get_width(), 8):
				if image.get_pixel(x, y).a < 0.999:
					transparent += 1
		if transparent > 0:
			problems.append("%s must be fully opaque but %d sampled pixels have alpha" % [name, transparent])
	# A blank or single-colour export usually means the SVG failed to rasterize.
	var first: Color = image.get_pixel(0, 0)
	var varies: bool = false
	for y in range(0, image.get_height(), 16):
		for x in range(0, image.get_width(), 16):
			if not image.get_pixel(x, y).is_equal_approx(first):
				varies = true
				break
		if varies:
			break
	if not varies:
		problems.append("%s rasterized to a single flat colour" % name)
	# The themed icon is recoloured from its alpha channel, so it must be
	# transparent around the edges rather than a filled square.
	if name.begins_with("adaptive_monochrome"):
		var corner: Color = image.get_pixel(2, 2)
		if corner.a > 0.05:
			problems.append("%s must have transparent corners, corner alpha is %.2f" % [name, corner.a])
		var centre: Color = image.get_pixel(image.get_width() / 2, image.get_height() / 2)
		if centre.a < 0.5:
			problems.append("%s has no mark in the centre" % name)
	return problems


func _write_listing_copy() -> void:
	var path: String = PLAY_DIR + "/listing_copy.txt"
	var text: String = ""
	text += "MIXING FLAVORS: VOXEL GAUNTLET - Google Play listing copy\n"
	text += "=========================================================\n"
	text += "Paste-ready. Plain text, no markdown.\n\n"
	text += "APP TITLE (max 30 chars)\n----------------------\n"
	text += "%s\n\n" % str(LISTING["title"])
	text += "SHORT DESCRIPTION (max 80 chars)\n---------------------------------\n"
	text += "%s\n\n" % str(LISTING["short_description"])
	text += "FULL DESCRIPTION (max 4000 chars)\n----------------------------------\n"
	text += "%s\n\n" % str(LISTING["full_description"])
	text += "CHARACTER COUNTS\n----------------\n"
	text += "title            : %d / 30\n" % str(LISTING["title"]).length()
	text += "short description: %d / 80\n" % str(LISTING["short_description"]).length()
	text += "full description : %d / 4000\n" % str(LISTING["full_description"]).length()
	text += "package id       : com.morrisonc.mixingflavors.voxelgauntlet\n"
	text += "content rating   : Everyone (no ads, no IAP, no data collection)\n"
	text += "category         : Game\n"
	text += "contact email    : (set this in Play Console; it is not stored here)\n"
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("[brand] could not write " + path)
		return
	file.store_string(text)
	file.close()
	print("[brand] wrote ", path)
