'use strict';

// Uploads a signed App Bundle to Google Play internal testing through the
// Google Play Developer API.
//
//   npm run publish:play            # validate, then upload and roll out
//   npm run publish:play -- --dry-run
//
// This is the automatable half of a Play release. It CANNOT create the app,
// accept the developer declarations, enrol the upload key, or fill the store
// listing: those are browser-console actions tied to the account holder and the
// API refuses them. Do those by hand first (see store/PLAY_CONSOLE.md), then run
// this.
//
// Required environment:
//   GOOGLE_PLAY_SERVICE_ACCOUNT_JSON  path to a Play Console service account
//                                     key JSON, with the "Release manager" role on
//                                     this app and Play App Signing enabled.
//
// Optional:
//   MF_PACKAGE_ID   defaults to the Android preset's package/unique_name
//   MF_AAB          defaults to build/android/MixingFlavorsVoxelGauntlet.aab
//   MF_TRACK        defaults to "internal"
//   MF_RELEASE_NOTES_FILE  defaults to a short note written to the release

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const ROOT = path.resolve(__dirname, '..');
const PRESET_PATH = path.join(ROOT, 'export_presets.cfg');
const API = 'https://androidpublisher.googleapis.com/androidpublisher/v3';
const TOKEN_URL = 'https://oauth2.googleapis.com/token';
const SCOPE = 'https://www.googleapis.com/auth/androidpublisher';
const DRY_RUN = process.argv.includes('--dry-run');

const DEFAULT_NOTES = [
    'First internal build of Mixing Flavors: Voxel Gauntlet.',
    '- 3D Picross deduction: read the face clues, hammer the empty blocks, mark what must stay.',
    '- Deterministic Gauntlet: the same seed always produces the same puzzle sequence.',
    '- Landscape-first, fully offline, no ads and no purchases.',
].join('\n');

function fail(message) {
    console.error(`[publish:play] ERROR: ${message}`);
    process.exit(1);
}

function readPresetValue(key) {
    if (!fs.existsSync(PRESET_PATH)) return null;
    const text = fs.readFileSync(PRESET_PATH, 'utf8');
    const match = text.match(new RegExp('^' + key.replace('/', '\\/') + '="([^"]*)"', 'm'));
    return match ? match[1] : null;
}

