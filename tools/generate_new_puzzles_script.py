import json
import random
import uuid
import os
import itertools

def is_puzzle_solvable(dims, hints, target_voxels):
    dx, dy, dz = dims
    grid_state = {}
    for x in range(dx):
        for y in range(dy):
            for z in range(dz):
                grid_state[(x, y, z)] = 0

    target_set = set(tuple(v) for v in target_voxels)

    changed = True
    iterations = 0
    max_iterations = dx * dy * dz * 2

    while changed and iterations < max_iterations:
        changed = False
        iterations += 1

        for axis in range(3):
            a1_max = [dy, dx, dx][axis]
            a2_max = [dz, dz, dy][axis]

            for a1 in range(a1_max):
                for a2 in range(a2_max):
                    axis_key = ["x", "y", "z"][axis]
                    key = f"{a1},{a2}"
                    line_clue = hints.get(axis_key, {}).get(key, [])

                    line_coords = []
                    line_states = []

                    n = dims[axis]
                    for i in range(n):
                        if axis == 0: coord = (i, a1, a2)
                        elif axis == 1: coord = (a1, i, a2)
                        else: coord = (a1, a2, i)
                        line_coords.append(coord)
                        line_states.append(grid_state[coord])

                    if 0 not in line_states:
                        continue

                    valid_configs = _get_valid_configurations(line_clue, line_states)

                    if not valid_configs:
                        return False

                    for i in range(n):
                        if line_states[i] == 0:
                            all_target = all(config[i] == 2 for config in valid_configs)
                            all_empty = all(config[i] == 1 for config in valid_configs)

                            if all_target:
                                grid_state[line_coords[i]] = 2
                                changed = True
                            elif all_empty:
                                grid_state[line_coords[i]] = 1
                                changed = True

    for x in range(dx):
        for y in range(dy):
            for z in range(dz):
                if grid_state[(x, y, z)] == 0:
                    return False

    for x in range(dx):
        for y in range(dy):
            for z in range(dz):
                v = (x, y, z)
                is_target = v in target_set
                resolved_state = grid_state[v]
                if is_target and resolved_state != 2: return False
                if not is_target and resolved_state != 1: return False

    return True

def _get_valid_configurations(clue, current_state):
    valid_configs = []
    _solve_line(clue, current_state, 0, 0, [], valid_configs)
    return valid_configs

def _solve_line(clue, current_state, current_idx, clue_idx, current_config, valid_configs):
    if current_idx == len(current_state):
        if clue_idx == len(clue):
            valid_configs.append(list(current_config))
        return

    can_be_empty = current_state[current_idx] in (0, 1)

    if can_be_empty:
        current_config.append(1)
        _solve_line(clue, current_state, current_idx + 1, clue_idx, current_config, valid_configs)
        current_config.pop()

    if clue_idx < len(clue):
        block_size = clue[clue_idx]
        if current_idx + block_size <= len(current_state):
            valid = True
            for i in range(block_size):
                if current_state[current_idx + i] == 1:
                    valid = False
                    break

            if valid:
                end_idx = current_idx + block_size
                if end_idx < len(current_state) and current_state[end_idx] == 2:
                    valid = False

                if valid:
                    current_config.extend([2] * block_size)

                    if end_idx < len(current_state):
                        current_config.append(1)
                        _solve_line(clue, current_state, end_idx + 1, clue_idx + 1, current_config, valid_configs)
                        current_config.pop()
                    else:
                        _solve_line(clue, current_state, end_idx, clue_idx + 1, current_config, valid_configs)

                    for _ in range(block_size):
                        current_config.pop()

def generate_hints(dims, target_voxels):
    dx, dy, dz = dims
    target_set = set(tuple(v) for v in target_voxels)

    hints = {"x": {}, "y": {}, "z": {}}
    clues_out = {"x_axis": {}, "y_axis": {}, "z_axis": {}}

    def calc_line(length, is_target_func):
        groups = []
        count = 0
        for i in range(length):
            if is_target_func(i):
                count += 1
            else:
                if count > 0:
                    groups.append(count)
                    count = 0
        if count > 0:
            groups.append(count)
        return groups

    for y in range(dy):
        for z in range(dz):
            blocks = calc_line(dx, lambda x: (x, y, z) in target_set)
            hints["x"][f"{y},{z}"] = blocks
            clues_out["x_axis"][f"{y},{z}"] = {"total": sum(blocks), "blocks": blocks}

    for x in range(dx):
        for z in range(dz):
            blocks = calc_line(dy, lambda y: (x, y, z) in target_set)
            hints["y"][f"{x},{z}"] = blocks
            clues_out["y_axis"][f"{x},{z}"] = {"total": sum(blocks), "blocks": blocks}

    for x in range(dx):
        for y in range(dy):
            blocks = calc_line(dz, lambda z: (x, y, z) in target_set)
            hints["z"][f"{x},{y}"] = blocks
            clues_out["z_axis"][f"{x},{y}"] = {"total": sum(blocks), "blocks": blocks}

    return hints, clues_out

