// Operator-only real NAS integration check. Password comes from private process
// environment; never pass it on the command line or commit an environment file.
import assert from 'node:assert/strict';
import { request } from 'node:http';
import { randomBytes } from 'node:crypto';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { loadConfig } from '../../server/identity_web/src/config.js';
import { createIdentityService } from '../../server/identity_web/src/server.js';

let account = process.env.SYNOLOGY_TEST_ACCOUNT;
let password = process.env.SYNOLOGY_TEST_PASSWORD;
delete process.env.SYNOLOGY_TEST_ACCOUNT;
delete process.env.SYNOLOGY_TEST_PASSWORD;
if (!account || !password || !process.env.SYNOLOGY_ORIGIN) {
  console.error('Private SYNOLOGY_ORIGIN and test credentials are required.');
  process.exit(1);
}
const directory = mkdtempSync(join(tmpdir(), 'bga-auth-probe-'));
let service, token, call;
try {
  const config = loadConfig({
    PUBLIC_WEB_ORIGIN: 'https://integration.example.invalid',
    SYNOLOGY_ORIGIN: process.env.SYNOLOGY_ORIGIN,
    NAS_INSTANCE_ID: 'integration_probe_only_2026',
    SESSION_ENCRYPTION_KEY: randomBytes(32).toString('base64'),
    SESSION_DB_PATH: join(directory, 'probe.sqlite'),
    REQUEST_TIMEOUT_MS: '15000',
  });
  service = createIdentityService(config);
  await new Promise(resolve => service.server.listen(0, '127.0.0.1', resolve));
  // The local test harness is loopback HTTP; NAS traffic still requires valid
  // HTTPS certificates. This does not validate a public reverse proxy or app UI.
  call = async (path, data) => {
    return new Promise((resolve, reject) => {
      const req = request({ hostname: '127.0.0.1', port: service.server.address().port,
        path: `/api/identity/${path}`, method: data ? 'POST' : 'GET',
        headers: { Host: 'integration.example.invalid', 'X-Identity-Client': 'native-v1',
          ...(token ? { Authorization: `Bearer ${token}` } : {}),
          ...(data ? { 'Content-Type': 'application/json' } : {}) },
      }, response => {
        const parts = []; let size = 0;
        response.on('data', part => { size += part.length; if (size > 65536) req.destroy(new Error('Response limit')); else parts.push(part); });
        response.on('end', () => {
          try { const result = JSON.parse(Buffer.concat(parts).toString('utf8'));
            if (response.statusCode !== 200) reject(new Error('Probe step rejected')); else resolve(result);
          } catch { reject(new Error('Probe response invalid')); }
        });
        response.on('error', reject);
      });
      req.setTimeout(40000, () => req.destroy(new Error('Probe timeout')));
      req.on('error', reject);
      req.end(data ? JSON.stringify(data) : undefined);
    });
  };
  const login = await call('sign-in', { account, password });
  password = ''; account = '';
  token = login.sessionToken;
  assert.match(token, /^[A-Za-z0-9_-]{43}$/);
  console.log('PASS: application login through real SYNO.API.Auth');
  const current = await call('session');
  assert.equal(current.user.id, login.user.id);
  console.log('PASS: independent NAS UID verification and session restore');
  await call('sign-out', {});
  assert.equal((await call('session')).user, null);
  assert.equal(service.store.db.prepare('SELECT count(*) AS n FROM revocations').get().n, 0);
  console.log('PASS: NAS logout completed; old application token rejected');
  token = null;
} catch {
  console.error('FAIL: real NAS integration incomplete; credentials and diagnostics suppressed');
  process.exitCode = 1;
} finally {
  password = ''; account = '';
  if (token && call) {
    try { await call('sign-out', {}); }
    catch { console.error('WARN: probe logout could not be confirmed'); }
  }
  await service?.close();
  rmSync(directory, { recursive: true, force: true });
}
