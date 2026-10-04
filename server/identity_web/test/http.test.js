import test from 'node:test';
import assert from 'node:assert/strict';
import { request } from 'node:http';
import { createHash, randomBytes } from 'node:crypto';
import { mkdtempSync, rmSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadConfig } from '../src/config.js';
import { createIdentityService, COOKIE_NAME } from '../src/server.js';

const origin = 'https://board.example.test';
const supabaseUrl = 'https://registered.supabase.co';
const publishableKey = 'sb_publishable_test-only-public-key';
const hash = text => createHash('sha256').update(text).digest('hex');
const legacyKey = claims => [
  Buffer.from(JSON.stringify({ alg: 'HS256', typ: 'JWT' })).toString('base64url'),
  Buffer.from(JSON.stringify(claims)).toString('base64url'),
  Buffer.from('test-signature-not-live-verified').toString('base64url'),
].join('.');
function environment() {
  return {
    PUBLIC_WEB_ORIGIN: origin, SUPABASE_URL: supabaseUrl, REGISTERED_SUPABASE_URL: supabaseUrl,
    SUPABASE_PUBLISHABLE_KEY: publishableKey, REGISTERED_SUPABASE_KEY_SHA256: hash(publishableKey),
    REGISTERED_CALLBACK_URL: `${origin}/auth/callback`, SESSION_ENCRYPTION_KEY: randomBytes(32).toString('base64'),
  };
}

// Real Supabase SDK calls a fake HTTP gateway. This is deliberately NOT a live OIDC test.
class FakeGateway {
  constructor() {
    this.codes = new Map(); this.access = new Map(); this.refresh = new Map();
    this.calls = []; this.refreshCount = 0; this.logoutFailure = false; this.userFailure = null;
    this.expirySeconds = 3600; this.proxyData = { favorites: ['azul'] };
    this.metadataById = new Map();
  }
  issueCode(authorizationUrl, id = 'user-a') {
    const url = new URL(authorizationUrl);
    const code = `code-${randomBytes(8).toString('hex')}`;
    this.codes.set(code, { challenge: url.searchParams.get('code_challenge'), id });
    return code;
  }
  token(id) {
    const payload = { sub: id, exp: Math.floor(Date.now() / 1000) + this.expirySeconds,
      session_id: '12345678-1234-4234-8234-123456789abc' };
    const access_token = `${Buffer.from('{"alg":"HS256"}').toString('base64url')}.${Buffer.from(JSON.stringify(payload)).toString('base64url')}.${randomBytes(24).toString('base64url')}`;
    const refresh_token = `refresh-secret-${randomBytes(24).toString('hex')}`;
    this.access.set(access_token, id); this.refresh.set(refresh_token, id);
    return { access_token, refresh_token, token_type: 'bearer', expires_in: this.expirySeconds,
      expires_at: payload.exp, user: this.user(id), provider_token: 'nas-secret-token', provider_refresh_token: 'nas-secret-refresh' };
  }
  user(id) { return { id, email: `${id}@example.test`, user_metadata: this.metadataById.get(id) ?? { name: `Name ${id}`, private: 'do-not-return' } }; }
  fetch = async (input, init) => {
    const url = new URL(String(input));
    const headers = new Headers(init.headers);
    const body = init.body ? JSON.parse(init.body) : null;
    this.calls.push({ url: url.href, method: init.method, body, headers });
    if (this.hang && url.pathname === '/auth/v1/user') {
      return new Promise((_resolve, reject) => init.signal.addEventListener('abort', () => reject(new Error('fake abort')), { once: true }));
    }
    if (url.pathname === '/auth/v1/token' && url.searchParams.get('grant_type') === 'pkce') {
      const code = this.codes.get(body.auth_code);
      const challenge = createHash('sha256').update(body.code_verifier).digest('base64url');
      if (!code || challenge !== code.challenge) return Response.json({ code: 'bad_code', msg: 'secret upstream detail' }, { status: 400 });
      this.codes.delete(body.auth_code);
      return Response.json(this.token(code.id));
    }
    if (url.pathname === '/auth/v1/token' && url.searchParams.get('grant_type') === 'refresh_token') {
      this.refreshCount++;
      const id = this.refresh.get(body.refresh_token);
      if (!id) return Response.json({ code: 'refresh_token_not_found' }, { status: 400 });
      this.refresh.delete(body.refresh_token);
      this.expirySeconds = 3600;
      return Response.json(this.token(id));
    }
    if (url.pathname === '/auth/v1/user') {
      if (this.userFailure) return Response.json({ code: 'bad_jwt', msg: 'raw auth secret' }, { status: this.userFailure });
      const id = this.access.get(headers.get('authorization')?.replace('Bearer ', ''));
      if (!id) return Response.json({ code: 'bad_jwt' }, { status: 401 });
      return Response.json(this.user(this.overrideUser || id));
    }
    if (url.pathname === '/auth/v1/logout') {
      if (this.logoutFailure) return Response.json({ msg: 'remote secret failure' }, { status: 503 });
      return new Response(null, { status: 204 });
    }
    if (url.href === 'https://data.example.test/userdata') return Response.json(this.proxyData);
    throw new Error('Unexpected fake gateway request');
  };
}