def get_difficulty_score(dims, num_targets):
    vol = dims[0] * dims[1] * dims[2]
    density = num_targets / vol if vol > 0 else 0
    score = int(vol * 5 * (1 + density))
    return score

def determine_tier(score):
    if score < 200: return "easy"
    elif score < 400: return "medium"
    elif score < 600: return "hard"
    else: return "boss"

def get_all_rotations_and_mirrors(target_voxels, dims):
    # Returns a list of sets of tuples, representing all 48 possible symmetries (rotations/reflections) of the shape within dims
    dx, dy, dz = dims

    def normalize_shape(shape):
        if not shape:
            return frozenset()
        min_x = min(v[0] for v in shape)
        min_y = min(v[1] for v in shape)
        min_z = min(v[2] for v in shape)
        return frozenset((v[0]-min_x, v[1]-min_y, v[2]-min_z) for v in shape)

    symmetries = []

    # 48 symmetries of a cube
    for p in itertools.permutations([0, 1, 2]):
        for signs in itertools.product([1, -1], repeat=3):
            transformed_shape = []
            for v in target_voxels:
                # v is (x, y, z)
                coords = [v[0], v[1], v[2]]
                new_coords = [0, 0, 0]

                for i in range(3):
                    orig_val = coords[p[i]]
                    # Mirror if sign is -1 (mirror across center)
                    if signs[i] == -1:
                        # Assuming mirroring across axis bounds
                        orig_val = -orig_val
                    new_coords[i] = orig_val
                transformed_shape.append(tuple(new_coords))
            symmetries.append(normalize_shape(transformed_shape))

    return symmetries

