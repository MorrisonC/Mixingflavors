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

- **Assets:** `assets/textures/generated/abstract_panorama.svg`, `icon.svg`, and
  the branding masters in `assets/branding/` (`icon_master.svg`,
  `icon_foreground.svg`, `icon_monochrome.svg`, `feature_graphic.svg`)
- **Creator:** Mixing Flavors project
- **License:** CC0 1.0 Universal
- **Use:** The panorama is the title-screen backdrop; the branding masters are
  the source for the Android launcher icons, the Play Console listing icon and
  feature graphic, the splash logo, and the Web/PWA icons.
- **Generated outputs:** `assets/branding/launcher/*.png` and `store/play/*.png`
  are rasterized from the SVG masters by
  `godot --headless --path . -s tools/branding/generate_store_assets.gd`. Do not
  hand-edit the PNGs.
- **License copy:** `assets/textures/generated/LICENSE.txt`,
  `assets/branding/LICENSE.txt`

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

## Content curation

The runtime uses the verified generated panorama, audio pack, and puzzle catalog.
Legacy photographic backgrounds and the one-off OBJ conversion utility were removed
because they were not referenced by the shipping scenes.
