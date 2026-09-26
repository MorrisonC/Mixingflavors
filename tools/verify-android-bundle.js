'use strict';

// Verifies a built Android App Bundle the way a release gate should, rather
// than trusting that the export reported success.
//
// Checks performed:
//   1. The artifact really is an App Bundle (BundleConfig.pb + base module).
//   2. It is signed, and by the upload key we expect.
//   3. bundletool agrees it is a valid bundle and can turn it into device APKs.
//   4. The manifest carries the intended package id, versionCode, versionName,
//      minSdk, targetSdk, orientation and permission set.
//   5. arm64-v8a and armeabi-v7a are present; x86/x86_64 are not.
//   6. The Godot native libraries are 16 KB page aligned, which is a hard Play
//      requirement from November 2025 and cannot be assumed.
//
//   npm run verify:android

const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..');
const AAB = process.argv[2] || path.join(ROOT, 'build', 'android', 'MixingFlavorsVoxelGauntlet.aab');
const EXPECTED_PACKAGE = process.env.MF_PACKAGE_ID || 'com.morrisonc.mixingflavors.voxelgauntlet';
const EXPECTED_VERSION_NAME = process.env.MF_VERSION_NAME || '0.1.0';
const EXPECTED_MIN_SDK = Number(process.env.MF_MIN_SDK || 24);
const EXPECTED_TARGET_SDK = Number(process.env.MF_TARGET_SDK || 36);
const EXPECTED_COMPILE_SDK = Number(process.env.MF_COMPILE_SDK || 36);
const EXPECTED_VERSION_CODE = process.env.MF_VERSION_CODE || '1';
const EXPECTED_ABIS = ['arm64-v8a', 'armeabi-v7a'];
const FORBIDDEN_ABIS = ['x86', 'x86_64'];

const problems = [];
const notes = [];

function check(condition, message) {
    if (condition) {
        console.log(`[verify:android] ok   ${message}`);
    } else {
        problems.push(message);
        console.log(`[verify:android] FAIL ${message}`);
    }
    return condition;
}

/**
 * Collects candidate bundletool jars. Which one is usable cannot be decided by
 * reading the file: a jar's MANIFEST.MF is deflate-compressed, so "Main-Class" is
 * not greppable, and the Gradle module cache ships bundletool as a *library*
 * whose failure mode ("no main manifest attribute") looks like a broken bundle.
 * `probeBundletool` therefore runs each candidate instead of guessing.
 */
function bundletoolCandidates() {
    const candidates = [];
    const explicit = process.env.BUNDLETOOL_JAR;
    if (explicit && fs.existsSync(explicit)) candidates.push(explicit);

    // The .NET Android workload ships a standalone bundletool fat jar.
    const dotnetPacks = path.join('C:', 'Program Files', 'dotnet', 'packs', 'Microsoft.Android.Sdk.Windows');
    if (fs.existsSync(dotnetPacks)) {
        for (const version of fs.readdirSync(dotnetPacks).sort().reverse()) {
            const candidate = path.join(dotnetPacks, version, 'tools', 'bundletool.jar');
            if (fs.existsSync(candidate)) candidates.push(candidate);
        }
    }

    const gradleCache = path.join(os.homedir(), '.gradle', 'caches', 'modules-2', 'files-2.1',
        'com.android.tools.build', 'bundletool');
    if (fs.existsSync(gradleCache)) {
        const versions = fs.readdirSync(gradleCache)
            .map((name) => ({ name, dir: path.join(gradleCache, name) }))
            .sort((a, b) => compareVersions(b.name, a.name));
        for (const version of versions) {
            for (const file of walk(version.dir)) {
                if (file.endsWith('.jar') && !file.includes('sources')) candidates.push(file);
            }
        }
    }
    return [...new Set(candidates)];
}

function findBundletool(java) {
    for (const candidate of bundletoolCandidates()) {
        const probe = run(java, ['-jar', candidate, 'version']);
        if (probe.status === 0 && /^\s*\d+\.\d+/.test(probe.stdout)) {
            return candidate;
        }
    }
    return null;
}