async function fixture(t, overrides = {}, envOverrides = {}) {
  const root = fileURLToPath(new URL('.', import.meta.url));
  const directory = mkdtempSync(join(root, '.tmp-'));
  const config = { ...loadConfig({ ...environment(), ...envOverrides }), databasePath: join(directory, 'sessions.sqlite'), ...overrides };
  let clock = Date.now();
  const gateway = new FakeGateway();
  const logs = [];
  let service;
  let port;
  async function start() {
    service = createIdentityService(config, { fetchImpl: gateway.fetch, now: () => clock, log: record => logs.push(record) });
    await new Promise(resolve => service.server.listen(0, '127.0.0.1', resolve));
    port = service.server.address().port;
  }
  await start();
  t.after(async () => { await service.close(); rmSync(directory, { recursive: true, force: true }); });
  function browser() {
    return {
      cookie: '', cookieExpiresAt: null, csrf: null,
      async call(path, { method = 'GET', body, originHeader = method === 'GET' ? undefined : origin,
        csrf = this.csrf, cookie = this.cookieExpiresAt !== null && clock >= this.cookieExpiresAt ? '' : this.cookie, headers = {} } = {}) {
        const data = body === undefined ? undefined : JSON.stringify(body);
        const response = await new Promise((resolve, reject) => {
          const req = request({ hostname: '127.0.0.1', port, path, method, headers: {
            Host: new URL(origin).host, ...(cookie ? { Cookie: cookie } : {}),
            ...(originHeader ? { Origin: originHeader } : {}), ...(csrf ? { 'X-CSRF-Token': csrf } : {}),
            ...(data === undefined ? {} : { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(data) }), ...headers,
          } }, res => {
            const chunks = [];
            res.on('data', chunk => chunks.push(chunk));
            res.on('end', () => {
              const text = Buffer.concat(chunks).toString();
              resolve({ status: res.statusCode, headers: res.headers, text, data: text ? JSON.parse(text) : null });
            });
          });
          req.on('error', reject); req.end(data);
        });
        const set = response.headers['set-cookie']?.[0];
        if (set) {
          this.cookie = set.split(';')[0];
          const age = /(?:^|;)\s*Max-Age=(\d+)(?:;|$)/.exec(set);
          this.cookieExpiresAt = age ? clock + Number(age[1]) * 1000 : null;
        }
        return response;
      },
      async getCsrf() { const response = await this.call('/api/identity/csrf'); this.csrf = response.data.csrfToken; return response; },
      async begin() { await this.getCsrf(); return this.call('/api/identity/sign-in', { method: 'POST' }); },
      async login(id = 'user-a') {
        const begin = await this.begin(); assert.equal(begin.status, 200);
        const code = gateway.issueCode(begin.data.authorizationUrl, id);
        const callback = await this.call(`/auth/callback?code=${code}`);
        assert.equal(callback.status, 303, callback.text); await this.getCsrf(); return callback;
      },
    };
  }
  return { browser, gateway, config, logs, get store() { return service.store; }, now: () => clock, advance: ms => { clock += ms; },
    restart: async () => { await service.close(); await start(); }, retryRevocations: () => service.retryRevocations(), directory };
}

