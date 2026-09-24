# Project Assets & Attribution

Only assets with a verified, compatible license are approved for release.

## Bundled Open-Source Audio

- **Asset pack:** Kenney Interface Sounds 1.0
- **Creator:** Kenney
- **Source:** https://kenney.nl/assets/interface-sounds
- **License:** CC0 1.0 Universal
- **Bundled files:** `assets/audio/kenney_interface_sounds/chisel.ogg`, `mark.ogg`,
  `error.ogg`, `toggle.ogg`, and `victory.ogg`
- **Upstream files:** `click_002.ogg`, `confirmation_002.ogg`, `error_003.ogg`,
  `toggle_002.ogg`, and `confirmation_004.ogg`
- **Changes:** Files were renamed to describe their gameplay role; no audio processing
  was applied.
- **License copy:** `assets/audio/kenney_interface_sounds/LICENSE.txt`

## Original Project Artwork

- **Assets:** `assets/textures/generated/abstract_panorama.svg` and `icon.svg`
- **Creator:** Hybrid Tactical Puzzle RPG project
- **License:** CC0 1.0 Universal
- **Use:** The panorama replaces uncleared photographic runtime backgrounds; the icon is
  the application and Web icon.
- **License copy:** `assets/textures/generated/LICENSE.txt`

## Runtime-Generated Geometry

Voxel blocks, outlines, cursors, reveal animation, and UI themes are generated from Godot
meshes, materials, shaders, and scene resources in this repository. No third-party voxel or
UI-pack files are required at runtime.

## Development Dependency

- **Asset:** Godot Unit Test (GUT) 9.6.1
- **Source:** https://github.com/bitwes/Gut
- **License:** MIT
- **License copy:** `addons/gut/LICENSE.md`
- GUT is used for automated tests and is excluded from release exports.

## Unverified Legacy Files

The following files do not have sufficient provenance in the repository and are not
approved for public distribution:

- `assets/textures/valentine/bg1.jpg` through `bg8.jpg`
- `assets/textures/beautiful_skybox.jpg`
- `assets/textures/abstract_bg.png`
- `assets/textures/stylized_cube.png`
- `assets/models/heart.obj`

Runtime scenes no longer depend on these files, and the Web release preset excludes them.
They may be removed after any historical visual references are no longer needed.