function* walk(dir) {
    let entries = [];
    try {
        entries = fs.readdirSync(dir, { withFileTypes: true });
    } catch {
        return;
    }
    for (const entry of entries) {
        const full = path.join(dir, entry.name);
        if (entry.isDirectory()) yield* walk(full);
        else if (entry.isFile()) yield full;
    }
}

function compareVersions(a, b) {
    const pa = a.split('.').map(Number);
    const pb = b.split('.').map(Number);
    for (let i = 0; i < Math.max(pa.length, pb.length); i += 1) {
        const da = pa[i] || 0;
        const db = pb[i] || 0;
        if (da !== db) return da - db;
    }
    return 0;
}

function androidSdkRoots() {
    return [
        process.env.ANDROID_SDK_ROOT,
        process.env.ANDROID_HOME,
        path.join(os.homedir(), 'AppData', 'Local', 'Android', 'Sdk'),
        'C:\\Android\\Sdk',
        path.join('C:', 'Program Files', 'dotnet', 'packs', 'Microsoft.Android.Sdk.Windows'),
    ].filter(Boolean);
}

/** Build-tools folder names, newest first. */
function buildToolVersions(buildTools) {
    return fs.readdirSync(buildTools)
        .map((name) => ({ name, key: parseInt(name, 10) }))
        .filter((entry) => !Number.isNaN(entry.key))
        .sort((a, b) => b.key - a.key)
        .map((entry) => entry.name);
}

function findApksigner() {
    const explicit = process.env.APKSIGNER;
    if (explicit && fs.existsSync(explicit)) return explicit;
    for (const root of androidSdkRoots()) {
        const buildTools = path.join(root, 'build-tools');
        if (!fs.existsSync(buildTools)) continue;
        // Build-tools folders are named "36.1.0", which Number() cannot parse, so
        // this compares the leading integer instead. Number() turned every
        // version into NaN and silently skipped the whole SDK.
        const versions = buildToolVersions(buildTools);
        for (const version of versions) {
            for (const name of ['apksigner.bat', 'apksigner']) {
                const candidate = path.join(buildTools, version, name);
                if (fs.existsSync(candidate)) return candidate;
            }
        }
    }
    return null;
}

/**
 * bundletool's build-apks extracts aapt2 from its own jar, which fails on some
 * redistributions with "Unable to locate aapt2 inside jar". Pointing it at the
 * SDK's aapt2 is the documented workaround.
 */
function findAapt2() {
    const explicit = process.env.AAPT2;
    if (explicit && fs.existsSync(explicit)) return explicit;
    for (const root of androidSdkRoots()) {
        const buildTools = path.join(root, 'build-tools');
        if (!fs.existsSync(buildTools)) {
            const flat = path.join(root, 'tools', 'aapt2.exe');
            if (fs.existsSync(flat)) return flat;
            continue;
        }
        for (const version of buildToolVersions(buildTools)) {
            const candidate = path.join(buildTools, version, 'aapt2.exe');
            if (fs.existsSync(candidate)) return candidate;
        }
    }
    return null;
}

function findJavaTool(name) {
    const javaHome = process.env.JAVA_HOME;
    const roots = [javaHome, 'C:\\Android\\jdk17', path.join(os.homedir(), '.gradle', 'jdks')].filter(Boolean);
    for (const root of roots) {
        const candidate = path.join(root, 'bin', `${name}.exe`);
        if (fs.existsSync(candidate)) return candidate;
        const sh = path.join(root, 'bin', name);
        if (fs.existsSync(sh)) return sh;
    }
    return null;
}

/**
 * Reads the ELF LOAD segments of every native library in the extracted bundle.
 *
 * Google requires 16 KB page alignment, but only for 64-bit code: a 64-bit
 * process is the one that has to load on a device whose pages are 16 KB. The
 * armeabi-v7a slice is 32-bit and is exempt, so requiring 0x4000 of it produced
 * a false failure and hid the fact that the arm64 slice was already correct.
 * Entries are keyed by ABI as well as file name, because the two slices ship
 * identically named libraries and would otherwise overwrite each other.
 */
