'use strict';

// Uploads a signed App Bundle to Google Play internal testing through the
// Google Play Developer API.
//
//   npm run publish:play                  # validate, upload, roll out
//   npm run publish:play -- --dry-run    # validate only, upload nothing
//
// This is the automatable half of a Play release. It CANNOT create the app,
// accept the developer declarations, enrol the upload key, or fill the store
// listing: those are browser-console actions tied to the account holder and the
// API refuses them. Do those by hand first (see store/PLAY_CONSOLE.md), then run
// this.
//
// Required environment:
//   GOOGLE_PLAY_SERVICE_ACCOUNT_JSON  path to a Play Console service account
//                                     key JSON with the "Release manager" role
//                                     on this app.
//
// Optional:
//   MF_PACKAGE_ID           defaults to the Android preset's package/unique_name
//   MF_AAB                  defaults to build/android/MixingFlavorsVoxelGauntlet.aab
//   MF_TRACK                defaults to "internal"
//   MF_RELEASE_NOTES        release notes text
//   MF_RELEASE_NOTES_FILE   path to a file holding the release notes

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

// Thrown instead of process.exit()ing: calling process.exit() while a fetch
// socket is still tearing down aborts the Node runtime on Windows
// ("Assertion failed: !(handle->flags & UV_HANDLE_CLOSING)") and buries the real
// error under a crash. The handler at the bottom sets the exit code and lets the
// event loop drain instead.
class PublishError extends Error {}

function fail(message) {
    throw new PublishError(message);
}

function readPresetValue(key) {
    if (!fs.existsSync(PRESET_PATH)) return null;
    const text = fs.readFileSync(PRESET_PATH, 'utf8');
    const match = text.match(new RegExp('^' + key.replace('/', '\\/') + '="([^"]*)"', 'm'));
    return match ? match[1] : null;
}