function base64url(buffer) {
    return buffer.toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

/**
 * Mints an access token from a service account key using the JWT bearer flow.
 * The private key is only ever used in memory and is never printed.
 */
function accessToken(credentials) {
    const issued = Math.floor(Date.now() / 1000);
    const header = base64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
    const claims = base64url(JSON.stringify({
        iss: credentials.client_email,
        scope: SCOPE,
        aud: TOKEN_URL,
        iat: issued,
        exp: issued + 3600,
    }));
    const signature = crypto.sign('RSA-SHA256', Buffer.from(`${header}.${claims}`), credentials.private_key);
    const assertion = `${header}.${claims}.${base64url(signature)}`;

    const response = request('POST', TOKEN_URL,
        `grant_type=${encodeURIComponent('urn:ietf:params:oauth:grant-type:jwt-bearer')}`
        + `&assertion=${encodeURIComponent(assertion)}`,
        { 'Content-Type': 'application/x-www-form-urlencoded' });
    if (!response.token) {
        fail(`could not mint an access token. Is the service account valid and is its private key readable?\n${JSON.stringify(response, null, 2)}`);
    }
    return response.token;
}

function request(method, url, body, extraHeaders = {}) {
    const headers = { ...extraHeaders };
    if (body && !headers['Content-Type']) headers['Content-Type'] = 'application/json';
    const result = spawnSyncCurl(method, url, body, headers);
    let parsed = null;
    if (result.stdout) {
        try {
            parsed = JSON.parse(result.stdout);
        } catch {
            parsed = { raw: result.stdout };
        }
    }
    return { status: result.status, body: parsed || {}, text: result.stdout || '' };
}

/** Uses the bundled fetch so no HTTP client dependency is required. */
function spawnSyncCurl(method, url, body, headers) {
    const script = `
        const [,, method, url, body, headersJson] = process.argv;
        (async () => {
            const res = await fetch(url, {
                method,
                headers: JSON.parse(headersJson || '{}'),
                body: body === undefined || body === '' ? undefined : body,
            });
            const text = await res.text();
            process.stdout.write(JSON.stringify({ status: res.status, stdout: text }));
        })().catch((e) => {
            process.stdout.write(JSON.stringify({ status: -1, stdout: String(e && e.message || e) }));
        });
    `;
    const headerJson = JSON.stringify(headers);
    const result = require('child_process').spawnSync(
        process.execPath, ['-e', script, method, url, body === undefined ? '' : body, headerJson],
        { encoding: 'utf8', maxBuffer: 512 * 1024 * 1024 },
    );
    if (result.status !== 0) {
        return { status: -1, stdout: result.stderr || 'request failed' };
    }
    try {
        const parsed = JSON.parse(result.stdout);
        return { status: parsed.status, stdout: parsed.stdout };
    } catch {
        return { status: -1, stdout: result.stdout };
    }
}

function api(token, packageId, method, endpoint, body) {
    return request(method, `${API}/applications/${packageId}${endpoint}`, body, { Authorization: `Bearer ${token}` });
}

/** Explains the API's error object in the operator's terms. */
function explain(status, body, context) {
    const detail = body && body.error && body.error.message ? body.error.message : JSON.stringify(body);
    if (status === 404) {
        return `${context}: the app was not found.\n`
            + '  The Play Developer API can only manage an app that already exists.\n'
            + '  Create it in the browser first (store/PLAY_CONSOLE.md step 2), then retry.';
    }
    if (status === 403) {
        return `${context}: access denied.\n`
            + '  Check that the service account is shared with this app in Play Console\n'
            + '  (Users and permissions) and has the "Release manager" role.';
    }
    if (status === 401) {
        return `${context}: the access token was rejected. The service account key is probably wrong or disabled.`;
    }
    return `${context}: HTTP ${status}\n  ${detail}`;
}

function main() {
    const packageId = process.env.MF_PACKAGE_ID || readPresetValue('package/unique_name');
    if (!packageId) fail('could not read package/unique_name from export_presets.cfg');
    const aabPath = process.env.MF_AAB || path.join(ROOT, 'build', 'android', 'MixingFlavorsVoxelGauntlet.aab');
    const track = process.env.MF_TRACK || 'internal';
    const keyPath = process.env.GOOGLE_PLAY_SERVICE_ACCOUNT_JSON
        || process.env.GOOGLE_APPLICATION_CREDENTIALS;

    console.log(`[publish:play] package : ${packageId}`);
    console.log(`[publish:play] track   : ${track}`);
    console.log(`[publish:play] bundle  : ${path.relative(ROOT, aabPath)}`);

    if (!fs.existsSync(aabPath)) {
        fail(`no bundle at ${aabPath}. Run: npm run build:android`);
    }
    if (!keyPath) {
        fail([
            'no Play Console credentials are available on this machine.',
            '',
            '  GOOGLE_PLAY_SERVICE_ACCOUNT_JSON is not set, and no gcloud auth exists.',
            '  The upload cannot be performed without it, and this script will not',
            '  pretend otherwise.',
            '',
            '  To fix, see store/PLAY_CONSOLE.md step 8: create a service account in',
            '  Play Console, grant it "Release manager" on this app, download the JSON',
            '  key to a path outside the repository, and set:',
            '    $env:GOOGLE_PLAY_SERVICE_ACCOUNT_JSON = "C:\\secure\\play-service-account.json"',
        ].join('\n'));
    }
    if (!fs.existsSync(keyPath)) {
        fail(`the service account key path does not exist: ${keyPath}`);
    }

    let credentials;
    try {
        credentials = JSON.parse(fs.readFileSync(keyPath, 'utf8'));
    } catch (error) {
        fail(`could not parse the service account key as JSON: ${error.message}`);
    }
    if (credentials.type !== 'service_account' || !credentials.private_key || !credentials.client_email) {
        fail('that file is not a service account key (expected type "service_account" with client_email and private_key).');
    }
    console.log(`[publish:play] identity: ${credentials.client_email}`);

    const token = accessToken(credentials);

    // Confirm the app exists and the account can see it before touching an edit.
    const tracks = api(token, packageId, 'GET', '/edits');
    if (tracks.status !== 200) {
        fail(explain(tracks.status, tracks.body, 'could not open an edit on the app'));
    }
    const internal = ((tracks.body.tracks || []).find((t) => t.track === track));
    console.log(`[publish:play] track "${track}" exists: ${internal ? 'yes' : 'no (it will be created by the update)'}`);

    if (DRY_RUN) {
        console.log('[publish:play] dry run: credentials are valid and the app is reachable. Nothing was uploaded.');
        return;
    }

    const editId = tracks.body.id;
    if (!editId) fail('the API did not return an edit id.');

    const aab = fs.readFileSync(aabPath);
    console.log(`[publish:play] uploading ${(aab.length / 1048576).toFixed(1)} MB...`);
    const upload = request(
        'POST',
        `${API}/applications/${packageId}/edits/${editId}/bundles?uploadType=media`,
        aab.toString('base64'),
        { Authorization: `Bearer ${token}`, 'Content-Type': 'application/octet-stream' },
    );
    const uploaded = upload.body && upload.body.versionCode ? upload.body : JSON.parse(upload.text || '{}');
    if (!uploaded || !uploaded.versionCode) {
        fail(explain(upload.status, upload.body || { raw: upload.text }, 'the bundle upload failed')
            + '\n  If Play reports an unenrolled upload key, enrol mixingflavors-upload-cert.pem first (step 3).');
    }
    const versionCode = Number(uploaded.versionCode);
    console.log(`[publish:play] uploaded versionCode ${versionCode}`);

    const notesFile = process.env.MF_RELEASE_NOTES_FILE;
    const notes = notesFile && fs.existsSync(notesFile)
        ? fs.readFileSync(notesFile, 'utf8').trim()
        : (process.env.MF_RELEASE_NOTES || DEFAULT_NOTES).trim();

    const release = {
        name: `${versionCode} (1)`,
        versionCodes: [String(versionCode)],
        releaseNotes: [{ language: 'en-US', text: notes }],
        status: 'completed',
    };
    if (internal && internal.releases && internal.releases.length > 0) {
        // Preserve anything already on the track rather than replacing it.
        for (const existing of internal.releases) {
            release.name = `${versionCode} (${internal.releases.length + 1})`;
        }
    }
    const update = api(token, packageId, 'PUT', `/edits/${editId}/tracks/${track}`, JSON.stringify(release));
    if (update.status !== 200) {
        fail(explain(update.status, update.body, 'could not attach the release to the track'));
    }
    console.log(`[publish:play] attached to ${track} as "${release.name}"`);

    const commit = api(token, packageId, 'POST', `/edits/${editId}:commit`, '');
    if (commit.status !== 200) {
        fail(explain(commit.status, commit.body, 'the edit could not be committed'));
    }
    console.log(`[publish:play] committed. Version ${versionCode} is live on ${track}.`);
    console.log('[publish:play] check Play Console > Testing > Internal testing for the release and the tester opt-in link.');
}

main();
