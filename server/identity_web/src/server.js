import { createServer } from 'node:http';
import { timingSafeEqual } from 'node:crypto';
import { createClient } from '@supabase/supabase-js';
import { SessionStore, randomToken } from './store.js';

export const COOKIE_NAME = '__Host-bga_sid';
export const PROVIDER_ID = 'custom:synology';
const STORAGE_KEY = 'bga-supabase';

class HttpError extends Error {
  constructor(status, code) { super(code); this.status = status; this.code = code; }
}
const fail = (status, code) => { throw new HttpError(status, code); };
const sameToken = (a, b) => typeof a === 'string' && typeof b === 'string' &&
  /^[A-Za-z0-9_-]{43}$/.test(a) && /^[A-Za-z0-9_-]{43}$/.test(b) && timingSafeEqual(Buffer.from(a), Buffer.from(b));

function cookieSid(req) {
  const entries = (req.headers.cookie || '').split(';').map(s => s.trim()).filter(s => s.startsWith(`${COOKIE_NAME}=`));
  if (entries.length !== 1) return null;
  const value = entries[0].slice(COOKIE_NAME.length + 1);
  return /^[A-Za-z0-9_-]{43}$/.test(value) ? value : null;
}

function setCookie(res, sid, expires, now) {
  // Authenticated expiry is absolute, not idle. Database `seen` slides idle;
  // session reads must not reissue an SID that could overwrite a rotated cookie.
  const age = Math.max(0, Math.ceil((expires - now) / 1000));
  res.setHeader('Set-Cookie', `${COOKIE_NAME}=${sid}; Path=/; HttpOnly; Secure; SameSite=Lax; Max-Age=${age}`);
}
const clearCookie = res => res.setHeader('Set-Cookie', `${COOKIE_NAME}=; Path=/; HttpOnly; Secure; SameSite=Lax; Max-Age=0`);

function json(res, status, value) {
  res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8' });
  res.end(JSON.stringify(value));
}

async function readBody(req, signal, limit, empty = false) {
  const parts = [];
  let size = 0;
  for await (const part of req) {
    signal.throwIfAborted();
    size += part.length;
    if (size > limit) fail(413, 'body_too_large');
    parts.push(part);
  }
  const text = Buffer.concat(parts).toString('utf8');
  if (empty && text === '') return null;
  if (!/^application\/json(?:\s*;.*)?$/i.test(req.headers['content-type'] || '')) fail(415, 'json_required');
  let data;
  try { data = JSON.parse(text); } catch { fail(400, 'invalid_json'); }
  if (!data || Array.isArray(data) || typeof data !== 'object') fail(400, 'object_required');
  if (empty && Object.keys(data).length) fail(400, 'empty_body_required');
  return data;
}

function sdkResult(result) {
  if (result.error) {
    if (result.error.code === 'bff_timeout') fail(504, 'upstream_timeout');
    if (result.error.code === 'bff_unavailable') fail(502, 'identity_unavailable');
    if ([401, 403].includes(result.error.status) ||
        ['refresh_token_not_found', 'refresh_token_already_used', 'session_not_found', 'bad_jwt'].includes(result.error.code)) {
      fail(401, 'session_invalid');
    }
    fail(502, 'identity_unavailable');
  }
  return result.data;
}

function publicUser(user) {
  if (!user || typeof user.id !== 'string' || !user.id || user.id.length > 200) fail(401, 'session_invalid');
  const clean = (v, limit) => typeof v === 'string' ? v.replace(/[\x00-\x1f\x7f]/g, '').slice(0, limit) : null;
  const metadata = user.user_metadata;
  const displayName = ['full_name', 'name', 'display_name', 'preferred_username', 'username', 'nickname']
    .map(key => clean(metadata?.[key], 200)?.trim()).find(value => value) || null;
  return {
    id: user.id, email: clean(user.email, 320),
    displayName,
  };
}

