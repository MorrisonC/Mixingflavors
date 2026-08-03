1. **Update `PuzzleRegistry.gd` to lazily load puzzles from the manifest**
   - Convert `PuzzleRegistry` from a static helper class to an Autoload-compatible script (remove static methods, store data as member variables).
   - Add `manifest_data` and `loaded_theme_puzzles` variables.
   - Read `res://assets/puzzles/puzzle_manifest.json` in `_ready()` (or lazily when needed).
   - Create `load_theme(theme_name: String) -> Array` to lazily load theme json files.
   - Create `get_puzzles_for_gauntlet(tier: String) -> Array` to return a list of matching puzzles from the *already loaded* themes, OR load a random theme if none exist yet. Wait, I should implement exactly what the prompt asked for:
```gdscript
func get_puzzles_for_gauntlet(tier: String) -> Array:
	var matching_puzzles: Array = []
	for theme in manifest_data.keys():
		var puzzles = load_theme(theme)
		for puzzle in puzzles:
			if puzzle.get("difficulty_tier", "") == tier:
				matching_puzzles.append(puzzle)
	return matching_puzzles
```
   - *Self-correction:* The prompt provided the exact implementation for `get_puzzles_for_gauntlet`. I should use it, but replace `res://data/puzzles/` with `res://assets/puzzles/` since I put the assets there based on user feedback.

2. **Update Main Menu (`scenes/MainMenu.tscn` & `scripts/MainMenu.gd`)**
   - Add the missing "Boss" difficulty button to the existing Difficulty Selector dialog (between Hard and Endless).
   - Ensure the "Boss" button correctly calls `_on_difficulty_selected("boss")`.

3. **Update Gauntlet Mode (`scripts/EscapeGauntlet.gd`)**
   - Remove the `max_rounds = 5` and hardcoded Valentine background logic.
   - Make it endless: just increment the round continuously.
   - Instead of using `PuzzleRegistry.get_puzzles_by_tier`, use `PuzzleRegistry.get_puzzles_for_gauntlet(tier)`.
   - Wait, `PuzzleRegistry` was previously accessed with static methods. If I change it to an instance script, I might need to make sure it's added as an Autoload or keep it static?
   - Wait, the prompt says:
     `Godot Asynchronous Theme Dataset Loader (res://scripts/PuzzleRegistry.gd)`
     `extends Node`
     `class_name PuzzleRegistry`
     `var manifest_data: Dictionary = {}`
     `var loaded_theme_puzzles: Dictionary = {}`
     `func _ready() -> void: load_manifest()`
     This implies it's either an Autoload, OR I should make these methods `static` if it's NOT an Autoload. Let's check `project.godot` to see if `PuzzleRegistry` is in the autoloads.

4. **Run Tests and verify everything works**

5. **Complete pre-commit steps to ensure proper testing, verification, review, and reflection are done.**