test('registration is exact and HTTPS-only; no alternate origins, URLs, keys or callbacks', () => {
  const env = environment(); assert.equal(loadConfig(env).supabaseUrl, supabaseUrl);
  for (const patch of [
    { SUPABASE_URL: 'https://evil.test' }, { SUPABASE_PUBLISHABLE_KEY: 'sb_publishable_other' },
    { PUBLIC_WEB_ORIGIN: `${origin}/` }, { PUBLIC_WEB_ORIGIN: 'http://board.example.test' },
    { REGISTERED_CALLBACK_URL: `${origin}/other` }, { SUPABASE_PUBLISHABLE_KEY: 'sb_secret_disallowed' },
    { SESSION_ENCRYPTION_KEY: 'short' }, { USERDATA_UPSTREAM_URL: 'https://evil.test/userdata' },
  ]) assert.throws(() => loadConfig({ ...env, ...patch }));
});

test('public API key classification accepts pinned publishable and legacy anon keys', () => {
  for (const key of [publishableKey, legacyKey({ role: 'anon', iss: 'supabase', ref: 'self-hosted' })]) {
    const config = loadConfig({ ...environment(), SUPABASE_PUBLISHABLE_KEY: key, REGISTERED_SUPABASE_KEY_SHA256: hash(key) });
    assert.equal(config.supabaseKey, key);
  }
});

test('privileged, malformed and non-anon API keys are rejected even with matching pins', () => {
  const anon = legacyKey({ role: 'anon' });
  const [header, payload, signature] = anon.split('.');
  const keys = [
    'sb_secret_test-only-secret-key', 'service_role', 'sb_publishable_', 'sb_publishable_short',
    `${publishableKey}\n`, legacyKey({ role: 'service_role' }), legacyKey({ role: 'authenticated' }),
    legacyKey({ role: 'ANON' }), legacyKey({ role: ['anon'] }), legacyKey({ role: null }),
    legacyKey({}), legacyKey(null), legacyKey(['anon']), legacyKey('anon'),
    `${header}.${Buffer.from('{not-json').toString('base64url')}.${signature}`,
    `${header}.${payload}!${signature}`, `${header}.${payload}`, `${header}.${payload}.`,
    `${header}.${payload}.${signature}.extra`, `.${payload}.${signature}`,
    `${header}.${payload}=.${signature}`, ` ${anon}`, `${anon} `, 'x'.repeat(16385),
  ];
  for (const key of keys) {
    assert.throws(() => loadConfig({ ...environment(), SUPABASE_PUBLISHABLE_KEY: key,
      REGISTERED_SUPABASE_KEY_SHA256: hash(key) }), /Only a Supabase publishable or legacy anon key/);
  }
});

test('legacy anon role cannot bypass exact registration fingerprint or project pin', () => {
  const key = legacyKey({ role: 'anon', ref: 'registered' });
  const env = { ...environment(), SUPABASE_PUBLISHABLE_KEY: key, REGISTERED_SUPABASE_KEY_SHA256: hash(key) };
  assert.throws(() => loadConfig({ ...env, REGISTERED_SUPABASE_KEY_SHA256: hash(publishableKey) }), /key registration mismatch/);
  assert.throws(() => loadConfig({ ...env, SUPABASE_PUBLISHABLE_KEY: legacyKey({ role: 'anon', ref: 'other' }) }), /key registration mismatch/);
  assert.throws(() => loadConfig({ ...env, SUPABASE_URL: 'https://other.supabase.co' }), /registration mismatch/);
});