// Do not turn the optional data proxy into a token endpoint, even if the upstream errs.
function safeUserdata(data, secrets) {
  const denied = /^(?:access_?token|refresh_?token|id_?token|provider_?token|provider_?refresh_?token|jwt|authorization|cookie|set-cookie|api_?key|publishable_?key|secret|password|code_?verifier)$/i;
  function visit(value, depth = 0) {
    if (depth > 32) fail(502, 'unsafe_userdata_response');
    if (typeof value === 'string' && (secrets.some(s => s && value.includes(s)) ||
        /\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b/.test(value))) fail(502, 'unsafe_userdata_response');
    if (value && typeof value === 'object') {
      for (const [key, child] of Object.entries(value)) {
        if (denied.test(key)) fail(502, 'unsafe_userdata_response');
        visit(child, depth + 1);
      }
    }
  }
  visit(data);
  return data;
}

export function createIdentityService(config, { fetchImpl = fetch, sdkFactory = createClient, now = Date.now, log = () => {} } = {}) {
  const store = new SessionStore(config, now);
  const locks = new Map();
  let active = 0;
  let closing = false;
  let revocationRunning = false;
  const revoking = new Set();

  async function locked(key, signal, work) {
    const previous = locks.get(key) || Promise.resolve();
    let release;
    const done = new Promise(resolve => { release = resolve; });
    const tail = previous.then(() => done);
    locks.set(key, tail);
    try {
      await raceAbort(previous, signal);
      signal.throwIfAborted();
      return await work();
    } finally {
      release();
      if (locks.get(key) === tail) tail.then(() => { if (locks.get(key) === tail) locks.delete(key); });
    }
  }

  async function withSdk(sdk, signal, work, onStorageChange = () => {}) {
    let live = true;
    let budget = 6; // Includes SDK retries; no indefinite retry loop.
    const storage = {
      isServer: true,
      getItem: key => sdk[key] ?? null,
      setItem: (key, value) => { if (live && !signal.aborted) { sdk[key] = value; onStorageChange(); } },
      removeItem: key => { if (live && !signal.aborted) { delete sdk[key]; onStorageChange(); } },
    };
    const boundedFetch = async (input, init = {}) => {
      try {
        signal.throwIfAborted();
        if (--budget < 0) throw new Error('Budget');
        const url = new URL(typeof input === 'string' ? input : input.url ?? String(input));
        if (url.origin !== config.supabaseUrl || !url.pathname.startsWith('/auth/v1/')) throw new Error('Destination');
        const result = await fetchImpl(input, { ...init, redirect: 'error', signal });
        // Buffer inside the deadline: a server can send headers then stall its body.
        const bytes = await boundedBytes(result, signal, 1048576);
        if (!result.ok) {
          let code = 'identity_unavailable';
          try {
            const parsed = JSON.parse(bytes.toString('utf8'));
            if (['refresh_token_not_found', 'refresh_token_already_used', 'session_not_found', 'bad_jwt'].includes(parsed.code)) code = parsed.code;
          } catch { /* Upstream body is never logged or propagated. */ }
          return Response.json({ code, msg: 'Identity request unavailable' }, { status: result.status });
        }
        return new Response([204, 205, 304].includes(result.status) ? null : bytes, { status: result.status, headers: result.headers });
      } catch {
        // SDK network errors otherwise retry internally and may print upstream text.
        // A sanitized non-retryable SDK error lets the next HTTP request retry safely.
        return Response.json({ code: signal.aborted ? 'bff_timeout' : 'bff_unavailable', msg: 'Identity request unavailable' }, { status: 400 });
      }
    };
    const client = sdkFactory(config.supabaseUrl, config.supabaseKey, {
      auth: { storage, storageKey: STORAGE_KEY, flowType: 'pkce', persistSession: true,
        autoRefreshToken: false, detectSessionInUrl: false, debug: false },
      global: { fetch: boundedFetch },
    });
    try { return await raceAbort(Promise.resolve().then(() => work(client.auth)), signal); }
    finally { live = false; await client.auth.dispose(); }
  }

  async function verified(row, signal) {
    return withSdk(row.data.sdk, signal, async auth => {
      let session = sdkResult(await auth.getSession()).session;
      if (!session) fail(401, 'session_invalid');
      if (session.expires_at * 1000 <= now() + 60000) {
        session = sdkResult(await auth.refreshSession({ refresh_token: session.refresh_token })).session;
        if (!session) fail(401, 'session_invalid');
      }
      const user = sdkResult(await auth.getUser(session.access_token)).user;
      const safe = publicUser(user);
      if (row.data.userId && row.data.userId !== safe.id) fail(401, 'session_invalid');
      return { user: safe, session };
    }, () => { if (store.isLive(row.id)) store.save(row); });
  }

  function stillValid(sid, signal) {
    signal.throwIfAborted();
    if (!store.get(sid)) fail(401, 'session_invalid');
  }

  async function revoke(id, sdk, signal) {
    if (revoking.has(id)) return false;
    revoking.add(id);
    // signOut clears SDK storage even on some upstream failures. Keep the last
    // usable session (including any successful refresh) for the encrypted outbox.
    let retrySdk = structuredClone(sdk);
    try {
      await withSdk(sdk, signal, async auth => {
        const result = await auth.signOut({ scope: 'local' });
        if (result.error && ![401, 403, 404].includes(result.error.status)) sdkResult(result);
      }, () => { if (sdk[STORAGE_KEY]) retrySdk = structuredClone(sdk); });
      store.finishRevocation(id, true);
      return true;
    } catch (error) {
      if (error.status === 401) { store.finishRevocation(id, true); return true; }
      store.finishRevocation(id, false, retrySdk); return false;
    }
    finally { revoking.delete(id); }
  }

  async function retryRevocations() {
    if (closing || revocationRunning) return;
    revocationRunning = true;
    try {
      for (const job of store.pendingRevocations()) {
        if (closing) break;
        if (revoking.has(job.id)) continue;
        try { await revoke(job.id, store.open(job.id, job.payload), AbortSignal.timeout(config.timeoutMs)); }
        catch { store.finishRevocation(job.id, false); }
      }
    } finally { revocationRunning = false; }
  }

  async function route(req, res, url, sid, signal) {
    const existed = sid && store.has(sid);
    let row = sid ? store.get(sid) : null;
    // A missing SID can be an in-flight old request after rotation. Its response
    // must not clear the newer cookie. Only a known expired/corrupt row clears it.
    if (!row && existed) clearCookie(res);
    const mutation = req.method === 'POST' || req.method === 'PUT';
    if (mutation) {
      if (req.headers.origin !== config.publicWebOrigin) fail(403, 'origin_rejected');
      if (!row || !sameToken(req.headers['x-csrf-token'], row.data.csrf)) fail(403, 'csrf_rejected');
    }
    const path = url.pathname;
    if (path !== '/auth/callback' && url.search) fail(400, 'query_not_allowed');
    if (req.method === 'GET' && path === '/api/identity/configuration') {
      return json(res, 200, { supabaseUrl: config.supabaseUrl, publishableKey: config.supabaseKey,
        providerId: PROVIDER_ID, webCallback: config.callbackUrl });
    }
    if (req.method === 'GET' && path === '/api/identity/csrf') {
      if (!row) {
        const next = store.create();
        row = next.row;
        setCookie(res, next.sid, row.expires, now());
      } else store.save(row);
      return json(res, 200, { csrfToken: row.data.csrf });
    }
    if (req.method === 'GET' && path === '/api/identity/session') {
      if (!row?.data.authenticated) return json(res, 200, { user: null });
      const { user } = await verified(row, signal);
      stillValid(sid, signal);
      store.save(row);
      return json(res, 200, { user });
    }
    if (req.method === 'POST' && path === '/api/identity/sign-in') {
      await readBody(req, signal, config.maxBodyBytes, true);
      stillValid(sid, signal);
      // Invalidate BEFORE starting OAuth: cancellation cannot resurrect the old account.
      store.revokeAndDelete(row);
      clearCookie(res);
      const next = store.create();
      row = next.row;
      setCookie(res, next.sid, row.expires, now());
      try {
        const data = await withSdk(row.data.sdk, signal, async auth => sdkResult(await auth.signInWithOAuth({
          provider: PROVIDER_ID, options: { redirectTo: config.callbackUrl, skipBrowserRedirect: true },
        })));
        const authorization = new URL(data.url);
        if (authorization.origin !== config.supabaseUrl || authorization.pathname !== '/auth/v1/authorize' ||
            authorization.username || authorization.password || authorization.hash ||
            authorization.searchParams.get('provider') !== PROVIDER_ID ||
            authorization.searchParams.get('redirect_to') !== config.callbackUrl ||
            authorization.searchParams.get('code_challenge_method') !== 's256') fail(502, 'authorization_rejected');
        row.data.loginExpires = now() + config.pkceMs;
        row.data.loginFlowId = data.flowId;
        signal.throwIfAborted();
        store.save(row);
        return json(res, 200, { authorizationUrl: authorization.href });
      } catch (error) { store.revokeAndDelete(row); clearCookie(res); throw error; }
    }
    if (req.method === 'GET' && path === '/auth/callback') {
      if (!row || row.data.authenticated || !row.data.loginExpires || row.data.loginExpires <= now()) fail(400, 'login_expired');
      try {
        const codes = url.searchParams.getAll('code');
        if (url.searchParams.has('error') || codes.length !== 1 || !codes[0] || codes[0].length > 4096 ||
            [...url.searchParams.keys()].some(k => k !== 'code')) fail(400, 'login_failed');
        const userId = await withSdk(row.data.sdk, signal, async auth => {
          const data = sdkResult(await auth.exchangeCodeForSession(codes[0], { flowId: row.data.loginFlowId }));
          if (!data.session) fail(401, 'session_invalid');
          return publicUser(sdkResult(await auth.getUser(data.session.access_token)).user).id;
        });
        stillValid(sid, signal);
        // Never retain SDK verifier slots after a completed flow.
        const sdk = Object.fromEntries(Object.entries(row.data.sdk).filter(([key]) => !key.endsWith('-code-verifier')));
        const next = store.rotate(row, sdk, userId);
        setCookie(res, next.sid, next.row.expires, now());
        res.writeHead(303, { Location: '/' });
        return res.end();
      } catch (error) { store.revokeAndDelete(row); clearCookie(res); throw error; }
    }
    if (req.method === 'POST' && path === '/api/identity/sign-out') {
      await readBody(req, signal, config.maxBodyBytes, true);
      stillValid(sid, signal);
      store.revokeAndDelete(row);
      clearCookie(res);
      const revoked = !row.data.authenticated || await revoke(row.id, row.data.sdk, signal);
      return json(res, revoked ? 200 : 503, revoked ? { user: null } : { user: null, error: 'revocation_pending' });
    }
    if (path === '/api/identity/userdata' && ['GET', 'PUT'].includes(req.method)) {
      if (!config.userdataUrl) fail(404, 'userdata_disabled');
      if (!row?.data.authenticated) fail(401, 'sign_in_required');
      const body = req.method === 'PUT' ? await readBody(req, signal, config.maxBodyBytes) : null;
      const { user, session } = await verified(row, signal);
      stillValid(sid, signal);
      // Persist rotated refresh tokens before an unrelated data-service failure.
      store.save(row);
      let upstream;
      try {
        upstream = await fetchImpl(config.userdataUrl, { method: req.method, redirect: 'error', signal,
          headers: { Authorization: `Bearer ${session.access_token}`, 'Content-Type': 'application/json',
            Accept: 'application/json', 'X-Identity-User': user.id },
          ...(body ? { body: JSON.stringify(body) } : {}),
        });
        const bytes = await boundedBytes(upstream, signal, config.maxBodyBytes);
        if (!upstream.ok) fail(upstream.status === 429 ? 429 : 502, 'userdata_unavailable');
        if (!/^application\/json(?:;|$)/i.test(upstream.headers.get('content-type') || '')) fail(502, 'invalid_userdata');
        const data = JSON.parse(bytes.toString('utf8'));
        const safe = safeUserdata(data, [session.access_token, session.refresh_token,
          session.provider_token, session.provider_refresh_token, config.supabaseKey]);
        stillValid(sid, signal);
        return json(res, 200, safe);
      } catch (error) {
        if (error instanceof HttpError) throw error;
        fail(signal.aborted ? 504 : 502, 'userdata_unavailable');
      }
    }
    fail(404, 'not_found');
  }

  const server = createServer({ maxHeaderSize: 16384 }, async (req, res) => {
    res.setHeader('Cache-Control', 'no-store');
    res.setHeader('Vary', 'Cookie');
    res.setHeader('X-Content-Type-Options', 'nosniff');
    res.setHeader('Referrer-Policy', 'no-referrer');
    res.setHeader('Content-Security-Policy', "default-src 'none'; frame-ancestors 'none'");
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), config.timeoutMs);
    const abort = () => controller.abort();
    req.on('aborted', abort);
    res.on('close', abort);
    const signal = controller.signal;
    const sid = cookieSid(req);
    let counted = false;
    try {
      if (closing || active >= config.maxRequests) fail(503, 'service_busy');
      active++; counted = true;
      // The proxy must overwrite Host; forwarded headers are never trusted here.
      if (req.headers.host !== new URL(config.publicWebOrigin).host) fail(421, 'host_rejected');
      if (req.headers.origin !== undefined && req.headers.origin !== config.publicWebOrigin) fail(403, 'origin_rejected');
      if (!req.url.startsWith('/') || req.url.startsWith('//') || req.url.length > 8192) fail(400, 'invalid_url');
      const url = new URL(req.url, config.publicWebOrigin);
      if (url.pathname !== '/auth/callback' && ['cross-site', 'same-site'].includes(req.headers['sec-fetch-site'])) fail(403, 'origin_rejected');
      if (req.headers.authorization) fail(400, 'cookie_auth_only');
      await locked(sid || randomToken(), signal, () => raceAbort(route(req, res, url, sid, signal), signal));
    } catch (error) {
      const status = signal.aborted ? 504 : error.status || 500;
      const code = signal.aborted ? 'request_timeout' : error.code || 'service_unavailable';
      if (status === 401 && sid) { const row = store.get(sid); if (row) { store.delete(row.id); clearCookie(res); } }
      log({ status, code }); // No URL, cookie, SDK error, headers, code or token text.
      if (!res.headersSent && !res.destroyed) {
        if (signal.aborted) { res.setHeader('Connection', 'close'); res.once('finish', () => req.destroy()); }
        if (status === 401 && req.url === '/api/identity/session') json(res, 200, { user: null });
        else json(res, status, { error: code });
      }
    } finally {
      clearTimeout(timer);
      req.off('aborted', abort); res.off('close', abort);
      if (counted) active--;
    }
  });
  server.requestTimeout = config.timeoutMs;
  server.headersTimeout = config.timeoutMs;
  server.keepAliveTimeout = 5000;
  server.maxRequestsPerSocket = 100;
  server.on('clientError', (_error, socket) => socket.end('HTTP/1.1 400 Bad Request\r\nConnection: close\r\n\r\n'));
  const sweep = setInterval(() => { store.cleanup(); void retryRevocations().catch(() => log({ status: 503, code: 'revocation_retry_failed' })); }, 5000);
  sweep.unref();
  return {
    server, store, retryRevocations,
    async close() {
      closing = true; clearInterval(sweep);
      await new Promise(resolve => server.close(resolve));
      // Retry worker has its own bounded deadlines; finish before closing SQLite.
      while (revocationRunning) await new Promise(resolve => setTimeout(resolve, 10));
      store.close();
    },
  };
}

function raceAbort(promise, signal) {
  return new Promise((resolve, reject) => {
    const abort = () => reject(new HttpError(504, 'request_timeout'));
    if (signal.aborted) return abort();
    signal.addEventListener('abort', abort, { once: true });
    Promise.resolve(promise).then(resolve, reject).finally(() => signal.removeEventListener('abort', abort));
  });
}

async function boundedBytes(response, signal, limit) {
  if (!response.body) return Buffer.alloc(0);
  const reader = response.body.getReader();
  const parts = [];
  let size = 0;
  try {
    while (true) {
      const { done, value } = await raceAbort(reader.read(), signal);
      if (done) break;
      size += value.length;
      if (size > limit) throw new Error('Upstream body limit');
      parts.push(Buffer.from(value));
    }
    return Buffer.concat(parts);
  } finally { void reader.cancel().catch(() => {}); }
}
