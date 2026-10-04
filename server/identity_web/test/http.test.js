import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { randomBytes } from 'node:crypto';
import { request as httpRequest } from 'node:http';
import { createIdentityService, COOKIE_NAME } from '../src/server.js';
import { loadConfig } from '../src/config.js';

function fixture(t, overrides = {}) {
  const directory = mkdtempSync(join(tmpdir(), 'synology-auth-'));
  let clock = Date.now(), serial = 0;
  const records = new Map(), calls = [], logs = [];
  const config = { publicWebOrigin: 'https://app.example.test', nasOrigin: 'https://nas.example.test:5001',
    nasId: 'nas_fixture_identity_2026', encryptionKey: randomBytes(32), databasePath: join(directory, 'session.sqlite'),
    idleMs: 300000, absoluteMs: 3600000, anonymousMs: 600000, timeoutMs: 1000, maxSessions: 1000, maxBodyBytes: 8192, ...overrides };
  const fetchImpl = async (input, options) => {
    const url = new URL(input), fields = options.method === 'POST' ? new URLSearchParams(options.body) : url.searchParams;
    assert.equal(url.origin, config.nasOrigin); assert.equal(options.redirect, 'error');
    calls.push({ api: fields.get('api'), method: fields.get('method'), verb: options.method });
    const ok = data => Response.json({ success: true, data });
    const bad = code => Response.json({ success: false, error: { code, diagnostic: 'private upstream diagnostics' } });
    if (fields.get('api') === 'SYNO.API.Info') return ok({
      'SYNO.API.Auth': { path: 'entry.cgi', minVersion: 1, maxVersion: 7 },
      'SYNO.FileStation.Info': { path: 'entry.cgi', minVersion: 1, maxVersion: 2 },
    });
    if (fields.get('method') === 'login') {
      assert.equal(options.method, 'POST'); assert.equal(url.search, '');
      assert.equal(fields.get('enable_device_token'), null);
      if (fields.get('passwd') !== 'fixture-password') return bad(400);
      if (fields.get('account') === 'disabled') return bad(401);
      if (fields.get('account') === 'expired') return bad(409);
      if (fields.get('account') === 'otp' && !fields.get('otp_code')) return bad(403);
      if (fields.get('account') === 'otp' && fields.get('otp_code') !== '123456') return bad(404);
      const sid = `private-nas-session-${++serial}`;
      records.set(sid, { uid: fields.get('account') === 'other' ? 1002 : 1001 });
      return ok({ sid, synotoken: 'private-syno-token' });
    }
    const session = records.get(fields.get('_sid'));
    if (fields.get('method') === 'logout') {
      if (overrides.logoutFailure) throw new Error('private logout failure');
      records.delete(fields.get('_sid')); return ok({});
    }
    if (fields.get('api') === 'SYNO.FileStation.Info') {
      if (!session) return bad(119);
      if (overrides.profileFailure) throw new Error('private NAS failure');
      if (overrides.profileDelay) await new Promise((resolve, reject) => {
        const timer = setTimeout(resolve, overrides.profileDelay);
        options.signal.addEventListener('abort', () => { clearTimeout(timer); reject(new Error('aborted')); }, { once: true });
      });
      return ok({ uid: session.uid, privateInternalFields: true });
    }
    return bad(102);
  };
  const service = createIdentityService(config, { fetchImpl, now: () => clock, log: value => logs.push(value) });
  t.after(async () => { await service.close(); rmSync(directory, { recursive: true, force: true }); });
  const ready = new Promise(resolve => service.server.listen(0, '127.0.0.1', resolve));
  let cookie = '';
  const call = async (path, { native = false, token, method = 'GET', data, origin, csrf, headers = {} } = {}) => {
    await ready;
    const response = await new Promise((resolve, reject) => {
      const request = httpRequest(`http://127.0.0.1:${service.server.address().port}${path}`, {
      method, headers: { Host: 'app.example.test', ...(native ? { 'X-Identity-Client': 'native-v1' } : cookie ? { Cookie: cookie } : {}),
        ...(token ? { Authorization: `Bearer ${token}` } : {}), ...(origin ? { Origin: origin } : {}),
        ...(csrf ? { 'X-CSRF-Token': csrf } : {}), ...(data ? { 'Content-Type': 'application/json' } : {}), ...headers },
      }, incoming => {
        const chunks = [];
        incoming.on('data', chunk => chunks.push(chunk));
        incoming.on('end', () => resolve({ status: incoming.statusCode,
          headers: new Headers(Object.entries(incoming.headers).map(([key, value]) => [key, Array.isArray(value) ? value.join(',') : value])),
          json: async () => JSON.parse(Buffer.concat(chunks).toString('utf8')) }));
      });
      request.on('error', reject); request.end(data ? JSON.stringify(data) : undefined);
    });
    if (!native && response.headers.get('set-cookie')) cookie = response.headers.get('set-cookie').split(';')[0];
    return { status: response.status, body: await response.json(), headers: response.headers };
  };
  const login = async (account = 'fixture', extra = {}) => call('/api/identity/sign-in', { native: true, method: 'POST', data: { account, password: 'fixture-password', ...extra } });
  return { service, config, call, login, records, calls, logs, advance: ms => { clock += ms; } };
}
test('native login, independent session verification, logout and old-token rejection', async t => {
  const f = fixture(t); const login = await f.login();
  assert.equal(login.status, 200); assert.match(login.body.sessionToken, /^[\w-]{43}$/);
  assert.equal(login.body.user.displayName, 'fixture'); assert.match(login.body.user.id, /^[a-f0-9]{64}$/);
  assert.equal(JSON.stringify(login.body).includes('private-nas'), false);
  const token = login.body.sessionToken;
  assert.equal((await f.call('/api/identity/session', { native: true, token })).body.user.id, login.body.user.id);
  assert.equal((await f.call('/api/identity/sign-out', { native: true, token, method: 'POST', data: {} })).status, 200);
  assert.equal((await f.call('/api/identity/session', { native: true, token })).body.user, null);
  assert.equal(f.records.size, 0);
});
test('browser cookie is Secure HttpOnly, same-origin CSRF required, no native token returned', async t => {
  const f = fixture(t);
  const boot = await f.call('/api/identity/csrf');
  assert.match(boot.headers.get('set-cookie'), /HttpOnly; Secure; SameSite=Lax/);
  assert.ok(boot.headers.get('set-cookie').startsWith(`${COOKIE_NAME}=`));
  const data = { account: 'fixture', password: 'fixture-password' };
  assert.equal((await f.call('/api/identity/sign-in', { method: 'POST', data })).status, 403);
  assert.equal((await f.call('/api/identity/sign-in', { method: 'POST', data, origin: 'https://sibling.example.test', csrf: boot.body.csrfToken })).status, 403);
  const login = await f.call('/api/identity/sign-in', { method: 'POST', data, origin: f.config.publicWebOrigin, csrf: boot.body.csrfToken });
  assert.equal(login.status, 200); assert.equal(login.body.sessionToken, undefined);
  assert.equal((await f.call('/api/identity/session')).body.user.id, login.body.user.id);
  assert.equal((await f.call('/api/identity/sign-out', { method: 'POST', data: {}, origin: f.config.publicWebOrigin, csrf: boot.body.csrfToken })).status, 403);
  const newCsrf = await f.call('/api/identity/csrf');
  assert.equal((await f.call('/api/identity/sign-out', { method: 'POST', data: {}, origin: f.config.publicWebOrigin, csrf: newCsrf.body.csrfToken })).status, 200);
});
test('OTP challenge, invalid code and success never bypass two-factor authentication', async t => {
  const f = fixture(t);
  assert.equal((await f.login('otp')).body.error, 'otp_required');
  assert.equal((await f.login('otp', { otp: '000000' })).body.error, 'invalid_otp');
  assert.equal((await f.login('otp', { otp: '123456' })).status, 200);
});
test('credential errors, disabled accounts and password expiry are sanitized', async t => {
  const f = fixture(t);
  assert.equal((await f.login('fixture', { password: 'wrong' })).body.error, 'invalid_credentials');
  assert.equal((await f.login('disabled')).body.error, 'account_denied');
  assert.equal((await f.login('expired')).body.error, 'password_change_required');
  assert.equal(JSON.stringify(f.logs).includes('password'), true); // Fixed error code only.
  assert.equal(JSON.stringify(f.logs).includes('fixture-password'), false);
  assert.equal(JSON.stringify(f.logs).includes('private upstream'), false);
});
test('persistent account rate limit stops repeated password attempts before reaching NAS', async t => {
  const f = fixture(t);
  for (let i = 0; i < 5; i++) assert.equal((await f.login('fixture', { password: 'wrong' })).status, 401);
  const count = f.calls.length;
  assert.equal((await f.login('fixture')).status, 429); assert.equal(f.calls.length, count);
});
test('client cannot spoof native mode from a browser or replay native tokens as cookies', async t => {
  const f = fixture(t); const login = await f.login();
  assert.equal((await f.call('/api/identity/session', { native: true, token: login.body.sessionToken, origin: f.config.publicWebOrigin })).status, 403);
  assert.equal((await f.call('/api/identity/session', { native: true, token: login.body.sessionToken, headers: { 'Sec-Fetch-Site': 'same-origin' } })).status, 403);
  assert.equal((await f.call('/api/identity/session', { headers: { Cookie: `${COOKIE_NAME}=${login.body.sessionToken}` } })).status, 401);
});
test('NAS revocation and changed UID invalidate the application identity', async t => {
  const f = fixture(t); const login = await f.login();
  for (const value of f.records.values()) value.uid = 9999;
  assert.equal((await f.call('/api/identity/session', { native: true, token: login.body.sessionToken })).body.user, null);
  const next = await f.login(); f.records.clear();
  assert.equal((await f.call('/api/identity/session', { native: true, token: next.body.sessionToken })).body.user, null);
});
test('idle and absolute expiration reject sessions and enqueue NAS revocation', async t => {
  const f = fixture(t); const login = await f.login();
  f.advance(300001);
  assert.equal((await f.call('/api/identity/session', { native: true, token: login.body.sessionToken })).body.user, null);
  await f.service.retryRevocations(); assert.equal(f.records.size, 0);
  const next = await f.login();
  for (let i = 0; i < 18; i++) { f.advance(200000); await f.call('/api/identity/session', { native: true, token: next.body.sessionToken }); }
  assert.equal((await f.call('/api/identity/session', { native: true, token: next.body.sessionToken })).body.user, null);
});
test('NAS session and SynoToken are encrypted at rest, passwords are never stored', async t => {
  const f = fixture(t); await f.login();
  const files = [f.config.databasePath, `${f.config.databasePath}-wal`];
  for (const file of files) {
    const bytes = readFileSync(file);
    for (const forbidden of ['private-nas-session', 'private-syno-token', 'fixture-password']) assert.equal(bytes.includes(Buffer.from(forbidden)), false);
  }
});
test('profile failure cannot mint a successful application session and NAS session is revoked', async t => {
  const f = fixture(t, { profileFailure: true });
  assert.equal((await f.login()).status, 502); assert.equal(f.records.size, 0);
});
test('public configuration does not expose NAS origin, tokens, encryption key or Supabase parameters', async t => {
  const f = fixture(t); const result = await f.call('/api/identity/configuration');
  assert.deepEqual(result.body, { version: 2, authType: 'synology-api-auth', nasId: f.config.nasId, serviceUrl: f.config.publicWebOrigin });
});
test('configuration requires HTTPS origins, fixed NAS realm and private encrypted database', () => {
  const env = { PUBLIC_WEB_ORIGIN: 'https://app.example.test', SYNOLOGY_ORIGIN: 'https://nas.example.test:5001',
    NAS_INSTANCE_ID: 'nas_fixture_identity_2026', SESSION_ENCRYPTION_KEY: randomBytes(32).toString('base64'), SESSION_DB_PATH: '/private/session.sqlite' };
  assert.equal(loadConfig(env).nasOrigin, env.SYNOLOGY_ORIGIN);
  for (const patch of [{ SYNOLOGY_ORIGIN: 'http://nas.example.test' }, { PUBLIC_WEB_ORIGIN: 'https://user:password@app.example.test' },
    { NAS_INSTANCE_ID: 'short' }, { SESSION_DB_PATH: 'relative.sqlite' }, { SESSION_ENCRYPTION_KEY: 'not-a-key' }]) assert.throws(() => loadConfig({ ...env, ...patch }));
});
test('failed NAS logout invalidates app token immediately and retries encrypted revocation', async t => {
  const options = { logoutFailure: true };
  const f = fixture(t, options);
  const login = await f.login();
  assert.equal((await f.call('/api/identity/sign-out', { native: true, token: login.body.sessionToken, method: 'POST', data: {} })).body.error, 'revocation_pending');
  assert.equal((await f.call('/api/identity/session', { native: true, token: login.body.sessionToken })).body.user, null);
  assert.equal(f.records.size, 1);
  options.logoutFailure = false;
  f.advance(6000);
  await f.service.retryRevocations();
  assert.equal(f.records.size, 0);
});
test('upstream deadline fails closed and compensates an issued NAS session', async t => {
  const f = fixture(t, { profileDelay: 1000, timeoutMs: 30 });
  assert.equal((await f.login()).body.error, 'upstream_timeout');
  assert.equal(f.records.size, 0);
  assert.equal(f.service.store.db.prepare('SELECT count(*) AS n FROM sessions').get().n, 0);
});
test('login rate-limit buckets expire and are capacity bounded', async t => {
  const f = fixture(t, { maxSessions: 2 });
  assert.equal((await f.login('one', { password: 'wrong' })).status, 401);
  assert.equal((await f.login('two', { password: 'wrong' })).status, 401);
  assert.equal((await f.login('three', { password: 'wrong' })).status, 429);
  f.advance(900001);
  assert.equal((await f.login('three', { password: 'wrong' })).status, 401);
  assert.equal(f.service.store.db.prepare('SELECT count(*) AS n FROM login_limits').get().n, 1);
});
test('session capacity refuses a new NAS login before issuing credentials upstream', async t => {
  const f = fixture(t, { maxSessions: 1 });
  assert.equal((await f.login()).status, 200);
  const count = f.calls.length;
  assert.equal((await f.login('other')).status, 503);
  assert.equal(f.calls.length, count);
});
test('an unfinished credential body is terminated at the request deadline', async t => {
  const f = fixture(t, { timeoutMs: 40 });
  await f.call('/api/identity/configuration');
  await new Promise((resolve, reject) => {
    const req = httpRequest({ hostname: '127.0.0.1', port: f.service.server.address().port,
      path: '/api/identity/sign-in', method: 'POST',
      headers: { Host: 'app.example.test', 'X-Identity-Client': 'native-v1', 'Content-Type': 'application/json' },
    });
    const timer = setTimeout(() => { req.destroy(); reject(new Error('Unbounded request body')); }, 1000);
    req.on('error', () => { clearTimeout(timer); resolve(); });
    req.write('{'); // Deliberately do not finish the request.
  });
  assert.equal(f.calls.length, 0);
});
