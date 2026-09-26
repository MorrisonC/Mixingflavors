'use strict';

/**
 * Build the checked-in Web export with a deliberately small, cross-platform
 * orchestration layer.  The export preset is read from export_presets.cfg;
 * this script never swaps preset files.
 */

const childProcess = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const zlib = require('node:zlib');

const REQUIRED_GODOT_VERSION = '4.7.1';
const SUPPORTED_GODOT_VERSIONS = ['4.7.1', '4.7.2'];
const PROJECT_ROOT = path.resolve(__dirname, '..');
const BUILD_ROOT = path.join(PROJECT_ROOT, 'build');
const WEB_OUTPUT_DIR = path.join(BUILD_ROOT, 'web');
const WEB_OUTPUT_HTML = path.join(WEB_OUTPUT_DIR, 'index.html');
const PROJECT_FILE = path.join(PROJECT_ROOT, 'project.godot');
const EXPORT_PRESET_FILE = path.join(PROJECT_ROOT, 'export_presets.cfg');
const WEB_TEST_BUILD = process.env.WEB_TEST_BUILD === '1';
const EXPORT_PRESET_NAME = WEB_TEST_BUILD ? 'WebTest' : 'Web';
const REQUIRED_WEB_FILES = ['index.html', 'index.js', 'index.wasm', 'index.pck'];
const COMPRESSIBLE_WEB_FILES = [...REQUIRED_WEB_FILES, 'index.audio.worklet.js'];
const FILE_TIME_TOLERANCE_MS = 2000;
const GODOT_STEP_TIMEOUT_MS = 10 * 60 * 1000;

function fail(message) {
    throw new Error(message);
}

function expandHome(filePath) {
    if (filePath === '~') {
        return os.homedir();
    }
    if (filePath.startsWith(`~${path.sep}`) || filePath.startsWith('~/')) {
        return path.join(os.homedir(), filePath.slice(2));
    }
    return filePath;
}

function uniquePaths(paths) {
    const seen = new Set();
    return paths.filter((candidate) => {
        if (!candidate) {
            return false;
        }
        const normalized = path.normalize(candidate);
        if (seen.has(normalized)) {
            return false;
        }
        seen.add(normalized);
        return true;
    });
}

function executableExtensions() {
    if (process.platform !== 'win32') {
        return [''];
    }
    return ['', '.exe'];
}

function isFile(candidate) {
    try {
        return fs.statSync(candidate).isFile();
    } catch (_error) {
        return false;
    }
}

function resolveExecutable(candidate) {
    const expanded = expandHome(candidate);
    if (path.isAbsolute(expanded)) {
        return isFile(expanded) ? expanded : null;
    }

    if (expanded.includes('/') || expanded.includes('\\')) {
        const relative = path.resolve(PROJECT_ROOT, expanded);
        return isFile(relative) ? relative : null;
    }

    const pathEntries = (process.env.PATH || '').split(path.delimiter).filter(Boolean);
    for (const pathEntry of pathEntries) {
        for (const extension of executableExtensions()) {
            const resolved = path.join(pathEntry, `${expanded}${extension}`);
            if (isFile(resolved)) {
                return resolved;
            }
        }
    }
    return null;
}

function configuredGodot() {
    return process.env.GODOT_BIN
        || process.env.GODOT_EXECUTABLE
        || process.env.GODOT_EXE
        || process.env.GODOT_PATH
        || process.env.GODOT
        || '';
}