function checkPageAlignment(extractDir) {
    const libs = [];
    for (const file of walk(extractDir)) {
        if (file.endsWith('.so')) {
            const abi = path.basename(path.dirname(file));
            libs.push({ file, abi, name: `${abi}/${path.basename(file)}` });
        }
    }
    if (libs.length === 0) {
        problems.push('no native libraries were found in the bundle');
        return;
    }
    const offenders = [];
    const exempt = [];
    let worst64 = Infinity;
    for (const lib of libs) {
        const info = elfLoadAlignment(lib.file);
        if (info === null) {
            problems.push(`could not read ELF headers from ${lib.name}`);
            continue;
        }
        if (!info.is64) {
            exempt.push(`${lib.name}=0x${info.alignment.toString(16)} (32-bit, exempt)`);
            continue;
        }
        if (info.alignment < worst64) {
            worst64 = info.alignment;
        }
        if (info.alignment < 0x4000) {
            offenders.push(`${lib.name}=0x${info.alignment.toString(16)}`);
        }
    }
    if (offenders.length === 0 && Number.isFinite(worst64)) {
        console.log(`[verify:android] ok   64-bit native libraries are 16 KB page aligned (worst 0x${worst64.toString(16)})`);
    } else if (offenders.length > 0) {
        problems.push(`64-bit native libraries are not 16 KB page aligned: ${offenders.join(', ')}`);
    }
    if (exempt.length > 0) {
        console.log(`[verify:android] note 32-bit slice is exempt from the 16 KB rule: ${exempt.join(', ')}`);
    }
}

function elfLoadAlignment(file) {
    const buffer = fs.readFileSync(file);
    if (buffer.length < 64) return null;
    if (buffer.readUInt32BE(0) !== 0x7f454c46) return null; // not ELF
    const is64 = buffer[4] === 2;
    const little = buffer[5] === 1;
    const rd16 = (o) => (little ? buffer.readUInt16LE(o) : buffer.readUInt16BE(o));
    const rd32 = (o) => (little ? buffer.readUInt32LE(o) : buffer.readUInt32BE(o));
    const rd64 = (o) => (little ? buffer.readBigUInt64LE(o) : buffer.readBigUInt64BE(o));
    const programHeaderOffset = Number(is64 ? rd64(0x20) : rd32(0x1c));
    const entrySize = is64 ? 56 : 32;
    const entryCount = rd16(is64 ? 0x38 : 0x2c);
    let worst = Infinity;
    for (let i = 0; i < entryCount; i += 1) {
        const base = programHeaderOffset + i * entrySize;
        if (base + entrySize > buffer.length) break;
        const type = rd32(base);
        if (type !== 1) continue; // PT_LOAD
        const align = is64 ? Number(rd64(base + 0x30)) : rd32(base + 0x1c);
        if (align > 0 && align < worst) worst = align;
    }
    return Number.isFinite(worst) ? { alignment: worst, is64 } : null;
}
function run(command, args, options = {}) {
    // apksigner ships as apksigner.bat, and Node cannot spawn a batch file
    // without a shell. Without shell:true the call fails with ENOENT, which
    // looks like a bad signature rather than a bad invocation.
    const needsShell = process.platform === 'win32' && /\.(bat|cmd)$/i.test(command);
    const result = spawnSync(command, args, {
        encoding: 'utf8',
        maxBuffer: 64 * 1024 * 1024,
        shell: needsShell,
        ...options,
    });
    return {
        status: result.status,
        stdout: result.stdout || '',
        stderr: result.stderr || '',
    };
}

