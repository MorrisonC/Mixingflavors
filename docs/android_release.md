# Android release gate

The Android export is now configured for Google Play and can produce a signed
App Bundle locally. This document records what is verified, what is still
unproven, and exactly how to upload to internal testing.

## What the checked-in `Android` preset now does

Read `export_presets.cfg` rather than assuming; the values below are the ones
that matter and the reasons they are what they are.

- **Emits an App Bundle, not an APK.** `gradle_build/export_format=1` with
  `gradle_build/use_gradle_build=true`. Godot refuses to produce an `.aab`
  without the Gradle build, so an Android build needs a JDK, the Android SDK,
  and a warm Gradle cache. The Web build does not.
- **`arm64-v8a` + `armeabi-v7a` only.** Play requires 64-bit; `x86`/`x86_64` are
  off and are only re-enabled for a local emulator lane, never for an upload.
- **`minSdk 24`, `targetSdk 36`, `versionCode 1`, `versionName 0.1.0`.**
  Increment `version/code` for every upload; Play rejects a duplicate.
- **`screen/edge_to_edge=true`.** Mandatory from `targetSdk` 35 onward. Without
  it Android letterboxes the game and the safe-area handling in `MainMenu` and
  `TutorialUI` has nothing real to work against.
- **Landscape only**, from `display/window/handheld/orientation=0` in
  `project.godot`.
- **Adaptive launcher icon** with a monochrome layer for Android 13+ themed
  icons, plus a legacy 192px icon and a splash logo.
- **VIBRATE only** as an explicit permission, because haptics are a shipped
  feature behind a settings toggle. INTERNET is left off; Godot adds it on its
  own and only if the project actually uses a network feature.
- **Excludes** `test/**`, `tests/**`, `addons/gut/**`, `tools/**`,
  `scripts/test_bridge.gd`, the 25 MB `assets/puzzles/*_puzzles.json` source
  corpus, `puzzle_manifest.json`, and the Node/package files. The runtime
  `gauntlet_catalog.json` and the curated per-theme model JSONs stay, because
  the Compendium loads them at runtime.
- `project.godot` now sets `rendering/textures/vram_compression/import_etc2_astc=true`.
  Godot refuses an Android export without it.

## Signing

Release signing is **never** in version control. `export_presets.cfg` keeps
`keystore/release`, `keystore/release_user` and `keystore/release_password`
present and empty.

The upload key lives outside the repository, in `C:\secure`:

| File | Purpose |
| --- | --- |
| `mixingflavors-upload.jks` | the upload keystore; the only copy, never lose it |
| `mixingflavors-upload-cert.pem` | X.509 certificate for Play Console enrolment |
| `mixingflavors-upload.pem` | private key, PKCS#8 PEM |
| `mixingflavorsinfo.txt` | passwords (plaintext, as requested) and fingerprints |

`npm run build:android` resolves the four signing values from
`MF_KEYSTORE` / `MF_KEYSTORE_PASSWORD` / `MF_KEY_ALIAS` / `MF_KEY_PASSWORD`, or
reads the password and alias out of `MF_SIGNING_INFO`, injects them into a
temporary copy of `export_presets.cfg`, exports, and restores the committed
preset in a `finally` block. The script fails loudly if a password is still
present in the preset after the restore.

> The password is stored in plaintext because that was asked for. Treat
> `C:\secure` as a secret: anyone with the `.jks` and the text can sign builds
> Play will accept as yours. If that folder is ever shared, backed up to the
> cloud, or committed by mistake, rotate the upload key in Play Console
> immediately.

## Building

```powershell
# Once per machine: the standard (non-mono) Godot console build and the Android SDK.
$env:GODOT_BIN = 'C:\Godot\Godot_v4.7.2-stable_win64_console.exe'
$env:JAVA_HOME = 'C:\Android\jdk17'

# Point at the local signing material.
$env:MF_SIGNING_INFO = 'C:\secure\mixingflavorsinfo.txt'
$env:MF_KEYSTORE    = 'C:\secure\mixingflavors-upload.jks'

npm run build:android
npm run verify:android
```