function commonGodotCandidates() {
    const names = process.platform === 'win32'
        ? [
            'Godot_v4.7.1-stable_win64_console.exe',
            'Godot_v4.7.1-stable_win64.exe',
            'Godot_v4.7.2-stable_win64_console.exe',
            'Godot_v4.7.2-stable_win64.exe',
            'godot.exe',
            'godot4.exe',
        ]
        : [
            'godot',
            'godot4',
            'Godot',
            'Godot_v4.7.1-stable_linux.x86_64',
            'Godot_v4.7.2-stable_linux.x86_64',
        ];
    const directories = [
        process.env.GODOT_HOME,
        process.env.LOCALAPPDATA ? path.join(process.env.LOCALAPPDATA, 'Programs', 'Godot') : '',
        process.env.ProgramFiles ? path.join(process.env.ProgramFiles, 'Godot') : '',
        process.env['ProgramFiles(x86)'] ? path.join(process.env['ProgramFiles(x86)'], 'Godot') : '',
        process.env.USERPROFILE ? path.join(process.env.USERPROFILE, 'Downloads', 'Godot') : '',
        process.env.HOME ? path.join(process.env.HOME, '.local', 'bin') : '',
        path.join(os.tmpdir(), 'godot-4.7.1'),
        path.join(os.tmpdir(), 'godot-4.7.2'),
        path.join(os.tmpdir(), 'opencode', 'godot-4.7.1'),
        path.join(os.tmpdir(), 'opencode', 'godot-4.7.2'),
    ];
    if (process.platform !== 'win32') {
        directories.push('/usr/local/bin', '/usr/bin', '/opt/godot');
        if (process.platform === 'darwin') {
            directories.push('/Applications/Godot.app/Contents/MacOS');
        }
    }

    const candidates = [];
    for (const name of names) {
        candidates.push(name);
    }
    for (const directory of uniquePaths(directories)) {
        for (const name of names) {
            candidates.push(path.join(directory, name));
        }
    }
    return uniquePaths(candidates);
}

function versionFromOutput(result) {
    const output = `${result.stdout || ''}\n${result.stderr || ''}`;
    const match = output.match(/\b(\d+\.\d+\.\d+)(?:\.[^\s]+)?/);
    return match ? match[1] : '';
}

function isRequiredVersion(version) {
    return SUPPORTED_GODOT_VERSIONS.includes(version);
}

function probeGodot(candidate) {
    const executable = resolveExecutable(candidate);
    if (!executable) {
        return { candidate, executable: null, version: '', error: 'not found' };
    }

    const result = childProcess.spawnSync(executable, ['--version'], {
        cwd: PROJECT_ROOT,
        encoding: 'utf8',
        timeout: 10000,
        windowsHide: true,
    });
    if (result.error) {
        return { candidate, executable, version: '', error: result.error.message };
    }
    if (result.status !== 0) {
        return {
            candidate,
            executable,
            version: versionFromOutput(result),
            error: `exited with status ${result.status}`,
        };
    }

    const version = versionFromOutput(result);
    if (!version) {
        return { candidate, executable, version: '', error: 'did not report a version' };
    }
    return { candidate, executable, version, error: '' };
}

function findGodot() {
    const configured = configuredGodot();
    const candidates = configured ? [configured] : commonGodotCandidates();
    const failures = [];

    for (const candidate of uniquePaths(candidates)) {
        const probe = probeGodot(candidate);
        if (probe.executable && !probe.error && isRequiredVersion(probe.version)) {
            console.log(`[web-build] Using Godot ${probe.version}: ${probe.executable}`);
            return probe.executable;
        }

        const detail = probe.error
            ? probe.error
            : `reported version ${probe.version || 'unknown'}`;
        failures.push(`${candidate} (${detail})`);
        if (configured) {
            break;
        }
    }

    const source = configured
        ? `GODOT_BIN=${configured}`
        : 'PATH and common Godot installation locations';
    fail(`Godot ${SUPPORTED_GODOT_VERSIONS.join(' or ')} was not found via ${source}. `
        + `Set GODOT_BIN to a supported Godot ${SUPPORTED_GODOT_VERSIONS.join('/')} executable. `
        + `Candidates checked: ${failures.join(', ') || 'none'}`);
    return '';
}

function formatCommand(executable, args) {
    return [executable, ...args]
        .map((part) => (/\s/.test(part) ? JSON.stringify(part) : part))
        .join(' ');
}