test('legacy anon configuration completes SDK PKCE, identity verification and logout over HTTP', async t => {
  const key = legacyKey({ role: 'anon', iss: 'supabase', ref: 'self-hosted' });
  const f = await fixture(t, {}, { SUPABASE_PUBLISHABLE_KEY: key, REGISTERED_SUPABASE_KEY_SHA256: hash(key) });
  const b = f.browser();
  const configuration = await b.call('/api/identity/configuration');
  assert.deepEqual(configuration.data, { supabaseUrl, publishableKey: key, providerId: 'custom:synology', webCallback: `${origin}/auth/callback` });
  await b.login();
  assert.deepEqual((await b.call('/api/identity/session')).data, { user: {
    id: 'user-a', email: 'user-a@example.test', displayName: 'Name user-a',
  } });
  const calls = f.gateway.calls.filter(call => new URL(call.url).pathname.startsWith('/auth/v1/'));
  assert.ok(calls.length >= 3);
  assert.ok(calls.every(call => call.headers.get('apikey') === key));
  assert.deepEqual((await b.call('/api/identity/sign-out', { method: 'POST' })).data, { user: null });
  assert.ok(!JSON.stringify(f.logs).includes(key));
});

test('verified Synology names fall back in order, skip invalid values and retain public sanitization', async t => {
  const f = await fixture(t); const b = f.browser(); await b.login();
  const cases = [
    [{ full_name: 'Full', name: 'Name', display_name: 'Display', preferred_username: 'Preferred' }, 'Full'],
    [{ full_name: '', name: 'Name', display_name: 'Display', preferred_username: 'Preferred' }, 'Name'],
    [{ full_name: {}, name: 42, display_name: 'Display', preferred_username: 'Preferred' }, 'Display'],
    [{ preferred_username: 'Preferred', username: 'Username', nickname: 'Nick' }, 'Preferred'],
    [{ full_name: ' \t\n', preferred_username: ' ', username: 'Username', nickname: 'Nick' }, 'Username'],
    [{ preferred_username: {}, username: ['bad'], nickname: 'Nick' }, 'Nick'],
    [{ nickname: '\x00  群晖用户\n \x7f', private: 'private-name-field' }, '群晖用户'],
    [{ preferred_username: 'n'.repeat(220) }, 'n'.repeat(200)],
    [{ full_name: '\x00', name: false, nickname: '  ' }, null],
    [{}, null],
  ];
  // Changes after login prove names come from getUser, rather than cached SDK metadata.
  for (const [metadata, expected] of cases) {
    f.gateway.metadataById.set('user-a', metadata);
    const result = await b.call('/api/identity/session');
    assert.equal(result.status, 200);
    assert.deepEqual(result.data, { user: { id: 'user-a', email: 'user-a@example.test', displayName: expected } });
  }
});

test('Synology fallback names remain isolated between authenticated browsers', async t => {
  const f = await fixture(t); const a = f.browser(); const b = f.browser();
  f.gateway.metadataById.set('user-a', { preferred_username: 'Synology A' });
  f.gateway.metadataById.set('user-b', { nickname: 'Synology B' });
  await a.login('user-a'); await b.login('user-b');
  const [resultA, resultB] = await Promise.all([a.call('/api/identity/session'), b.call('/api/identity/session')]);
  assert.equal(resultA.data.user.displayName, 'Synology A'); assert.equal(resultA.data.user.id, 'user-a');
  assert.equal(resultB.data.user.displayName, 'Synology B'); assert.equal(resultB.data.user.id, 'user-b');
});

test('anonymous identity and authoritative public configuration have exact response contracts', async t => {
  const f = await fixture(t); const b = f.browser();
  assert.deepEqual((await b.call('/api/identity/session')).data, { user: null });
  const result = await b.call('/api/identity/configuration');
  assert.deepEqual(result.data, { supabaseUrl, publishableKey, providerId: 'custom:synology', webCallback: `${origin}/auth/callback` });
  assert.equal(result.headers['cache-control'], 'no-store');
  assert.equal(result.headers['set-cookie'], undefined);
  assert.equal((await b.call('/api/identity/configuration?supabaseUrl=https://evil.test')).status, 400);
  assert.equal((await b.call('/api/identity/session', { headers: { Host: 'evil.test' } })).status, 421);
});

