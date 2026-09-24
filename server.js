'use strict';

const express = require('express');
const fs = require('node:fs');
const path = require('node:path');
const zlib = require('node:zlib');
const { pipeline } = require('node:stream/promises');

const WEB_ROOT = path.resolve(__dirname, 'build', 'web');
const REQUIRED_FILES = ['index.html', 'index.js', 'index.wasm', 'index.pck'];
const DEFAULT_PORT = 8080;
const DEFAULT_HOST = '127.0.0.1';
const COMPRESSION_MIN_BYTES = 1024;

const MIME_TYPES = new Map([
    ['.html', 'text/html; charset=utf-8'],
    ['.js', 'text/javascript; charset=utf-8'],
    ['.mjs', 'text/javascript; charset=utf-8'],
    ['.css', 'text/css; charset=utf-8'],
    ['.json', 'application/json; charset=utf-8'],
    ['.wasm', 'application/wasm'],
    ['.pck', 'application/octet-stream'],
    ['.png', 'image/png'],
    ['.jpg', 'image/jpeg'],
    ['.jpeg', 'image/jpeg'],
    ['.gif', 'image/gif'],
    ['.svg', 'image/svg+xml'],
    ['.ico', 'image/x-icon'],
    ['.webp', 'image/webp'],
    ['.woff', 'font/woff'],
    ['.woff2', 'font/woff2'],
    ['.txt', 'text/plain; charset=utf-8'],
    ['.map', 'application/json; charset=utf-8'],
    ['.ogg', 'audio/ogg'],
    ['.wav', 'audio/wav'],
    ['.mp3', 'audio/mpeg'],
]);

const COMPRESSIBLE_EXTENSIONS = new Set([
    '.html',
    '.js',
    '.mjs',
    '.css',
    '.json',
    '.svg',
    '.wasm',
    '.pck',
    '.txt',
    '.map',
]);

function configuredPort() {
    const rawValue = process.env.PORT || String(DEFAULT_PORT);
    const port = Number(rawValue);
    if (!Number.isInteger(port) || port < 1 || port > 65535) {
        throw new Error(`PORT must be an integer between 1 and 65535; received ${rawValue}`);
    }
    return port;
}

function isInsideWebRoot(candidate) {
    const relative = path.relative(WEB_ROOT, candidate);
    return relative === ''
        || (relative !== '..'
            && !relative.startsWith(`..${path.sep}`)
            && !path.isAbsolute(relative));
}

function mimeTypeFor(filePath) {
    return MIME_TYPES.get(path.extname(filePath).toLowerCase()) || 'application/octet-stream';
}

function acceptsEncoding(headerValue, encoding) {
    if (!headerValue) {
        return false;
    }
    return headerValue.split(',').some((part) => {
        const pieces = part.trim().toLowerCase().split(';');
        if (pieces[0] !== encoding) {
            return false;
        }
        const qualityParameter = pieces.slice(1).find((parameter) => parameter.trim().startsWith('q='));
        if (!qualityParameter) {
            return true;
        }
        const quality = Number(qualityParameter.trim().slice(2));
        return Number.isFinite(quality) && quality > 0;
    });
}

function chooseEncoding(request, filePath, fileSize) {
    if (fileSize < COMPRESSION_MIN_BYTES || !COMPRESSIBLE_EXTENSIONS.has(path.extname(filePath).toLowerCase())) {
        return null;
    }
    const accepted = request.headers['accept-encoding'];
    if (acceptsEncoding(accepted, 'br')) {
        return 'br';
    }
    if (acceptsEncoding(accepted, 'gzip')) {
        return 'gzip';
    }
    return null;
}

function setSecurityHeaders(response) {
    // Godot's Web runtime requests cross-origin isolation.  These headers are
    // deliberately same-origin; this server does not opt into public CORS.
    response.setHeader('Cross-Origin-Opener-Policy', 'same-origin');
    response.setHeader('Cross-Origin-Embedder-Policy', 'require-corp');
    response.setHeader('Cross-Origin-Resource-Policy', 'same-origin');
    response.setHeader('X-Content-Type-Options', 'nosniff');
    response.setHeader('Referrer-Policy', 'no-referrer');
    response.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate, max-age=0');
    response.setHeader('Pragma', 'no-cache');
}