function runGodot(executable, label, args) {
    console.log(`[web-build] ${label}: ${formatCommand(executable, args)}`);
    const maxAttempts = label === 'Importing project resources' ? 2 : 1;
    for (let attempt = 1; attempt <= maxAttempts; attempt += 1) {
        const result = childProcess.spawnSync(executable, args, {
            cwd: PROJECT_ROOT,
            env: process.env,
            encoding: 'utf8',
            maxBuffer: 16 * 1024 * 1024,
            timeout: GODOT_STEP_TIMEOUT_MS,
            stdio: ['ignore', 'pipe', 'pipe'],
            windowsHide: true,
        });

        if (result.stdout) {
            process.stdout.write(result.stdout);
        }
        if (result.stderr) {
            process.stderr.write(result.stderr);
        }
        if (result.error) {
            if (attempt < maxAttempts) {
                console.warn(`[web-build] ${label} could not start (${result.error.message}); retrying once.`);
                continue;
            }
            fail(`${label} could not start: ${result.error.message}`);
        }
        if (result.status !== 0) {
            if (attempt < maxAttempts) {
                console.warn(`[web-build] ${label} exited with ${result.status}; retrying once.`);
                continue;
            }
            const signal = result.signal ? ` (signal ${result.signal})` : '';
            fail(`${label} failed with exit status ${result.status}${signal}`);
        }
        return;
    }
}

