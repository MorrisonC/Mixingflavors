# Mixing Flavors: Voxel Gauntlet — Google Play internal testing runbook

Everything needed to take the current build from a clean machine to an installable
internal-testing release. Follow top to bottom on the first submission.

Read `docs/android_release.md` for how the build is configured and what the
verification gate actually proves.

## Where this currently stands

Everything that can be automated from here is done and verified. The upload is
**blocked on steps 2, 3 and 5**, which are browser-console actions bound to the
Play account and cannot be done through the API or by an agent without a signed-in
browser session:

- [x] Signed, verified App Bundle (51.7 MB, `verify:android` 29/29).
- [x] Upload keystore, certificate and key in `C:\secure`.
- [x] Store icon, feature graphic, listing copy, adaptive/themed icons.
- [x] Service account key at `C:\secure\play-service-account.json`; it
      authenticates against the Play Developer API.
- [ ] **Create the app** (step 2).
- [ ] **Enrol the upload key** (step 3).
- [ ] **Complete the store listing and declarations** (steps 4 and 5).
- [ ] **Upload** (step 7) — one command once the three items above are done.

## What is already in place

| Item | Location | Notes |
| --- | --- | --- |
| Upload keystore (JKS, RSA 4096) | `C:\secure\mixingflavors-upload.jks` | The only copy. Back it up off this machine. |
| Upload certificate (PEM) | `C:\secure\mixingflavors-upload-cert.pem` | Upload this to Play Console. |
| Private key (PKCS#8 PEM) | `C:\secure\mixingflavors-upload.pem` | Backup only, not needed by Play. |
| Passwords and fingerprints | `C:\secure\mixingflavorsinfo.txt` | Plaintext, as requested. |
| Verified App Bundle | `build\android\MixingFlavorsVoxelGauntlet.aab` | 51.7 MB, signed, passes `npm run verify:android`. |
| Store icon, feature graphic, web icons | `store\play\` | Regenerate with the command in step 9. |
| Adaptive + themed launcher icons | `assets\branding\launcher\` | Baked into the bundle. |
| Listing copy | `store\play\listing_copy.txt` | Paste-ready, with character counts. |

Package id: `com.morrisonc.mixingflavors.voxelgauntlet`
Target/compile SDK 36, minSdk 24, ABIs `arm64-v8a` + `armeabi-v7a`.

Upload certificate **SHA-1**, which is what Play asks for when you enrol by
fingerprint rather than by file:

```
5b:aa:55:43:74:08:ef:e9:dd:0f:52:3a:7c:98:a5:3c:b2:fd:32:ab
```

## 1. Build the bundle

```powershell
$env:GODOT_BIN   = 'C:\Godot\Godot_v4.7.2-stable_win64_console.exe'   # NOT the .NET build
$env:JAVA_HOME   = 'C:\Android\jdk17'
$env:MF_SIGNING_INFO = 'C:\secure\mixingflavorsinfo.txt'
$env:MF_KEYSTORE    = 'C:\secure\mixingflavors-upload.jks'

npm run build:android
npm run verify:android
```

The Godot .NET/Mono build cannot export Android at all. An `.aab` also requires
the Gradle build, so this needs the JDK, the Android SDK, and a warm Gradle
cache; the first run takes a while while AGP and AndroidX download.

## 2. Create the app

This is a browser-console action. The API cannot do it.

1. Open <https://play.google.com/console> and confirm **Mixing Flavors: Voxel
   Gauntlet** has no existing entry. The package name is taken permanently.
2. **Create app** → name `Mixing Flavors: Voxel Gauntlet` → default language
   `English (United States)` → type **App** → free → accept the declarations.
3. Complete the four required setup cards: App details, App content, Ads,
   Data safety.

## 3. Turn on Play App Signing

1. **Release → Setup → App signing**.
2. Choose **Use Play App Signing**. Apps created after August 2021 cannot opt out.
3. Under **Upload key certificate**, enrol the generated key:
   - New app: choose the option to upload a certificate and provide
     `C:\secure\mixingflavors-upload-cert.pem`.
   - Or paste the SHA-1 above if Play offers a fingerprint field.
4. Play generates and holds the **app signing key**. Bundles you upload are
   signed with your upload key; Play re-signs for distribution.

## 4. Fill the store listing

**Grow → Store presence → Main store listing**

| Field | Source |
| --- | --- |
| App icon | `store\play\play_icon_512.png` |
| Feature graphic | `store\play\feature_graphic_1024x500.png` |
| App name | `store\play\listing_copy.txt` |
| Short description | `store\play\listing_copy.txt` |
| Full description | `store\play\listing_copy.txt` |

Two or more phone screenshots are required for a **production** release. They are
not required for internal testing, so they can wait — but the app must not reach
production without them, and they must be genuine captures of the game.

## 5. Complete the declarations

From `store\play\listing_copy.txt`:

- **Content rating** — expect **Everyone**: no user-generated content, no chat, no
  purchases, no ads.
- **Data safety** — **no data collected, no data shared**. The merged manifest
  requests only `VIBRATE` and no `INTERNET` permission, and no analytics SDK is
  bundled, so this is verifiable from the artifact. Any future change here must be
  a deliberate product and privacy update, per `AGENTS.md`.
- **Privacy policy** — a publicly reachable URL is required.
- **App access** — all functionality is available without restrictions.

## 6. Create a service account for the upload

Only needed if you want `npm run publish:play` to do the upload instead of the
browser. If you would rather upload by hand, skip to step 7.

**Already done on this machine:** the key is at
`C:\secure\play-service-account.json` (ACL locked to the current user), and
`npm run publish:play -- --dry-run` authenticates against the Play Developer API
successfully with it. Steps 1–5 below only have to be redone on a new machine.

1. **Play Console → Users and permissions → Invite new users**.
2. Invite a Google account, or create a service account under
   [Google Cloud IAM](https://console.cloud.google.com/iam-admin/serviceaccounts)
   and add its `...iam.gserviceaccount.com` email here.
3. Grant it the **Release manager** permission, scoped to this app only.
4. On the service account page, create a JSON key and download it.
5. Store the key **outside the repository**:

```powershell
Move-Item "$env:USERPROFILE\Downloads\<key>.json" C:\secure\play-service-account.json
$env:GOOGLE_PLAY_SERVICE_ACCOUNT_JSON = 'C:\secure\play-service-account.json'
```

## 7. Upload the bundle

### Option A — automated (needs step 6)

```powershell
npm run publish:play -- --dry-run   # checks credentials and app access, uploads nothing
npm run publish:play                # uploads, attaches to internal, commits
```

The script opens an edit, uploads the bundle, attaches the new `versionCode` to
the `internal` track with release notes, and commits. The private key is only
used in memory and is never printed.

### Option B — manual

1. **Testing → Internal testing → Create new release**.
2. Upload `build\android\MixingFlavorsVoxelGauntlet.aab`. Play validates the
   signature against the enrolled upload certificate and reports the target API
   level.
3. Add release notes. Internal testing skips the review queue, so notes are for
   testers only.
4. **Save → Start rollout to internal testing**. Select 100% unless you want a
   staged ramp.
5. Testers join from the Play Store opt-in link, or from **Internal testing →
   Testers → Manage testers** by email or Google Group.

## 8. Before you go further

- [ ] Back up `C:\secure\mixingflavors-upload.jks` to a second location. Losing
      it means losing the ability to upload updates; Play cannot reissue an
      upload key.
- [ ] Install the build on a **physical arm64 phone** and walk through pause/resume,
      audio, haptics, safe areas and a sustained run. No device has run this
      build yet, so frame rate, memory and thermal behaviour are unmeasured.
- [ ] Increment `version/code` in `export_presets.cfg` before every subsequent
      upload. Play rejects a duplicate version code.
- [ ] Confirm the release notes never promise something the build does not do.

## 9. Regenerating store assets

The SVGs in `assets\branding\` are the source of truth; the PNGs are generated.

```powershell
godot --headless --path . -s tools/branding/generate_store_assets.gd
```

The generator fails the run if a Play icon is not fully opaque, if a themed icon
has non-transparent corners or no mark in the centre, or if any export rasterizes
to a single flat colour.

## Troubleshooting

**`The upload key certificate is not enrolled`** — the build was signed with a
keystore other than the one enrolled in step 3. Compare the signer against the
SHA-1 above:

```powershell
$env:JAVA_HOME = 'C:\Android\jdk17'
& C:\Android\Sdk\build-tools\36.1.0\apksigner.bat verify --print-certs `
    <extracted base-master.apk from the .apks archive>
```

**`Signer #1 certificate DN: CN=Android Debug`** — the bundle was debug-signed, so
it is not uploadable. Build through `npm run build:android` with the signing
variables set; it injects the release keystore and restores the preset
afterwards, and fails loudly if a password survives the restore.

**`Your bundle does not support the target API level`** — `gradle_build/target_sdk`
must stay at 36; raise it if Google raises the requirement, never lower it.

**Play Console says the app does not exist** — the API can only manage an app that
already exists. Create it in the browser (step 2) first.

**`access denied` from `npm run publish:play`** — the service account is not
shared with this app, or lacks the Release manager role. See step 6.

**`Android build template not installed`** — install the Android export templates
for your exact Godot version. `build:android` unpacks the Gradle template itself;
it does not install the templates.

## Still unproven

Recorded honestly in `docs/android_release.md`: no device run, no Play Console
validation, no CI signing, and 16 KB page alignment proven only by reading the ELF
headers rather than on a 16 KB-page-size device.
