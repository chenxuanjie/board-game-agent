import { createServer } from 'node:http';
import { timingSafeEqual } from 'node:crypto';
import { SessionStore, sidHash, randomToken } from './store.js';
import { SynologyClient, IdentityError } from './synology.js';

export const COOKIE_NAME = '__Host-bga_synology';
const fail = (status, code) => { throw new IdentityError(status, code); };
const validToken = token => typeof token === 'string' && /^[A-Za-z0-9_-]{43}$/.test(token);
const sameToken = (a, b) => validToken(a) && validToken(b) && timingSafeEqual(Buffer.from(a), Buffer.from(b));
function cookie(req) {
  const values = (req.headers.cookie || '').split(';').map(v => v.trim()).filter(v => v.startsWith(`${COOKIE_NAME}=`));
  const value = values.length === 1 ? values[0].slice(COOKIE_NAME.length + 1) : null;
  return validToken(value) ? value : null;
}
function setCookie(res, sid, expires, now) {
  res.setHeader('Set-Cookie', `${COOKIE_NAME}=${sid}; Path=/; HttpOnly; Secure; SameSite=Lax; Max-Age=${Math.max(0, Math.ceil((expires - now) / 1000))}`);
}
const clearCookie = res => res.setHeader('Set-Cookie', `${COOKIE_NAME}=; Path=/; HttpOnly; Secure; SameSite=Lax; Max-Age=0`);
function json(res, status, data) {
  if (res.destroyed || res.writableEnded) return;
  res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8' });
  res.end(JSON.stringify(data));
}
async function body(req, signal, limit) {
  if (!/^application\/json(?:\s*;.*)?$/i.test(req.headers['content-type'] || '')) fail(415, 'json_required');
  const parts = [];
  let length = 0;
  const abort = () => { if (!req.complete) req.destroy(); };
  signal.throwIfAborted();
  signal.addEventListener('abort', abort, { once: true });
  try {
    for await (const part of req) {
      signal.throwIfAborted(); length += part.length;
      if (length > limit) fail(413, 'body_too_large');
      parts.push(part);
    }
  } finally {
    signal.removeEventListener('abort', abort);
  }
  let value;
  try { value = JSON.parse(Buffer.concat(parts).toString('utf8')); } catch { fail(400, 'invalid_json'); }
  if (!value || typeof value !== 'object' || Array.isArray(value)) fail(400, 'object_required');
  return value;
}
function credentials(data) {
  if (Object.keys(data).some(key => !['account', 'password', 'otp'].includes(key))) fail(400, 'invalid_credentials_format');
  if (typeof data.account !== 'string' || !data.account.trim() || data.account.length > 200 || /[\x00-\x1f\x7f]/.test(data.account) ||
      typeof data.password !== 'string' || !data.password || data.password.length > 1024 ||
      (data.otp !== undefined && (typeof data.otp !== 'string' || !/^\d{6,8}$/.test(data.otp)))) fail(400, 'invalid_credentials_format');
  return { account: data.account.trim(), password: data.password, otp: data.otp };
}
export function createIdentityService(config, { fetchImpl = fetch, now = Date.now, log = () => {} } = {}) {
  const store = new SessionStore(config, now);
  const nas = new SynologyClient(config, fetchImpl);
  const locks = new Map();
  const controllers = new Set();
  let active = 0, closing = false, retrying = false;
  let windowAt = now(), windowRequests = 0;
  async function locked(key, signal, work) {
    const previous = locks.get(key) || Promise.resolve();
    let release;
    const done = new Promise(resolve => { release = resolve; });
    const tail = previous.then(() => done);
    locks.set(key, tail);
    try { await abortable(previous, signal); signal.throwIfAborted(); return await work(); }
    finally { release(); if (locks.get(key) === tail) tail.then(() => { if (locks.get(key) === tail) locks.delete(key); }); }
  }
  async function revoke(id, record) {
    try { await nas.logout(record, AbortSignal.timeout(config.timeoutMs)); store.finishRevocation(id, true); return true; }
    catch { store.finishRevocation(id, false, record); return false; }
  }
  async function retryRevocations() {
    if (closing || retrying) return;
    retrying = true;
    try {
      for (const job of store.pendingRevocations()) {
        if (closing) break;
        await locked(`revoke:${job.id}`, AbortSignal.timeout(config.timeoutMs), async () => {
          try { await revoke(job.id, store.open(job.id, job.payload)); }
          catch { store.finishRevocation(job.id, false); }
        });
      }
    } finally { retrying = false; }
  }
  async function route(req, res, url, signal, mode, sid) {
    let row = sid ? store.get(sid) : null;
    if (row && row.data.mode !== mode) fail(401, 'session_invalid');
    const mutation = req.method === 'POST';
    if (mode === 'web' && mutation) {
      if (req.headers.origin !== config.publicWebOrigin) fail(403, 'origin_rejected');
      if (!row || !sameToken(req.headers['x-csrf-token'], row.data.csrf)) fail(403, 'csrf_rejected');
    }
    const path = url.pathname;
    if (url.search) fail(400, 'query_not_allowed');
    if (req.method === 'GET' && path === '/api/identity/configuration') {
      return json(res, 200, { version: 2, authType: 'synology-api-auth', nasId: config.nasId, serviceUrl: config.publicWebOrigin });
    }
    if (req.method === 'GET' && path === '/api/identity/csrf' && mode === 'web') {
      if (!row) { const next = store.create(); row = next.row; setCookie(res, next.sid, row.expires, now()); }
      else store.save(row);
      return json(res, 200, { csrfToken: row.data.csrf });
    }
    if (req.method === 'GET' && path === '/api/identity/session') {
      if (!row?.data.authenticated) return json(res, 200, { user: null });
      try {
        const uid = await nas.profile(row.data.nas, signal);
        if (uid !== row.data.nas.uid || !store.isLive(row.id)) fail(401, 'session_invalid');
        signal.throwIfAborted(); store.save(row);
        return json(res, 200, { user: row.data.user });
      } catch (error) {
        if (error.code === 'session_invalid') { store.revokeAndDelete(row); return json(res, 200, { user: null }); }
        throw error;
      }
    }
    if (req.method === 'POST' && path === '/api/identity/sign-in') {
      if (row?.data.authenticated) fail(409, 'already_signed_in');
      const data = await body(req, signal, config.maxBodyBytes);
      const fields = credentials(data);
      store.cleanup();
      if (!store.capacityAvailable()) fail(503, 'identity_unavailable');
      if (!store.consumeLogin(fields.account)) fail(429, 'rate_limited');
      let record, accepted = false;
      try {
        record = await nas.login(fields.account, fields.password, fields.otp, signal);
        // The password is never persisted, logged or retained for OTP retry.
        fields.password = ''; data.password = ''; delete data.otp;
        const uid = await nas.profile(record, signal);
        signal.throwIfAborted();
        if (row && !store.isLive(row.id)) fail(401, 'session_invalid');
        record.uid = uid;
        const user = { id: sidHash(`${config.nasId}|${uid}`), displayName: fields.account, email: null };
        const next = store.rotate(row, record, user, mode);
        store.clearLoginLimit(fields.account);
        if (mode === 'web') setCookie(res, next.sid, next.row.expires, now());
        res.once('close', () => {
          if (!res.writableFinished) { store.revokeAndDelete(next.row); void retryRevocations(); }
        });
        accepted = true;
        return json(res, 200, { user, ...(mode === 'native' ? { sessionToken: next.sid } : {}) });
      } finally {
        fields.password = ''; data.password = ''; delete data.otp;
        if (record && !accepted) {
          const id = sidHash(randomToken());
          store.enqueueRevocation(id, record);
          await revoke(id, record);
        }
      }
    }
    if (req.method === 'POST' && path === '/api/identity/sign-out') {
      const data = await body(req, signal, config.maxBodyBytes);
      if (Object.keys(data).length) fail(400, 'empty_body_required');
      if (mode === 'web') clearCookie(res);
      if (!row) return json(res, 200, { user: null });
      store.revokeAndDelete(row);
      const revoked = !row.data.nas?.sid || await locked(`revoke:${row.id}`, signal, () => revoke(row.id, row.data.nas));
      return json(res, revoked ? 200 : 503, { user: null, ...(revoked ? {} : { error: 'revocation_pending' }) });
    }
    fail(404, 'not_found');
  }
  const server = createServer(async (req, res) => {
    res.setHeader('Cache-Control', 'no-store');
    res.setHeader('X-Content-Type-Options', 'nosniff');
    const controller = new AbortController();
    const signal = controller.signal;
    const timeout = setTimeout(() => controller.abort(), config.timeoutMs);
    controllers.add(controller);
    const cancel = () => { if (!res.writableEnded) controller.abort(); };
    req.once('aborted', cancel); res.once('close', cancel);
    try {
      if (closing || active >= 128) fail(503, 'identity_unavailable');
      if (req.headers.host !== new URL(config.publicWebOrigin).host) fail(403, 'host_rejected');
      const native = req.headers['x-identity-client'] === 'native-v1';
      if (native && (req.headers.origin || req.headers['sec-fetch-site'] || req.headers.cookie)) fail(403, 'native_browser_rejected');
      if (!native && req.headers.authorization) fail(403, 'browser_token_rejected');
      if (req.headers['x-identity-client'] && !native) fail(403, 'client_rejected');
      if (now() - windowAt >= 60000) { windowAt = now(); windowRequests = 0; }
      if (++windowRequests > 600) fail(429, 'rate_limited');
      const authorization = req.headers.authorization;
      const token = native && authorization?.startsWith('Bearer ') ? authorization.slice(7) : null;
      if (authorization && !validToken(token)) fail(401, 'session_invalid');
      const sid = native ? token : cookie(req);
      const url = new URL(req.url, config.publicWebOrigin);
      const key = sid ? sidHash(sid) : `anonymous:${req.socket.remoteAddress}`;
      active++;
      try { await locked(key, signal, () => route(req, res, url, signal, native ? 'native' : 'web', sid)); }
      finally { active--; }
    } catch (error) {
      const status = signal.aborted ? 504 : (error.status || 500);
      const code = signal.aborted ? 'upstream_timeout' : (error instanceof IdentityError ? error.code : 'identity_unavailable');
      // Never log req.url, body, cookies, headers or upstream exceptions.
      log({ status, code });
      json(res, status, { error: code });
    } finally { clearTimeout(timeout); controllers.delete(controller); }
  });
  server.requestTimeout = config.timeoutMs;
  server.headersTimeout = Math.min(config.timeoutMs, 10000);
  const retryTimer = setInterval(() => { void retryRevocations().catch(() => {}); }, 5000);
  retryTimer.unref();
  return { server, store, retryRevocations, async close() {
    closing = true; clearInterval(retryTimer);
    for (const controller of controllers) controller.abort();
    if (server.listening) await new Promise(resolve => server.close(resolve));
    const tails = [...locks.values()];
    await Promise.allSettled(tails);
    while (retrying) await new Promise(resolve => setTimeout(resolve, 10));
    store.close();
  } };
}
function abortable(promise, signal) {
  signal.throwIfAborted();
  return new Promise((resolve, reject) => {
    const abort = () => reject(new IdentityError(504, 'upstream_timeout'));
    signal.addEventListener('abort', abort, { once: true });
    promise.then(resolve, reject).finally(() => signal.removeEventListener('abort', abort));
  });
}