function requestPath(requestUrl) {
    let pathname;
    try {
        pathname = decodeURIComponent(new URL(requestUrl, 'http://localhost').pathname);
    } catch (_error) {
        return null;
    }
    if (pathname.includes('\0')) {
        return null;
    }

    const relativePath = pathname === '/' ? 'index.html' : pathname.replace(/^\/+/, '');
    const candidate = path.resolve(WEB_ROOT, relativePath);
    return isInsideWebRoot(candidate) ? candidate : null;
}

async function sendFile(request, response, filePath, fileStat) {
    const contentType = mimeTypeFor(filePath);
    const contentEncoding = chooseEncoding(request, filePath, fileStat.size);
    response.status(200);
    response.setHeader('Content-Type', contentType);
    response.setHeader('Vary', 'Accept-Encoding');

    if (contentEncoding) {
        response.setHeader('Content-Encoding', contentEncoding);
    } else {
        response.setHeader('Content-Length', String(fileStat.size));
    }

    if (request.method === 'HEAD') {
        response.end();
        return;
    }

    const source = fs.createReadStream(filePath);
    let destination = null;
    if (contentEncoding === 'br') {
        destination = zlib.createBrotliCompress();
    } else if (contentEncoding === 'gzip') {
        destination = zlib.createGzip();
    }

    if (destination) {
        await pipeline(source, destination, response);
    } else {
        await pipeline(source, response);
    }
}

function assertFreshBuildExists() {
    const missing = REQUIRED_FILES.filter((fileName) => {
        try {
            return !fs.statSync(path.join(WEB_ROOT, fileName)).isFile();
        } catch (_error) {
            return true;
        }
    });
    if (missing.length > 0) {
        throw new Error(`Web build is missing required file(s): ${missing.join(', ')}. `
            + 'Run `npm run build:web` before starting the server.');
    }
}

function createApp() {
    const app = express();
    app.disable('x-powered-by');
    app.use((request, response, next) => {
        setSecurityHeaders(response);
        next();
    });

    app.use((request, response, next) => {
        if (request.method !== 'GET' && request.method !== 'HEAD') {
            response.setHeader('Allow', 'GET, HEAD');
            response.status(405).type('text/plain').send('Method Not Allowed');
            return;
        }

        const filePath = requestPath(request.url);
        if (!filePath) {
            response.status(400).type('text/plain').send('Bad Request');
            return;
        }

        fs.stat(filePath, (statError, fileStat) => {
            if (statError || !fileStat.isFile()) {
                response.status(404).type('text/plain').send('Not Found');
                return;
            }

            sendFile(request, response, filePath, fileStat).catch((streamError) => {
                if (!response.headersSent) {
                    next(streamError);
                } else {
                    response.destroy(streamError);
                }
            });
        });
    });

    app.use((error, _request, response, _next) => {
        console.error(`[web-server] ${error instanceof Error ? error.stack : String(error)}`);
        if (!response.headersSent) {
            response.status(500).type('text/plain').send('Internal Server Error');
        } else {
            response.destroy();
        }
    });

    return app;
}

function startServer() {
    assertFreshBuildExists();
    const app = createApp();
    const port = configuredPort();
    const host = process.env.HOST || DEFAULT_HOST;
    const server = app.listen(port, host, () => {
        console.log(`Web server listening at http://${host}:${port}`);
    });
    server.on('error', (error) => {
        console.error(`[web-server] ${error instanceof Error ? error.message : String(error)}`);
        process.exitCode = 1;
    });
    return server;
}

if (require.main === module) {
    try {
        startServer();
    } catch (error) {
        console.error(`[web-server] ERROR: ${error instanceof Error ? error.message : String(error)}`);
        process.exitCode = 1;
    }
}

module.exports = {
    MIME_TYPES,
    WEB_ROOT,
    createApp,
    startServer,
};