if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="Generate solvable 3D Picross puzzles.")
    parser.add_argument("--count", type=int, default=1, help="Number of puzzles to generate")
    parser.add_argument("--theme", type=str, default="animals", help="Theme to generate for")
    args = parser.parse_args()

    THEME = args.theme
    NUM_NEW_PUZZLES = args.count
    FILE_PATH = f"assets/puzzles/{THEME}_puzzles.json"
    MANIFEST_PATH = "assets/puzzles/puzzle_manifest.json"
    DIMS_OPTIONS = [[3, 3, 3], [4, 4, 4], [5, 5, 5]]

    if os.path.exists(FILE_PATH):
        with open(FILE_PATH, 'r') as f:
            data = json.load(f)
    else:
        data = {"puzzles": []}

    existing_puzzles = data.get("puzzles", [])

    # Store normalized existing shapes to check against all rotations/mirrors
    def normalize_shape(shape):
        if not shape:
            return frozenset()
        min_x = min(v[0] for v in shape)
        min_y = min(v[1] for v in shape)
        min_z = min(v[2] for v in shape)
        return frozenset((v[0]-min_x, v[1]-min_y, v[2]-min_z) for v in shape)

    existing_normalized_shapes = set(normalize_shape([tuple(v) for v in p["target_voxels"]]) for p in existing_puzzles)

    new_puzzles = []

    themes_nouns = {
        "animals": ["Wolf", "Bear", "Lion", "Eagle", "Shark", "Tiger", "Fox", "Owl", "Rhino", "Hippo", "Bat", "Frog", "Toad", "Snake", "Fish"],
        "mythical": ["Dragon", "Unicorn", "Phoenix", "Griffin", "Chimera", "Hydra", "Kraken", "Minotaur", "Sphinx", "Pegasus", "Cerberus", "Basilisk", "Wyvern", "Golem", "Troll"],
        "cyberpunk": ["Deck", "Jack", "Neuro", "Synapse", "Chrome", "Neon", "Wire", "Grid", "Data", "Proxy", "Core", "Byte", "Chip", "Glitch", "Pulse"],
        "scifi": ["Star", "Galaxy", "Nebula", "Quasar", "Pulsar", "Nova", "Comet", "Meteor", "Asteroid", "Planet", "Moon", "Orbit", "Rocket", "Drone", "Laser"],
        "alchemy": ["Potion", "Elixir", "Flask", "Vial", "Crystal", "Gem", "Stone", "Metal", "Gold", "Silver", "Copper", "Iron", "Lead", "Mercury", "Salt"],
        "egypt": ["Pyramid", "Sphinx", "Pharaoh", "Scarab", "Ankh", "Mummy", "Obelisk", "Temple", "Tomb", "Camel", "Papyrus", "Chariot", "Oasis", "Nile", "Hieroglyph"],
    }

    animals_names = themes_nouns.get(THEME, ["Shape", "Block", "Structure", "Object", "Form", "Item", "Element", "Entity", "Thing", "Construct"])
    name_adjectives = ["Cosmic", "Luminous", "Iron", "Shadow", "Crystal", "Astral", "Mystic", "Solar", "Lunar", "Neon", "Quantum", "Cyber", "Void", "Chrono", "Aether"]

    print(f"Generating {NUM_NEW_PUZZLES} new puzzles for {THEME} theme...")

    attempts = 0
    while len(new_puzzles) < NUM_NEW_PUZZLES and attempts < 50000:
        attempts += 1
        dims = random.choice(DIMS_OPTIONS)
        dx, dy, dz = dims
        vol = dx * dy * dz

        num_targets = random.randint(int(vol * 0.2), int(vol * 0.6))
        target_voxels = set()

        start = (random.randint(0, dx-1), random.randint(0, dy-1), random.randint(0, dz-1))
        target_voxels.add(start)
        candidates = set()

        def add_neighbors(p):
            for d in [(1,0,0), (-1,0,0), (0,1,0), (0,-1,0), (0,0,1), (0,0,-1)]:
                n = (p[0]+d[0], p[1]+d[1], p[2]+d[2])
                if 0 <= n[0] < dx and 0 <= n[1] < dy and 0 <= n[2] < dz:
                    if n not in target_voxels:
                        candidates.add(n)

        add_neighbors(start)
        while len(target_voxels) < num_targets and candidates:
            nxt = random.choice(list(candidates))
            candidates.remove(nxt)
            target_voxels.add(nxt)
            add_neighbors(nxt)

        target_list = [list(v) for v in target_voxels]
        target_list.sort()

        # Check uniqueness against all rotations/mirrors
        symmetries = get_all_rotations_and_mirrors(target_list, dims)
        is_unique = True
        for sym in symmetries:
            if sym in existing_normalized_shapes:
                is_unique = False
                break

        if not is_unique:
            continue

        hints, clues_out = generate_hints(dims, target_list)

        # Reject and regenerate if not logically solvable
        if is_puzzle_solvable(dims, hints, target_list):
            existing_normalized_shapes.add(normalize_shape([tuple(v) for v in target_list]))

            score = get_difficulty_score(dims, len(target_list))
            tier = determine_tier(score)

            rand_id = random.randint(10000, 99999)
            name = f"{random.choice(name_adjectives)} {random.choice(animals_names)} #{rand_id}"

            new_puzzle = {
                "id": f"{THEME}_{rand_id}",
                "name": name,
                "theme": THEME,
                "difficulty_tier": tier,
                "difficulty_score": score,
                "par_time_seconds": score // 2,
                "grid_size": dims,
                "voxel_count": len(target_list),
                "target_voxels": target_list,
                "clues": clues_out,
                "matching_asset_id": f"asset_{THEME}_{rand_id}",
                "solvable": True
            }

            new_puzzles.append(new_puzzle)
            print(f"[{len(new_puzzles)}/{NUM_NEW_PUZZLES}] Generated {name} ({tier}, score {score})")

    if len(new_puzzles) > 0:
        data["puzzles"].extend(new_puzzles)
        with open(FILE_PATH, 'w') as f:
            json.dump(data, f)

        print(f"Added {len(new_puzzles)} puzzles to {FILE_PATH}.")

        # Update manifest
        if os.path.exists(MANIFEST_PATH):
            with open(MANIFEST_PATH, 'r') as f:
                manifest = json.load(f)

            manifest["total_puzzles"] += len(new_puzzles)
            if THEME not in manifest["themes"]:
                manifest["themes"][THEME] = {
                    "file": f"{THEME}_puzzles.json",
                    "count": 0,
                    "easy_count": 0,
                    "medium_count": 0,
                    "hard_count": 0,
                    "boss_count": 0
                }
            manifest["themes"][THEME]["count"] += len(new_puzzles)

            for p in new_puzzles:
                tier = p["difficulty_tier"]
                manifest["themes"][THEME][f"{tier}_count"] += 1

            with open(MANIFEST_PATH, 'w') as f:
                json.dump(manifest, f, indent=2)

            print("Updated puzzle_manifest.json")
    else:
        print("Failed to generate any unique, solvable puzzles within attempt limits.")