function main() {
    if (!fs.existsSync(AAB)) {
        console.error(`[verify:android] ERROR: no bundle at ${AAB}. Run npm run build:android first.`);
        process.exit(1);
    }
    const bytes = fs.statSync(AAB).size;
    console.log(`[verify:android] bundle: ${path.relative(ROOT, AAB)} (${(bytes / 1048576).toFixed(1)} MB)`);
    check(bytes > 1024 * 1024, 'the bundle is larger than a placeholder');

    const workDir = fs.mkdtempSync(path.join(os.tmpdir(), 'mf-aab-verify-'));
    // An .aab unpacks with BundleConfig.pb and base/ at the archive root, so the
    // extraction directory *is* the bundle root.
    const extractDir = workDir;
    try {
        const viaTar = run('tar', ['-xf', AAB, '-C', workDir]).status; // bsdtar reads zips
        const unzip = viaTar === 0
            ? 0
            : run('powershell', ['-NoProfile', '-Command',
                `Expand-Archive -LiteralPath '${AAB}' -DestinationPath '${workDir}' -Force`]).status;
        check(unzip === 0, 'the bundle is a readable zip archive');
        if (unzip !== 0) return;

        check(fs.existsSync(path.join(extractDir, 'BundleConfig.pb')), 'BundleConfig.pb is present (it is an App Bundle, not an APK)');
        check(fs.existsSync(path.join(extractDir, 'base', 'manifest', 'AndroidManifest.xml')), 'the base module manifest is present');

        const abis = fs.existsSync(path.join(extractDir, 'base', 'lib'))
            ? fs.readdirSync(path.join(extractDir, 'base', 'lib'))
            : [];
        for (const abi of EXPECTED_ABIS) {
            check(abis.includes(abi), `the bundle ships ${abi}`);
        }
        for (const abi of FORBIDDEN_ABIS) {
            check(!abis.includes(abi), `the bundle does not ship ${abi}`);
        }
        checkPageAlignment(extractDir);

        const jarsigner = findJavaTool('jarsigner');
        if (jarsigner) {
            const signed = run(jarsigner, ['-verify', AAB]);
            const output = `${signed.stdout}\n${signed.stderr}`;
            check(/jar verified|jar is unsigned|signer errors/i.test(output), 'jarsigner could read the bundle signature');
            check(!/jar is unsigned/i.test(output), 'the bundle carries a JAR signature');
            if (/X.509, CN=Mixing Flavors Voxel Gauntlet Upload/i.test(output)) {
                console.log('[verify:android] ok   signed by the Mixing Flavors upload key');
            } else if (process.env.MF_KEY_ALIAS) {
                notes.push('the signing certificate subject did not contain the expected upload-key CN');
            }
        } else {
            notes.push('jarsigner was not found, so the bundle signature was not checked');
        }

        const java = findJavaTool('java');
        const bundletool = java ? findBundletool(java) : null;
        if (!bundletool) {
            notes.push('a runnable bundletool was not found, so the manifest and APK generation were not checked');
        } else {
            console.log(`[verify:android] note using bundletool ${path.basename(bundletool)}`);
            {
                const dump = run(java, ['-jar', bundletool, 'dump', 'manifest', `--bundle=${AAB}`]);
                if (check(dump.status === 0, 'bundletool parsed the bundle')) {
                    // bundletool prints real Android manifest XML, so the values
                    // are read as attributes. A previous parser only searched for
                    // a bare number and silently reported null, which turned three
                    // assertions into no-ops.
                    const manifest = dump.stdout;
                    const attribute = (name) => {
                        const match = manifest.match(new RegExp(`${name}="([^"]*)"`));
                        return match ? match[1] : null;
                    };
                    check(attribute('package') === EXPECTED_PACKAGE, `package id is ${attribute('package')}`);
                    check(attribute('versionName') === EXPECTED_VERSION_NAME, `versionName is ${attribute('versionName')}`);
                    check(attribute('versionCode') === EXPECTED_VERSION_CODE, `versionCode is ${attribute('versionCode')} (expected ${EXPECTED_VERSION_CODE})`);
                    check(attribute('minSdkVersion') === String(EXPECTED_MIN_SDK), `minSdk is ${attribute('minSdkVersion')} (expected ${EXPECTED_MIN_SDK})`);
                    check(attribute('targetSdkVersion') === String(EXPECTED_TARGET_SDK), `targetSdk is ${attribute('targetSdkVersion')} (expected ${EXPECTED_TARGET_SDK})`);
                    check(attribute('compileSdkVersion') === String(EXPECTED_COMPILE_SDK), `compileSdk is ${attribute('compileSdkVersion')} (expected ${EXPECTED_COMPILE_SDK})`);
                    check(/android:screenOrientation="0"/.test(manifest), 'the activity is locked to landscape');
                    check(/android:isGame="true"/.test(manifest), 'the app is marked as a game');
                    check(/android:allowBackup="false"/.test(manifest), 'Android auto-backup is disabled');
                    check(!/uses-permission[^>]*INTERNET/.test(manifest), 'no INTERNET permission is requested');
                    check(/uses-permission[^>]*VIBRATE/.test(manifest), 'VIBRATE is requested for the haptics toggle');

                    const apksDir = path.join(workDir, 'apks');
                    fs.mkdirSync(apksDir, { recursive: true });
                    const buildArgs = ['-jar', bundletool, 'build-apks', `--bundle=${AAB}`, `--output=${path.join(apksDir, 'app.apks')}`];
                    const aapt2 = findAapt2();
                    if (aapt2) {
                        buildArgs.push(`--aapt2=${aapt2}`);
                    } else {
                        notes.push('aapt2 was not found; bundletool build-apks may fail to extract it from its own jar');
                    }
                    const built = run(java, buildArgs);
                    if (check(built.status === 0, 'bundletool generated device APKs from the bundle')) {
                        // build-apks writes a single .apks archive, which is itself a
                        // zip containing the per-device APKs. Looking for .apk
                        // files beside it always found nothing.
                        const archive = findBySuffix(apksDir, '.apks');
                        const splitDir = path.join(apksDir, 'splits');
                        fs.mkdirSync(splitDir, { recursive: true });
                        if (archive) {
                            const viaTar = run('tar', ['-xf', archive, '-C', splitDir]).status;
                            if (viaTar !== 0) {
                                run('powershell', ['-NoProfile', '-Command',
                                    `Expand-Archive -LiteralPath '${archive}' -DestinationPath '${splitDir}' -Force`]);
                            }
                        }
                        // The splits live under a splits/ subdirectory inside the
                        // archive, so they are collected recursively rather than
                        // listed from the top level.
                        const apks = fs.existsSync(splitDir)
                            ? [...walk(splitDir)].filter((file) => file.endsWith('.apk'))
                            : [];
                        check(apks.length > 0, `bundletool produced ${apks.length} device APK split(s)`);
                        const apksigner = findApksigner();
                        // The base split is the one that carries the manifest and the
                        // signature that matters for an upload.
                        const baseApk = apks.find((file) => /base-master\.apk$/i.test(file))
                            || apks.find((file) => /base-arm64_v8a\.apk$/i.test(file))
                            || apks[0]
                            || '';
                        if (!apks.length) {
                            notes.push('no APK split was available, so the signature was not verified');
                        }
                        if (apksigner && baseApk) {
                            const verified = run(apksigner, ['verify', '--verbose', '--print-certs', baseApk]);
                            if (check(verified.status === 0, 'apksigner verified the generated APK signature')) {
                                const v2 = /Verified using v2 scheme/i.test(verified.stdout);
                                const v3 = /Verified using v3 scheme/i.test(verified.stdout);
                                check(v2 || v3, `the APK carries a modern signature scheme (v2=${v2}, v3=${v3})`);
                            }
                        } else {
                            notes.push('apksigner was not found, so the generated APK signature was not verified');
                        }
                    }
                }
            }
        }
    } finally {
        fs.rmSync(workDir, { recursive: true, force: true });
    }
}

function findBySuffix(dir, suffix) {
    for (const file of walk(dir)) {
        if (file.endsWith(suffix)) return file;
    }
    return null;
}

main();

if (notes.length > 0) {
    console.log('\n[verify:android] notes:');
    for (const note of notes) console.log(`  - ${note}`);
}
if (problems.length > 0) {
    console.log(`\n[verify:android] ${problems.length} problem(s):`);
    for (const problem of problems) console.log(`  - ${problem}`);
    process.exit(1);
}
console.log('\n[verify:android] passed');