test('secure cookie, exact Origin and CSRF are required; per-browser CSRF is isolated', async t => {
  const f = await fixture(t); const a = f.browser(); const b = f.browser();
  const csrf = await a.getCsrf(); await b.getCsrf();
  assert.deepEqual(Object.keys(csrf.data), ['csrfToken']);
  assert.match(csrf.data.csrfToken, /^[A-Za-z0-9_-]{43}$/);
  assert.match(csrf.headers['set-cookie'][0], /Path=\/; HttpOnly; Secure; SameSite=Lax;/);
  assert.ok(!csrf.headers['set-cookie'][0].includes('Domain='));
  for (const opts of [{ csrf: null }, { csrf: b.csrf }, { originHeader: null }, { originHeader: 'https://evil.test' },
    { headers: { 'Sec-Fetch-Site': 'same-site' } }]) {
    assert.equal((await a.call('/api/identity/sign-in', { method: 'POST', ...opts })).status, 403);
  }
  assert.equal((await a.call('/api/identity/csrf', { headers: { 'Sec-Fetch-Site': 'cross-site' } })).status, 403);
  assert.equal((await a.call('/api/identity/sign-in', { method: 'POST', body: { provider: 'custom:other' } })).status, 400);
  assert.equal((await a.call('/api/identity/sign-in', { method: 'POST', body: {} })).status, 200);
});

test('SDK PKCE persists encrypted through restart, exchanges once and rotates login cookie', async t => {
  const f = await fixture(t); const b = f.browser();
  await b.getCsrf(); const anonymous = b.cookie;
  const begin = await b.call('/api/identity/sign-in', { method: 'POST' });
  const pending = b.cookie; assert.notEqual(pending, anonymous);
  const url = new URL(begin.data.authorizationUrl);
  assert.equal(url.origin, supabaseUrl); assert.equal(url.searchParams.get('provider'), 'custom:synology');
  assert.equal(url.searchParams.get('redirect_to'), `${origin}/auth/callback`);
  assert.equal(url.searchParams.get('code_challenge_method'), 's256');
  const row = f.store.get(pending.split('=')[1]);
  const verifiers = Object.entries(row.data.sdk).filter(([key]) => key.endsWith('-code-verifier'));
  assert.ok(verifiers.length > 0);
  const payload = f.store.db.prepare('SELECT payload FROM sessions WHERE id=?').get(row.id).payload;
  assert.ok(!Buffer.from(payload).includes(Buffer.from(verifiers[0][1])));
  assert.equal((await b.call('/api/identity/session', { cookie: anonymous })).data.user, null);
  b.cookie = pending;
  await f.restart();
  const code = f.gateway.issueCode(begin.data.authorizationUrl);
  const callback = await b.call(`/auth/callback?code=${code}`);
  assert.equal(callback.status, 303, callback.text); assert.equal(callback.headers.location, '/');
  assert.notEqual(b.cookie, pending);
  const authenticated = b.cookie;
  const user = await b.call('/api/identity/session');
  assert.deepEqual(user.data, { user: { id: 'user-a', email: 'user-a@example.test', displayName: 'Name user-a' } });
  assert.ok(!Object.keys(f.store.get(authenticated.split('=')[1]).data.sdk).some(key => key.endsWith('-code-verifier')));
  assert.equal((await b.call(`/auth/callback?code=${code}`, { cookie: pending })).status, 400);
  b.cookie = authenticated;
  await f.restart();
  assert.equal((await b.call('/api/identity/session')).data.user.id, 'user-a');
  const disk = readFileSync(f.config.databasePath);
  assert.ok(!disk.includes(Buffer.from('nas-secret-token')));
  assert.ok(!disk.includes(Buffer.from('refresh-secret-')));
});

