#!/usr/bin/env node
// Minimal static server for local development and LAN access.
// Usage: node server.mjs [port]

import { createServer } from 'node:http';
import { readFile, stat } from 'node:fs/promises';
import { createReadStream } from 'node:fs';
import { extname, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { networkInterfaces } from 'node:os';

const root = resolve(fileURLToPath(new URL('.', import.meta.url)));
const rootPrefix = root.endsWith(sep) ? root : root + sep;
const port = Number(process.argv[2] || process.env.PORT || 8080);
const host = process.env.HOST || '0.0.0.0';

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.webmanifest': 'application/manifest+json; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.ico': 'image/x-icon',
  '.txt': 'text/plain; charset=utf-8',
  '.map': 'application/json; charset=utf-8',
};

function safePath(urlPath) {
  const decoded = decodeURIComponent(urlPath.split('?')[0]);
  const candidate = resolve(root, `.${decoded === '/' ? '/index.html' : decoded}`);
  if (candidate !== root && !candidate.startsWith(rootPrefix)) return null;
  return candidate;
}

const server = createServer(async (request, response) => {
  try {
    if (request.method !== 'GET' && request.method !== 'HEAD') {
      response.writeHead(405, { Allow: 'GET, HEAD' });
      response.end('Method not allowed');
      return;
    }
    const target = safePath(request.url || '/');
    if (!target) {
      response.writeHead(403);
      response.end('Forbidden');
      return;
    }
    let file = target;
    try {
      const info = await stat(file);
      if (info.isDirectory()) file = resolve(file, 'index.html');
    } catch {
      response.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
      response.end('Not found');
      return;
    }
    const info = await stat(file);
    response.writeHead(200, {
      'Content-Type': MIME[extname(file)] || 'application/octet-stream',
      'Content-Length': info.size,
      'Cache-Control': 'no-cache',
      'X-Content-Type-Options': 'nosniff',
    });
    if (request.method === 'HEAD') {
      response.end();
      return;
    }
    createReadStream(file).pipe(response);
  } catch (error) {
    response.writeHead(500, { 'Content-Type': 'text/plain; charset=utf-8' });
    response.end(`Server error: ${error.message}`);
  }
});

function lanAddresses() {
  const addresses = [];
  for (const entries of Object.values(networkInterfaces())) {
    for (const entry of entries ?? []) {
      if (entry.family === 'IPv4' && !entry.internal) addresses.push(entry.address);
    }
  }
  return addresses;
}

server.listen(port, host, () => {
  console.log(`InvestorKit web app: http://localhost:${port}/`);
  for (const address of lanAddresses()) {
    console.log(`On your network:    http://${address}:${port}/`);
  }
  console.log('Press Ctrl+C to stop.');
});