`build:android` unpacks the Android Gradle build template into
`android/build` and writes `android/.build_version` if they are missing, so a
clean checkout does not need the editor's "Install Android Build Template" menu
item. Both paths are generated and gitignored.

The first Gradle build downloads the Android Gradle Plugin and the AndroidX
libraries, so it can take 20-30 minutes. Later builds are fast.

In CI, provide the four signing values as protected environment secrets. The
`export_presets.cfg` password is never written to a log.

## Store assets

`assets/branding/*.svg` are the editable masters. They are rasterized to the
exact sizes each surface needs by:

```
godot --headless --path . -s tools/branding/generate_store_assets.gd
```

The generator fails the run if a Play icon is not fully opaque, if a themed
icon has non-transparent corners or no mark in the centre, or if any export
rasterizes to a single flat colour.

| Artifact | Size | Used by |
| --- | --- | --- |
| `store/play/play_icon_512.png` | 512x512 opaque | Play Console app icon (required at app creation) |
| `store/play/feature_graphic_1024x500.png` | 1024x500 | Play listing feature graphic |
| `assets/branding/launcher/adaptive_{foreground,background,monochrome}_432.png` | 432x432 | Android adaptive + themed icon |
| `assets/branding/launcher/launcher_192.png` | 192x192 | legacy launcher icon and splash |
| `store/play/web_icon_{144,180,192,512}.png` | various | PWA / browser icons |
| `store/play/listing_copy.txt` | text | paste-ready title, short and full descriptions |

Godot's SVG rasteriser ignores `<text>`, which is why the feature graphic
wordmark is authored as stroked paths on an explicit grid.

## Uploading to internal testing

1. Create the app in Play Console with package id
   `com.morrisonc.mixingflavors.voxelgauntlet`, category **Game**, and upload
   `store/play/play_icon_512.png` as the app icon.
2. Under **Release > Setup > App signing**, choose *Use Play App Signing* and
   enrol the upload key certificate: upload
   `C:\secure\mixingflavors-upload-cert.pem` for a new app, or provide the
   SHA-1 fingerprint from `mixingflavorsinfo.txt` for an existing one.
3. Upload `build/android/MixingFlavorsVoxelGauntlet.aab` under
   **Testing > Internal testing > Create new release**.
4. Add tester email addresses or a Google Group under **Testing > Internal
   testing > Testers**.
5. Publish. Testers get the Play-installer link; the build is also available
   from the internal testing page.

## What `npm run verify:android` proves

`tools/verify-android-bundle.js` fails the build unless:

- the artifact is a real App Bundle (`BundleConfig.pb` plus a base module);
- it carries a JAR signature, signed by the expected upload key;
- `bundletool` parses it and can generate device APKs from it;
- the manifest reports the intended package id, versionName, minSdk and
  targetSdk, and does **not** request INTERNET;
- `arm64-v8a` and `armeabi-v7a` are present and `x86`/`x86_64` are not;
- `apksigner` verifies a generated APK with a v2 or v3 signature scheme;
- every native library is 16 KB page aligned, which is a hard Play requirement
  and is checked by reading the ELF `PT_LOAD` segments rather than assumed.

## Still unproven

The bundle is signed, structurally valid, and correctly configured, but none of
the following has been done. They remain genuine gaps, not formalities:

- **No device run.** Nothing has been installed on a physical arm64 phone or an
  emulator. Frame rate, memory, thermal behaviour, safe areas, audio focus,
  haptics, pause/resume and process recreation are all unmeasured.
- **No 16 KB page-size device test.** The verifier proves the libraries *declare*
  16 KB alignment; a device on a 16 KB page-size runtime is what actually
  exercises it.
- **No real Play upload.** The AAB has never been through Play Console's own
  validation, so target-API, data-safety and content-rating findings are still
  outstanding.
- **No release signing by Google.** Play App Signing is configured in the
  console steps above but has not been performed.
- **Screenshots are not generated.** They are required before a *production*
  release, not for internal testing.