test('browser sessions and PKCE codes cannot be swapped', async t => {
  const f = await fixture(t); const a = f.browser(); const b = f.browser();
  const beginA = await a.begin(); const beginB = await b.begin();
  const codeA = f.gateway.issueCode(beginA.data.authorizationUrl, 'user-a');
  const codeB = f.gateway.issueCode(beginB.data.authorizationUrl, 'user-b');
  assert.equal((await b.call(`/auth/callback?code=${codeA}`)).status, 502);
  assert.equal((await a.call(`/auth/callback?code=${codeA}`)).status, 303);
  assert.equal((await a.call('/api/identity/session')).data.user.id, 'user-a');
  assert.equal((await b.call(`/auth/callback?code=${codeB}`)).status, 400);
  await b.login('user-b');
  assert.equal((await b.call('/api/identity/session')).data.user.id, 'user-b');
  assert.equal((await a.call('/api/identity/session')).data.user.id, 'user-a');
});

test('sign-in destroys the previous authenticated session before a cancelled flow', async t => {
  const f = await fixture(t); const b = f.browser(); await b.login();
  const old = b.cookie; const oldCsrf = b.csrf;
  assert.equal((await b.call('/api/identity/sign-in', { method: 'POST' })).status, 200);
  const pending = b.cookie;
  assert.equal((await b.call('/api/identity/session')).data.user, null);
  assert.equal((await b.call('/api/identity/session', { cookie: old })).data.user, null);
  assert.equal((await b.call('/api/identity/session', { cookie: old })).headers['set-cookie'], undefined);
  assert.equal((await b.call('/api/identity/sign-out', { method: 'POST', cookie: old, csrf: oldCsrf })).status, 403);
  b.cookie = pending;
  assert.equal((await b.call('/auth/callback?error=access_denied&error_description=secret')).status, 400);
  assert.equal((await b.call('/api/identity/session')).data.user, null);
  assert.ok(!JSON.stringify(f.logs).includes('secret'));
});

test('idle and absolute expiry cannot authenticate a stale cookie', async t => {
  const f = await fixture(t, { idleMs: 1000, absoluteMs: 2500 }); const b = f.browser(); await b.login();
  f.advance(1001);
  let result = await b.call('/api/identity/session');
  assert.deepEqual(result.data, { user: null }); assert.match(result.headers['set-cookie'][0], /Max-Age=0/);
  await b.login(); f.advance(900); await b.call('/api/identity/session'); f.advance(900); await b.call('/api/identity/session'); f.advance(701);
  assert.equal((await b.call('/api/identity/session')).data.user, null);
});

test('active browser keeps its absolute-lifetime cookie beyond initial idle without renewal', async t => {
  const f = await fixture(t, { idleMs: 60000, absoluteMs: 300000 }); const b = f.browser();
  const callback = await b.login();
  assert.match(callback.headers['set-cookie'][0], /; Max-Age=300$/);
  const cookie = b.cookie;
  const sid = cookie.split('=')[1];
  const initial = f.store.get(sid);
  const absoluteDeadline = initial.created + f.config.absoluteMs;
  const initialIdleDeadline = initial.seen + f.config.idleMs;
  assert.equal(initial.expires, absoluteDeadline);
  assert.equal(b.cookieExpiresAt, absoluteDeadline);

  // Every gap is shorter than idle; multiple reads take us beyond its initial deadline.
  for (const gap of [45000, 45000, 45000, 45000, 45000, 45000, 29999]) {
    f.advance(gap);
    const result = await b.call('/api/identity/session');
    assert.equal(result.data.user?.id, 'user-a');
    assert.equal(result.headers['set-cookie'], undefined);
    assert.equal(b.cookie, cookie);
    assert.equal(b.cookieExpiresAt, absoluteDeadline);
    const current = f.store.get(sid);
    assert.equal(current.seen, f.now());
    assert.equal(current.expires, absoluteDeadline);
  }
  assert.ok(f.now() > initialIdleDeadline);
  assert.equal(f.now(), absoluteDeadline - 1);
  f.advance(1);
  // The test browser now honors the ORIGINAL Cookie Max-Age and sends no Cookie.
  assert.deepEqual((await b.call('/api/identity/session')).data, { user: null });
  // Even a manually replayed SID cannot bypass the independent database deadline.
  const replay = await b.call('/api/identity/session', { cookie });
  assert.deepEqual(replay.data, { user: null });
  assert.match(replay.headers['set-cookie'][0], /Max-Age=0$/);
  assert.equal(f.store.get(sid), null);
});