function base64url(input) {
    return Buffer.from(input).toString('base64')
        .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

/**
 * POSTs form data and returns { status, body }. A non-JSON body is preserved as
 * `text` so an HTML error page is still readable.
 */
async function postForm(url, form, headers = {}) {
    const response = await fetch(url, {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded', ...headers },
        body: new URLSearchParams(form).toString(),
    });
    const text = await response.text();
    return { status: response.status, body: parseJson(text), text };
}

async function callApi(token, packageId, method, endpoint, body) {
    const headers = { Authorization: `Bearer ${token}` };
    const init = { method, headers };
    if (body !== undefined && body !== null && body !== '') {
        headers['Content-Type'] = 'application/json';
        init.body = body;
    }
    const response = await fetch(`${API}/applications/${packageId}${endpoint}`, init);
    const text = await response.text();
    return { status: response.status, body: parseJson(text), text };
}

function parseJson(text) {
    if (!text) return {};
    try {
        return JSON.parse(text);
    } catch {
        return {};
    }
}

/**
 * Mints an access token from a service account key using the JWT bearer flow.
 * The private key is only ever used in memory and is never printed, logged, or
 * written to disk by this script.
 */
async function accessToken(credentials) {
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
    const response = await postForm(TOKEN_URL, {
        grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
        assertion,
    });
    if (!response.body || !response.body.access_token) {
        fail('could not mint an access token from the service account key.\n'
            + `  ${(response.body && response.body.error) || response.status}\n`
            + `  ${(response.body && response.body.error_description) || response.text.slice(0, 300)}\n`
            + '  Check that the key is active, that its clock is right, and that the private key is intact.');
    }
    return response.body.access_token;
}

/** Explains an API failure in the operator's terms instead of echoing JSON. */
function explain(status, body, context) {
    const detail = (body && body.error && body.error.message) ? body.error.message : JSON.stringify(body);
    if (status === 404) {
        return `${context}: the app was not found.\n`
            + '  The Play Developer API can only manage an app that already exists,\n'
            + '  and it reports a missing one the same way whether the app is absent or\n'
            + '  the service account has never been shared with it. So either:\n'
            + '    - the app does not exist yet: create it in the browser\n'
            + '      (store/PLAY_CONSOLE.md step 2), or\n'
            + '    - it exists but this service account cannot see it: share it in\n'
            + '      Play Console > Users and permissions with the "Release manager"\n'
            + '      role scoped to this app (step 6).';
    }
    if (status === 403) {
        return `${context}: access denied.\n`
            + '  Share the service account with this app in Play Console\n'
            + '  (Users and permissions) and give it the "Release manager" role.';
    }
    if (status === 401) {
        return `${context}: the access token was rejected. The service account key is wrong or disabled.`;
    }
    if (status === 400 && /version code|already been used|duplicate/i.test(detail)) {
        return `${context}: Play rejected this version code.\n`
            + '  Increment version/code in export_presets.cfg, rebuild, and retry. Play never\n'
            + '  accepts the same version code twice.';
    }
    if (status === 400 && /enrolled|certificate/i.test(detail)) {
        return `${context}: Play does not recognise the upload key.\n`
            + '  Enrol mixingflavors-upload-cert.pem first (store/PLAY_CONSOLE.md step 3).';
    }
    return `${context}: HTTP ${status}\n  ${detail}`;
}

function loadCredentials(keyPath) {
    if (!keyPath) {
        fail([
            'no Play Console credentials are available on this machine.',
            '',
            '  GOOGLE_PLAY_SERVICE_ACCOUNT_JSON is not set.',
            '  The upload cannot be performed without it, and this script will not pretend otherwise.',
            '',
            '  See store/PLAY_CONSOLE.md step 6, then:',
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
    return credentials;
}

function releaseNotes() {
    const notesFile = process.env.MF_RELEASE_NOTES_FILE;
    if (notesFile && fs.existsSync(notesFile)) {
        return fs.readFileSync(notesFile, 'utf8').trim();
    }
    return (process.env.MF_RELEASE_NOTES || DEFAULT_NOTES).trim();
}

async function main() {
    const packageId = process.env.MF_PACKAGE_ID || readPresetValue('package/unique_name');
    if (!packageId) fail('could not read package/unique_name from export_presets.cfg');
    const aabPath = process.env.MF_AAB || path.join(ROOT, 'build', 'android', 'MixingFlavorsVoxelGauntlet.aab');
    const track = process.env.MF_TRACK || 'internal';

    console.log(`[publish:play] package : ${packageId}`);
    console.log(`[publish:play] track   : ${track}`);
    console.log(`[publish:play] bundle  : ${path.relative(ROOT, aabPath)}`);

    if (!fs.existsSync(aabPath)) {
        fail(`no bundle at ${aabPath}. Run: npm run build:android`);
    }

    const credentials = loadCredentials(
        process.env.GOOGLE_PLAY_SERVICE_ACCOUNT_JSON || process.env.GOOGLE_APPLICATION_CREDENTIALS,
    );
    console.log(`[publish:play] identity: ${credentials.client_email}`);

    const token = await accessToken(credentials);
    console.log('[publish:play] authenticated with the Play Developer API');

    const edits = await callApi(token, packageId, 'GET', '/edits');
    if (edits.status !== 200) {
        fail(explain(edits.status, edits.body, 'could not open an edit on the app'));
    }
    const existing = (edits.body.tracks || []).find((t) => t.track === track);
    const existingReleases = (existing && existing.releases) || [];
    console.log(`[publish:play] track "${track}": ${existingReleases.length} existing release(s)`);

    if (DRY_RUN) {
        console.log('[publish:play] dry run: credentials are valid and the app is reachable. Nothing was uploaded.');
        return;
    }

    const editId = edits.body.id;
    if (!editId) fail('the API did not return an edit id.');

    // The bundle is uploaded as raw bytes, not JSON, so it is sent directly.
    const aab = fs.readFileSync(aabPath);
    console.log(`[publish:play] uploading ${(aab.length / 1048576).toFixed(1)} MB...`);
    const uploadResponse = await fetch(
        `${API}/applications/${packageId}/edits/${editId}/bundles?uploadType=media`,
        {
            method: 'POST',
            headers: {
                Authorization: `Bearer ${token}`,
                'Content-Type': 'application/octet-stream',
            },
            body: aab,
        },
    );
    const uploadText = await uploadResponse.text();
    const upload = parseJson(uploadText);
    if (!upload.versionCode) {
        fail(explain(uploadResponse.status, upload || { raw: uploadText.slice(0, 400) }, 'the bundle upload failed'));
    }
    const versionCode = Number(upload.versionCode);
    console.log(`[publish:play] uploaded versionCode ${versionCode}`);

    const release = {
        name: `${versionCode} (${existingReleases.length + 1})`,
        versionCodes: [String(versionCode)],
        releaseNotes: [{ language: 'en-US', text: releaseNotes() }],
        // "inProgress" keeps the release out of the review queue; internal
        // testing does not review, so a completed rollout is safe here.
        status: 'completed',
    };
    const update = await callApi(
        token, packageId, 'PUT', `/edits/${editId}/tracks/${track}`, JSON.stringify(release),
    );
    if (update.status !== 200) {
        fail(explain(update.status, update.body, `could not attach the release to the ${track} track`));
    }
    console.log(`[publish:play] attached to ${track} as "${release.name}"`);

    const commit = await callApi(token, packageId, 'POST', `/edits/${editId}:commit`, '');
    if (commit.status !== 200) {
        fail(explain(commit.status, commit.body, 'the edit could not be committed'));
    }
    console.log(`[publish:play] committed. Version ${versionCode} is live on ${track}.`);
    console.log('[publish:play] check Play Console > Testing > Internal testing for the release and the tester opt-in link.');
}

main().catch((error) => {
    if (error instanceof PublishError) {
        console.error(`[publish:play] ERROR: ${error.message}`);
    } else {
        console.error(`[publish:play] unexpected failure: ${error && error.message ? error.message : error}`);
        if (error && error.stack) console.error(error.stack);
    }
    process.exitCode = 1;
});
