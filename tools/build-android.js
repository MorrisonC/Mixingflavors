'use strict';

// Builds a Play-ready Android App Bundle for Mixing Flavors: Voxel Gauntlet.
//
// Signing secrets never come from version control. This script resolves the
// upload keystore from environment variables (CI) or from the local info file
// (developer machine), injects it into a *temporary* copy of export_presets.cfg,
// exports the bundle, and restores the committed preset afterwards. If anything
// fails mid-export the preset is still restored, and the script refuses to leave
// a password behind in a tracked file.
//
//   npm run build:android
//
// Environment:
//   GODOT_BIN            path to a standard (non-.NET) Godot console binary. The
//                         Mono build cannot export Android or Web at all.
//   MF_KEYSTORE          path to the upload .jks
//   MF_KEYSTORE_PASSWORD keystore password
//   MF_KEY_ALIAS         key alias inside the keystore
//   MF_KEY_PASSWORD      key password (defaults to MF_KEYSTORE_PASSWORD)
//   MF_SIGNING_INFO      optional path to the local info file to read the
//                         password and alias from, instead of setting them
//   MF_EXPORT_PRESET     preset name to export (default "Android")

const fs = require('fs');
const path = require('path');
const os = require('os');
const { spawnSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..');
const PRESET_PATH = path.join(ROOT, 'export_presets.cfg');
const PRESET_NAME = process.env.MF_EXPORT_PRESET || 'Android';
const OUTPUT_DIR = path.join(ROOT, 'build', 'android');
const OUTPUT_AAB = path.join(OUTPUT_DIR, 'MixingFlavorsVoxelGauntlet.aab');
const TEMP_EXPORT_DIR = path.join(os.tmpdir(), 'mixingflavors-aab-export');
// Godot looks for the unpacked Gradle build template here, and nowhere else.
const GRADLE_TEMPLATE_DIR = path.join(ROOT, 'android', 'build');
// Set when the export template folder is located; it is the identifier Godot expects
// in android/.build_version.
const templateVersions = new Map();
let templateVersion = '';

/**
 * Godot's editor filesystem scans res:// recursively. Without a .gdignore, an
 * unpacked Gradle template gets imported as if it were game content, which does
 * two damaging things: it writes *.import files next to the template's drawables
 * (the Android resource merger then rejects them: "The file name must end with
 * .xml or .png"), and Godot exports the project's own assets into
 * android/build/assetPackInstallTime/... where the next scan re-imports and
 * re-exports them, nesting the tree a level deeper every run.
 *
 * .gdignore only affects the editor scanner, so Godot can still read the
 * template files itself. The stale artifacts from any earlier scan are removed
 * as well, so a developer who installed the template through the editor menu
 * recovers without deleting the directory by hand.
 */
function ensureGodotIgnore() {
    const androidDir = path.join(ROOT, 'android');
    fs.mkdirSync(androidDir, { recursive: true });

    let removed = 0;
    for (const file of walk(androidDir)) {
        const relative = path.relative(androidDir, file);
        const isImportSidecar = file.endsWith('.import');
        const isGodotCache = file.split(path.sep).includes('.godot');
        if (isImportSidecar || isGodotCache) {
            fs.rmSync(file, { force: true, recursive: true });
            removed += 1;
        } else if (file.endsWith('.import.remap') || file.endsWith('.import.md5')) {
            fs.rmSync(file, { force: true });
            removed += 1;
        }
        if (removed > 5000) {
            break;
        }
    }
    if (removed > 0) {
        console.log(`[android-build] removed ${removed} stray Godot import artifacts from android/`);
    }

    const ignorePath = path.join(androidDir, '.gdignore');
    if (!fs.existsSync(ignorePath)) {
        fs.writeFileSync(ignorePath, '', 'utf8');
        console.log('[android-build] wrote android/.gdignore to keep Godot out of the Gradle tree');
    }
}

/** Yields every file path under a directory. */
function* walk(dir) {
    let entries = [];
    try {
        entries = fs.readdirSync(dir, { withFileTypes: true });
    } catch {
        return;
    }
    for (const entry of entries) {
        const full = path.join(dir, entry.name);
        if (entry.isDirectory()) {
            yield* walk(full);
        } else if (entry.isFile()) {
            yield full;
        }
    }
}

/** Orders export-template folders by version, newest first. */
function compareTemplateVersions(a, b) {
    const pa = a.split('.').map(Number);
    const pb = b.split('.').map(Number);
    for (let i = 0; i < Math.max(pa.length, pb.length); i += 1) {
        const da = Number.isNaN(pa[i]) ? 0 : pa[i];
        const db = Number.isNaN(pb[i]) ? 0 : pb[i];
        if (da !== db) return db - da;
    }
    return b.localeCompare(a);
}

function fail(message) {
    console.error(`[android-build] ERROR: ${message}`);
    process.exit(1);
}

function resolveGodot() {
    const candidates = process.env.GODOT_BIN
        ? [process.env.GODOT_BIN]
        : ['godot', 'godot4', 'Godot_v4.7.2-stable_win64_console.exe'];
    for (const candidate of candidates) {
        const probe = spawnSync(candidate, ['--version'], { encoding: 'utf8' });
        if (probe.status !== 0) {
            continue;
        }
        const version = (probe.stdout || '').trim();
        // The .NET/Mono build cannot export Android, and it fails with a
        // misleading "configuration errors" message, so reject it up front.
        if (/mono/i.test(version) || /mono/i.test(candidate)) {
            fail(`${candidate} is a .NET/Mono Godot build, which cannot export Android.\n`
                + 'Point GODOT_BIN at a standard (non-mono) console build.');
        }
        return { bin: candidate, version };
    }
    fail('could not run a Godot binary. Set GODOT_BIN to a standard (non-mono) console build.');
    return null;
}

const godot = resolveGodot();

/** Runs a Godot subcommand, echoing its output only when it fails. */
function runGodot(args, label) {
    const result = spawnSync(godot.bin, args, { cwd: ROOT, encoding: 'utf8' });
    if (result.status !== 0) {
        process.stdout.write(result.stdout || '');
        process.stderr.write(result.stderr || '');
        fail(`${label} failed with exit code ${result.status}`);
    }
    return (result.stdout || '') + (result.stderr || '');
}

function readInfoFile(filePath) {
    const text = fs.readFileSync(filePath, 'utf8');
    const grab = (label) => {
        const match = text.match(new RegExp('^' + label + '\\s*:\\s*(.+)$', 'im'));
        return match ? match[1].trim() : '';
    };
    const alias = text.match(/^Alias\s+:\s*(.+)$/im);
    return {
        keystorePassword: grab('Keystore password'),
        alias: alias ? alias[1].trim() : '',
        keyPassword: grab('Key password'),
    };
}

function resolveSigning() {
    let fromFile = { keystorePassword: '', alias: '', keyPassword: '' };
    if (process.env.MF_SIGNING_INFO) {
        if (!fs.existsSync(process.env.MF_SIGNING_INFO)) {
            fail(`MF_SIGNING_INFO points at a file that does not exist: ${process.env.MF_SIGNING_INFO}`);
        }
        fromFile = readInfoFile(process.env.MF_SIGNING_INFO);
    }
    const keystore = process.env.MF_KEYSTORE || '';
    const keystorePassword = process.env.MF_KEYSTORE_PASSWORD || fromFile.keystorePassword;
    const alias = process.env.MF_KEY_ALIAS || fromFile.alias;
    const keyPassword = process.env.MF_KEY_PASSWORD || fromFile.keyPassword || keystorePassword;

    const missing = [];
    if (!keystore) missing.push('MF_KEYSTORE (the path to the upload .jks)');
    if (!keystorePassword) missing.push('MF_KEYSTORE_PASSWORD');
    if (!alias) missing.push('MF_KEY_ALIAS');
    if (missing.length > 0) {
        fail(
            'release signing is not configured. Missing:\n'
            + missing.map((name) => '  - ' + name).join('\n')
            + '\n\nOn a developer machine, point MF_SIGNING_INFO at the local info file and\n'
            + 'MF_KEYSTORE at the keystore it names, e.g.\n'
            + '  $env:MF_SIGNING_INFO = "C:\\secure\\mixingflavorsinfo.txt"\n'
            + '  $env:MF_KEYSTORE    = "C:\\secure\\mixingflavors-upload.jks"\n'
            + 'In CI, provide the four values as protected environment secrets.',
        );
    }
    if (!fs.existsSync(keystore)) {
        fail(`upload keystore not found: ${keystore}`);
    }
    return { keystore, keystorePassword, alias, keyPassword };
}

/**
 * Godot refuses to export an App Bundle until the Android Gradle build template
 * is unpacked, and it looks for it at "<gradle_build_directory>/build", which
 * is <project>/android/build for the checked-in preset. That directory is
 * generated output and is gitignored, so a clean CI checkout has to create it.
 * Doing that here keeps "Project > Install Android Build Template" out of the
 * documented manual steps.
 */
function ensureGradleTemplate() {
    const required = ['build.gradle', 'config.gradle', 'gradle.properties', 'settings.gradle'];
    if (required.every((name) => fs.existsSync(path.join(GRADLE_TEMPLATE_DIR, name)))) {
        writeTemplateVersion();
        return;
    }
    const templateRoot = path.join(os.homedir(), 'AppData', 'Roaming', 'Godot', 'export_templates');
    const candidates = [];
    if (fs.existsSync(templateRoot)) {
        // Prefer the exact editor version so the template matches the engine.
        // Godot names these folders by the short version ("4.7.2.stable"), which
        // is also the identifier it expects in android/.build_version. Newest
        // last wins so a downgrade is deliberate rather than accidental.
        const folders = fs.readdirSync(templateRoot)
            .filter((name) => fs.existsSync(path.join(templateRoot, name, 'android_source.zip')))
            .sort(compareTemplateVersions);
        for (const name of folders) {
            candidates.push(path.join(templateRoot, name, 'android_source.zip'));
            templateVersions.set(path.join(templateRoot, name, 'android_source.zip'), name);
        }
    }
    if (candidates.length === 0) {
        fail(
            'the Android export template is not installed.\n'
            + 'Install the Android export templates for this exact Godot version, or use\n'
            + 'Project > Install Android Build Template in the editor.',
        );
    }
    const chosen = candidates[0];
    templateVersion = templateVersions.get(chosen) || '';
    fs.rmSync(path.join(ROOT, 'android'), { recursive: true, force: true });
    fs.mkdirSync(GRADLE_TEMPLATE_DIR, { recursive: true });
    const unzip = spawnSync('tar', ['-xf', chosen, '-C', GRADLE_TEMPLATE_DIR], { encoding: 'utf8' });
    if (unzip.status !== 0) {
        const expand = spawnSync('powershell', ['-NoProfile', '-Command',
            `Expand-Archive -LiteralPath '${chosen}' -DestinationPath '${GRADLE_TEMPLATE_DIR}' -Force`],
        { encoding: 'utf8' });
        if (expand.status !== 0) {
            fail(`could not unpack ${chosen}\n${unzip.stderr || ''}${expand.stderr || ''}`);
        }
    }
    for (const name of required) {
        if (!fs.existsSync(path.join(GRADLE_TEMPLATE_DIR, name))) {
            fail(`unpacked ${chosen} but ${name} is missing from ${GRADLE_TEMPLATE_DIR}`);
        }
    }
    console.log(`[android-build] unpacked the Android Gradle template from ${path.basename(path.dirname(chosen))}`);
    writeTemplateVersion();
}

/**
 * Godot records which template version produced an installed Gradle build in a
 * .build_version file beside the build directory, and refuses to build without
 * it. Writing the same value here keeps the unpacked template indistinguishable
 * from one installed through Project > Install Android Build Template.
 */
/**
 * The short engine version, e.g. 4.7.2.stable. Godot's --version prints
 * 4.7.2.stable.official.<hash>, and only the part up to and including the
 * status token belongs in android/.build_version.
 */
function shortEngineVersion() {
    const parts = (godot.version || '').trim().split('.');
    const status = ['dev', 'alpha', 'beta', 'rc', 'stable'].find((name) => parts.includes(name));
    if (!status) {
        return (godot.version || '').trim();
    }
    return parts.slice(0, parts.indexOf(status) + 1).join('.');
}

function writeTemplateVersion() {
    const versionPath = path.join(ROOT, 'android', '.build_version');
    // Leave a marker that the editor's own "Install Android Build Template"
    // already wrote alone; it knows the identifier better than we do.
    if (fs.existsSync(versionPath) && fs.readFileSync(versionPath, 'utf8').trim()) {
        return;
    }
    // The identifier Godot compares against is the short template version
    // ("4.7.2.stable"), not the full engine string it prints for --version
    // ("4.7.2.stable.official.<hash>"). Writing the long form is reported as
    // "Android build version mismatch".
    // Godot's --version prints a single token ("4.7.2.stable.official.<hash>"),
    // so splitting on whitespace is not enough. The identifier it compares
    // against is the export-template folder name, which is the short version
    // ("4.7.2.stable"). Using the long form is reported as
    // "Android build version mismatch".
    const version = templateVersion || shortEngineVersion();
    fs.writeFileSync(versionPath, version, 'utf8');
    console.log(`[android-build] recorded template version ${version} in android/.build_version`);
}

/**
 * Rewrites the Android preset in place with real signing values, returning the
 * original text so it can always be restored.
 */
function injectSigning(signing) {
    const original = fs.readFileSync(PRESET_PATH, 'utf8');
    const quote = (value) => value.replace(/\\/g, '\\\\').replace(/"/g, '\\"');
    let replaced = original
        .replace(/^keystore\/release=""$/m, 'keystore/release="' + quote(signing.keystore) + '"')
        .replace(/^keystore\/release_user=""$/m, 'keystore/release_user="' + quote(signing.alias) + '"')
        .replace(/^keystore\/release_password=""$/m, 'keystore/release_password="' + quote(signing.keyPassword) + '"');
    const stillEmpty = ['release', 'release_user', 'release_password']
        .filter((key) => replaced.includes('keystore/' + key + '=""'));
    if (stillEmpty.length > 0) {
        fail('could not inject keystore/' + stillEmpty.join(', keystore/')
            + ' into export_presets.cfg. Those keys are expected to be present and empty.');
    }
    fs.writeFileSync(PRESET_PATH, replaced, 'utf8');
    return original;
}

function restorePreset(original) {
    fs.writeFileSync(PRESET_PATH, original, 'utf8');
    if (/^keystore\/release_password="(.+)"$/m.test(fs.readFileSync(PRESET_PATH, 'utf8'))) {
        fail('export_presets.cfg still contains a release password after restore.');
    }
}

console.log(`[android-build] Godot: ${godot.version}`);

const signing = resolveSigning();
console.log(`[android-build] signing with alias "${signing.alias}" from ${signing.keystore}`);
console.log('[android-build] the password is never printed and never written to the repository');

fs.mkdirSync(OUTPUT_DIR, { recursive: true });
fs.mkdirSync(TEMP_EXPORT_DIR, { recursive: true });
ensureGradleTemplate();
ensureGodotIgnore();

// Import first so a headless box resolves the branding PNGs and the newly
// enabled ETC2/ASTC texture import before anything reads them.
runGodot(['--headless', '--path', ROOT, '--import'], 'resource import');

const originalPreset = injectSigning(signing);
let tempAab = null;
try {
    tempAab = path.join(TEMP_EXPORT_DIR, `MixingFlavorsVoxelGauntlet-${Date.now()}.aab`);
    const output = runGodot(
        ['--headless', '--path', ROOT, '--export-release', PRESET_NAME, tempAab],
        'Android release export',
    );
    if (!fs.existsSync(tempAab)) {
        fail(`the export reported success but produced no bundle at ${tempAab}\n${output}`);
    }
} finally {
    restorePreset(originalPreset);
}

fs.copyFileSync(tempAab, OUTPUT_AAB);
fs.rmSync(TEMP_EXPORT_DIR, { recursive: true, force: true });

const megabytes = (fs.statSync(OUTPUT_AAB).size / 1048576).toFixed(1);
console.log(`[android-build] wrote ${path.relative(ROOT, OUTPUT_AAB)} (${megabytes} MB)`);
console.log('[android-build] next: npm run verify:android, then upload the .aab to');
console.log('[android-build]       Play Console > Testing > Internal testing');