test('idle expiry rejects an unexpired absolute-lifetime browser cookie', async t => {
  const f = await fixture(t, { idleMs: 60000, absoluteMs: 300000 }); const b = f.browser();
  await b.login(); const sid = b.cookie.split('=')[1];
  const authCalls = f.gateway.calls.length;
  f.advance(60000);
  assert.ok(f.now() < b.cookieExpiresAt);
  const result = await b.call('/api/identity/session');
  assert.deepEqual(result.data, { user: null });
  assert.match(result.headers['set-cookie'][0], /Max-Age=0$/);
  assert.equal(f.gateway.calls.length, authCalls);
  assert.equal(f.store.get(sid), null);
});

test('retired SID session responses never overwrite the cookie issued after another login', async t => {
  const f = await fixture(t); const b = f.browser();
  const first = await b.login('user-a'); const retiredCookie = b.cookie;
  assert.match(first.headers['set-cookie'][0], /Max-Age=86400$/);
  await b.login('user-b'); const currentCookie = b.cookie;
  assert.notEqual(currentCookie, retiredCookie);
  const deadline = b.cookieExpiresAt;
  const oldResponse = await b.call('/api/identity/session', { cookie: retiredCookie });
  assert.deepEqual(oldResponse.data, { user: null });
  assert.equal(oldResponse.headers['set-cookie'], undefined);
  assert.equal(b.cookie, currentCookie);
  const reads = await Promise.all(Array.from({ length: 4 }, () => b.call('/api/identity/session')));
  assert.ok(reads.every(result => result.data.user?.id === 'user-b' && result.headers['set-cookie'] === undefined));
  assert.equal(b.cookie, currentCookie);
  assert.equal(b.cookieExpiresAt, deadline);
});

test('pending PKCE timeout rejects a still-live anonymous session', async t => {
  const f = await fixture(t); const b = f.browser(); const begin = await b.begin();
  const code = f.gateway.issueCode(begin.data.authorizationUrl);
  f.advance(f.config.pkceMs + 1);
  assert.equal((await b.call(`/auth/callback?code=${code}`)).status, 400);
  assert.equal((await b.call('/api/identity/session')).data.user, null);
});

test('getUser is authoritative, outages preserve session and invalid identity clears it', async t => {
  const f = await fixture(t); const b = f.browser(); await b.login();
  f.gateway.userFailure = 503;
  assert.equal((await b.call('/api/identity/session')).status, 502);
  f.gateway.userFailure = null;
  assert.equal((await b.call('/api/identity/session')).data.user.id, 'user-a');
  f.gateway.overrideUser = 'user-b';
  assert.deepEqual((await b.call('/api/identity/session')).data, { user: null });
  assert.equal((await b.call('/api/identity/session')).data.user, null);
});

test('near-expiry SDK refresh is persisted and concurrent requests do not reuse refresh tokens', async t => {
  const f = await fixture(t); const b = f.browser(); f.gateway.expirySeconds = 30; await b.login();
  const responses = await Promise.all(Array.from({ length: 8 }, () => b.call('/api/identity/session')));
  assert.ok(responses.every(r => r.data.user?.id === 'user-a'));
  assert.equal(f.gateway.refreshCount, 1);
  await f.restart();
  assert.equal((await b.call('/api/identity/session')).data.user.id, 'user-a');
  assert.equal(f.gateway.refreshCount, 1);
});

test('successful refresh survives a subsequent getUser outage', async t => {
  const f = await fixture(t); const b = f.browser(); f.gateway.expirySeconds = 30; await b.login();
  f.gateway.userFailure = 503;
  assert.equal((await b.call('/api/identity/session')).status, 502);
  assert.equal(f.gateway.refreshCount, 1);
  await f.restart(); f.gateway.userFailure = null;
  assert.equal((await b.call('/api/identity/session')).data.user.id, 'user-a');
  assert.equal(f.gateway.refreshCount, 1);
});