function validateProjectSettings() {
    if (!isFile(PROJECT_FILE)) {
        fail(`Missing ${path.relative(PROJECT_ROOT, PROJECT_FILE)}.`);
    }

    const project = fs.readFileSync(PROJECT_FILE, 'utf8');
    const requiredSettings = [
        { pattern: /renderer\/rendering_method\s*=\s*"gl_compatibility"/, description: 'GL Compatibility as the desktop renderer' },
        { pattern: /renderer\/rendering_method\.mobile\s*=\s*"gl_compatibility"/, description: 'GL Compatibility as the mobile renderer' },
        { pattern: /config\/features\s*=\s*PackedStringArray\("4\.7"/, description: 'the Godot 4.7 project feature' },
    ];
    for (const setting of requiredSettings) {
        if (!setting.pattern.test(project)) {
            fail(`project.godot must declare ${setting.description} for the Web Compatibility build.`);
        }
    }

    const enabledScreenSpaceAa = project.match(/anti_aliasing\/quality\/screen_space_aa\s*=\s*([1-9][0-9]*)/);
    if (enabledScreenSpaceAa) {
        fail('project.godot enables screen-space AA, which is not supported by the GL Compatibility renderer.');
    }
}

function validateExportPreset() {
    if (!isFile(EXPORT_PRESET_FILE)) {
        fail(`Missing ${path.relative(PROJECT_ROOT, EXPORT_PRESET_FILE)}. `
            + 'The build uses the checked-in preset and does not create or swap presets.');
    }

    const preset = fs.readFileSync(EXPORT_PRESET_FILE, 'utf8');
    const presetMarker = `name="${EXPORT_PRESET_NAME}"`;
    const markerIndex = preset.indexOf(presetMarker);
    const blockStart = markerIndex >= 0 ? preset.lastIndexOf('[preset.', markerIndex) : -1;
    const nextBlock = markerIndex >= 0 ? preset.indexOf('\n[preset.', markerIndex + presetMarker.length) : -1;
    const selectedPreset = blockStart >= 0
        ? preset.slice(blockStart, nextBlock >= 0 ? nextBlock : preset.length)
        : '';
    const requiredSettings = [
        { pattern: new RegExp(`name\\s*=\\s*"${EXPORT_PRESET_NAME}"`), description: `a Web preset named "${EXPORT_PRESET_NAME}"` },
        { pattern: /platform\s*=\s*"Web"/, description: 'the Web platform' },
        { pattern: /variant\/extensions_support\s*=\s*false/, description: 'GDExtension support disabled' },
        { pattern: /variant\/thread_support\s*=\s*false/, description: 'single-threaded Web export' },
        { pattern: /vram_texture_compression\/for_desktop\s*=\s*true/, description: 'desktop VRAM compression enabled' },
        { pattern: /vram_texture_compression\/for_mobile\s*=\s*false/, description: 'mobile VRAM compression disabled for Compatibility rendering' },
        { pattern: /html\/head_include\s*=\s*""\s*$/m, description: 'no custom pixelated canvas CSS' },
        { pattern: /progressive_web_app\/enabled\s*=\s*false/, description: 'PWA disabled' },
        { pattern: /progressive_web_app\/ensure_cross_origin_isolation_headers\s*=\s*true/, description: 'the current PWA isolation option' },
        { pattern: /threads\/emscripten_pool_size\s*=\s*8/, description: 'the current Emscripten pool size option' },
        { pattern: /threads\/godot_pool_size\s*=\s*4/, description: 'the current Godot pool size option' },
    ];
    if (WEB_TEST_BUILD && !/custom_features\s*=\s*"[^"]*\be2e\b[^"]*"/.test(selectedPreset)) {
        fail('WebTest must enable the e2e custom feature for the browser test bridge.');
    }
    if (!WEB_TEST_BUILD && /custom_features\s*=\s*"[^"]*\be2e\b[^"]*"/.test(selectedPreset)) {
        fail('The production Web preset must not enable the e2e test feature.');
    }
    if (!WEB_TEST_BUILD && !selectedPreset.includes('scripts/test_bridge.gd')) {
        fail('The production Web preset must exclude scripts/test_bridge.gd.');
    }
    if (WEB_TEST_BUILD && selectedPreset.includes('scripts/test_bridge.gd')) {
        fail('The WebTest preset must retain the test bridge for Playwright.');
    }
    for (const setting of requiredSettings) {
        if (!setting.pattern.test(preset)) {
            fail(`export_presets.cfg must contain ${setting.description}; refusing to build with a different Web configuration.`);
        }
    }

    const forbiddenSettings = [
        { pattern: /variant\/export_type\s*=/, description: 'the removed variant/export_type option' },
        { pattern: /memory\/initial_pages\s*=/, description: 'the removed memory/initial_pages option' },
        { pattern: /vram_texture_compression\/for_web\s*=/, description: 'the removed vram_texture_compression/for_web option' },
        { pattern: /image-rendering\s*:\s*pixelated/i, description: 'pixelated canvas CSS' },
    ];
    for (const setting of forbiddenSettings) {
        if (setting.pattern.test(preset)) {
            fail(`export_presets.cfg still contains ${setting.description}; refusing to build.`);
        }
    }

    for (const requiredExclusion of [
        'test/**',
        'tests/**',
        'addons/gut/**',
        'tools/**',
        'node_modules/**',
        'test-results/**',
        'playwright-report/**',
        'assets/puzzles/*_puzzles.json',
        'package.json',
        'package-lock.json',
        'build_manifest.json',
    ]) {
        if (!preset.includes(requiredExclusion)) {
            fail(`export_presets.cfg must exclude ${requiredExclusion} from the Web release.`);
        }
    }
}

function cleanWebOutput() {
    if (path.dirname(WEB_OUTPUT_DIR) !== BUILD_ROOT || path.basename(WEB_OUTPUT_DIR) !== 'web') {
        fail(`Refusing to clean unexpected output path: ${WEB_OUTPUT_DIR}`);
    }

    console.log(`[web-build] Cleaning generated directory: ${path.relative(PROJECT_ROOT, WEB_OUTPUT_DIR)}`);
    fs.rmSync(WEB_OUTPUT_DIR, { recursive: true, force: true });
    fs.mkdirSync(WEB_OUTPUT_DIR, { recursive: true });

    if (fs.readdirSync(WEB_OUTPUT_DIR).length !== 0) {
        fail(`Generated Web directory was not empty after cleaning: ${WEB_OUTPUT_DIR}`);
    }
}

function createBrotliAssets() {
    for (const fileName of COMPRESSIBLE_WEB_FILES) {
        const sourcePath = path.join(WEB_OUTPUT_DIR, fileName);
        if (!isFile(sourcePath)) {
            continue;
        }
        const source = fs.readFileSync(sourcePath);
        const compressed = zlib.brotliCompressSync(source, {
            params: {
                [zlib.constants.BROTLI_PARAM_QUALITY]: 5,
                [zlib.constants.BROTLI_PARAM_SIZE_HINT]: source.length,
            },
        });
        const outputPath = `${sourcePath}.br`;
        fs.writeFileSync(outputPath, compressed);
        const sourceSize = fs.statSync(sourcePath).size;
        const compressedSize = compressed.length;
        const reduction = sourceSize > 0 ? (100 * (1 - compressedSize / sourceSize)).toFixed(1) : '0.0';
        console.log(`[web-build] Brotli ${fileName}: ${sourceSize} -> ${compressedSize} bytes (${reduction}% smaller)`);
    }
}

function verifyWebOutput(buildStartedAt) {
    if (!fs.existsSync(WEB_OUTPUT_HTML)) {
        fail(`Godot export completed without the expected HTML file: ${WEB_OUTPUT_HTML}`);
    }

    for (const fileName of REQUIRED_WEB_FILES) {
        const filePath = path.join(WEB_OUTPUT_DIR, fileName);
        if (!isFile(filePath)) {
            fail(`Godot export completed without required output: ${fileName}`);
        }
        const stat = fs.statSync(filePath);
        if (stat.size <= 0) {
            fail(`Godot produced an empty output file: ${fileName}`);
        }
        if (stat.mtimeMs + FILE_TIME_TOLERANCE_MS < buildStartedAt) {
            fail(`Output ${fileName} predates this build; stale artifacts are not allowed.`);
        }
    }

    const html = fs.readFileSync(WEB_OUTPUT_HTML, 'utf8');
    if (!html.includes('index.js') || !html.includes('index.pck') || !html.includes('index.wasm')) {
        fail('The exported index.html does not reference the expected JavaScript, PCK, and WASM outputs.');
    }
    if (!/GODOT_THREADS_ENABLED\s*=\s*false/.test(html)) {
        fail('The Web export is not single-threaded as required by the checked-in preset.');
    }
    for (const unexpectedPwaFile of ['index.manifest.json', 'index.service.worker.js']) {
        if (fs.existsSync(path.join(WEB_OUTPUT_DIR, unexpectedPwaFile))) {
            fail(`PWA output ${unexpectedPwaFile} exists even though the release preset disables PWA.`);
        }
    }

    const wasm = fs.readFileSync(path.join(WEB_OUTPUT_DIR, 'index.wasm'));
    const wasmMagic = Buffer.from([0x00, 0x61, 0x73, 0x6d]);
    if (!wasm.subarray(0, wasmMagic.length).equals(wasmMagic)) {
        fail('index.wasm does not have a valid WebAssembly header.');
    }

    console.log(`[web-build] Verified fresh Godot ${SUPPORTED_GODOT_VERSIONS.join('/')} Web release in ${path.relative(PROJECT_ROOT, WEB_OUTPUT_DIR)}.`);
}

function runDataVerifier(script, label) {
    const result = childProcess.spawnSync(process.execPath, [path.join(__dirname, script)], {
        cwd: PROJECT_ROOT,
        encoding: 'utf8',
        timeout: 30000,
        windowsHide: true,
    });
    if (result.stdout) process.stdout.write(result.stdout);
    if (result.stderr) process.stderr.write(result.stderr);
    if (result.status !== 0) {
        fail(`${label} failed: ${result.error ? result.error.message : 'unknown error'}`);
    }
}

function buildWeb() {
    runDataVerifier('verify-catalog.js', 'Runtime catalog verification');
    runDataVerifier('verify-achievements.js', 'Achievement manifest verification');
    validateProjectSettings();
    validateExportPreset();
    const godot = findGodot();
    cleanWebOutput();
    const buildStartedAt = Date.now();
    const commonArguments = [
        '--headless',
        '--rendering-driver',
        'opengl3',
        '--path',
        PROJECT_ROOT,
    ];

    // In Godot 4, --import runs the editor import pass and exits when done.
    runGodot(godot, 'Importing project resources', [...commonArguments, '--import']);
    runGodot(godot, 'Exporting Web release', [
        ...commonArguments,
        '--export-release',
        EXPORT_PRESET_NAME,
        WEB_OUTPUT_HTML,
    ]);
    verifyWebOutput(buildStartedAt);
    createBrotliAssets();
}

if (require.main === module) {
    try {
        buildWeb();
    } catch (error) {
        console.error(`[web-build] ERROR: ${error instanceof Error ? error.message : String(error)}`);
        process.exitCode = 1;
    }
}

module.exports = {
    REQUIRED_GODOT_VERSION,
    SUPPORTED_GODOT_VERSIONS,
    WEB_OUTPUT_DIR,
    buildWeb,
    findGodot,
};