test('sign-out clears local session even when revocation fails and persists encrypted retry', async t => {
  const f = await fixture(t); const b = f.browser(); await b.login(); const old = b.cookie;
  f.gateway.logoutFailure = true;
  const result = await b.call('/api/identity/sign-out', { method: 'POST' });
  assert.equal(result.status, 503); assert.deepEqual(result.data, { user: null, error: 'revocation_pending' });
  assert.match(result.headers['set-cookie'][0], /Max-Age=0/);
  assert.equal((await b.call('/api/identity/session', { cookie: old })).data.user, null);
  const jobs = f.store.db.prepare('SELECT * FROM revocations').all();
  assert.equal(jobs.length, 1); assert.equal(jobs[0].attempts, 1);
  assert.ok(f.store.open(jobs[0].id, jobs[0].payload)['bga-supabase']);
  assert.ok(!Buffer.from(jobs[0].payload).includes(Buffer.from('refresh-secret')));
  await f.restart(); assert.equal(f.store.db.prepare('SELECT count(*) AS n FROM revocations').get().n, 1);
  f.gateway.logoutFailure = false; f.advance(5001); await f.retryRevocations();
  assert.equal(f.store.db.prepare('SELECT count(*) AS n FROM revocations').get().n, 0);
  await b.login();
  assert.deepEqual((await b.call('/api/identity/sign-out', { method: 'POST' })).data, { user: null });
});

test('upstream deadlines terminate hung SDK calls and cannot later write a session', async t => {
  const f = await fixture(t, { timeoutMs: 150 }); const b = f.browser(); await b.login();
  f.gateway.hang = true;
  const start = Date.now(); const result = await b.call('/api/identity/session');
  assert.equal(result.status, 504); assert.ok(Date.now() - start < 1500);
  f.gateway.hang = false;
  assert.equal((await b.call('/api/identity/session')).data.user.id, 'user-a');
});

test('optional fixed userdata proxy verifies user, requires CSRF for PUT and rejects token leaks', async t => {
  const f = await fixture(t, { userdataUrl: 'https://data.example.test/userdata' }); const b = f.browser();
  assert.equal((await b.call('/api/identity/userdata')).status, 401);
  await b.login();
  assert.deepEqual((await b.call('/api/identity/userdata')).data, { favorites: ['azul'] });
  assert.equal((await b.call('/api/identity/userdata', { method: 'PUT', csrf: null, body: { favorites: [] } })).status, 403);
  assert.equal((await b.call('/api/identity/userdata', { method: 'PUT', body: { favorites: [] } })).status, 200);
  const call = f.gateway.calls.find(c => c.url === f.config.userdataUrl);
  assert.match(call.headers.get('authorization'), /^Bearer /); assert.equal(call.headers.get('x-identity-user'), 'user-a');
  f.gateway.proxyData = { access_token: 'upstream-jwt' };
  const result = await b.call('/api/identity/userdata'); assert.equal(result.status, 502); assert.ok(!result.text.includes('upstream-jwt'));
  const session = JSON.parse(f.store.get(b.cookie.split('=')[1]).data.sdk['bga-supabase']);
  f.gateway.proxyData = { debug: session.access_token };
  assert.equal((await b.call('/api/identity/userdata')).status, 502);
  assert.equal((await b.call('/api/identity/userdata?url=https://evil.test')).status, 400);
});

test('database ownership and ciphertext authentication fail closed', async t => {
  const f = await fixture(t); const b = f.browser(); await b.getCsrf();
  assert.throws(() => createIdentityService(f.config, { fetchImpl: f.gateway.fetch }));
  const sid = b.cookie.split('=')[1]; const row = f.store.get(sid);
  const bytes = Buffer.from(f.store.db.prepare('SELECT payload FROM sessions WHERE id=?').get(row.id).payload);
  bytes[bytes.length - 1] ^= 1;
  f.store.db.prepare('UPDATE sessions SET payload=? WHERE id=?').run(bytes, row.id);
  assert.equal((await b.call('/api/identity/session')).data.user, null);
  assert.equal(f.store.get(sid), null);
});
