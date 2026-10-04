import { createHash } from 'node:crypto';
import { resolve } from 'node:path';

function required(env, name) {
  if (!env[name] || env[name].startsWith('REPLACE_')) throw new Error(`Missing configuration: ${name}`);
  return env[name];
}

function httpsUrl(value, originOnly = false) {
  const url = new URL(value);
  if (url.protocol !== 'https:' || url.username || url.password || url.search || url.hash ||
      (originOnly && value !== url.origin)) throw new Error('Expected canonical HTTPS URL');
  return url;
}

function integer(env, name, fallback, min, max) {
  const value = env[name] === undefined ? fallback : Number(env[name]);
  if (!Number.isSafeInteger(value) || value < min || value > max) throw new Error(`Invalid configuration: ${name}`);
  return value;
}

function isPublicKey(value) {
  if (value.length > 16384) return false;
  if (/^sb_publishable_[A-Za-z0-9_-]{16,}$/.test(value)) return true;
  // Classify ONLY the operator-pinned legacy API key, not a user's JWT.
  // Supabase remains responsible for signature verification and authentication.
  if (!/^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(value)) return false;
  try {
    const payload = value.split('.')[1];
    const bytes = Buffer.from(payload, 'base64url');
    if (bytes.toString('base64url') !== payload) return false;
    const claims = JSON.parse(bytes.toString('utf8'));
    return claims !== null && !Array.isArray(claims) && typeof claims === 'object' && claims.role === 'anon';
  } catch { return false; }
}

export function loadConfig(env = process.env) {
  const publicWebOrigin = required(env, 'PUBLIC_WEB_ORIGIN');
  httpsUrl(publicWebOrigin, true);
  const supabaseUrl = required(env, 'SUPABASE_URL');
  httpsUrl(supabaseUrl, true);
  // These are operator-pinned registration values, never supplied by a browser.
  if (supabaseUrl !== required(env, 'REGISTERED_SUPABASE_URL')) throw new Error('Supabase registration mismatch');
  const callbackUrl = `${publicWebOrigin}/auth/callback`;
  if (callbackUrl !== required(env, 'REGISTERED_CALLBACK_URL')) throw new Error('Callback registration mismatch');
  const supabaseKey = required(env, 'SUPABASE_PUBLISHABLE_KEY');
  if (!isPublicKey(supabaseKey)) throw new Error('Only a Supabase publishable or legacy anon key is accepted');
  const fingerprint = createHash('sha256').update(supabaseKey).digest('hex');
  if (fingerprint !== required(env, 'REGISTERED_SUPABASE_KEY_SHA256')) throw new Error('Supabase key registration mismatch');
  const keyText = required(env, 'SESSION_ENCRYPTION_KEY');
  const encryptionKey = Buffer.from(keyText, 'base64');
  if (encryptionKey.length !== 32 || encryptionKey.toString('base64') !== keyText) throw new Error('Expected a base64 32-byte encryption key');
  const userdataUrl = env.USERDATA_UPSTREAM_URL || null;
  if (userdataUrl) {
    httpsUrl(userdataUrl);
    if (userdataUrl !== required(env, 'REGISTERED_USERDATA_UPSTREAM_URL')) throw new Error('Userdata registration mismatch');
  }
  return Object.freeze({
    publicWebOrigin, callbackUrl, supabaseUrl, supabaseKey, encryptionKey, userdataUrl,
    host: '127.0.0.1', port: integer(env, 'PORT', 8787, 1024, 65535),
    databasePath: resolve(env.SESSION_DB_PATH || './data/sessions.sqlite'),
    idleMs: integer(env, 'SESSION_IDLE_SECONDS', 1800, 60, 3600) * 1000,
    absoluteMs: integer(env, 'SESSION_ABSOLUTE_SECONDS', 86400, 300, 604800) * 1000,
    anonymousMs: 600_000, pkceMs: 300_000,
    timeoutMs: integer(env, 'REQUEST_TIMEOUT_MS', 10000, 1000, 30000),
    maxSessions: integer(env, 'MAX_SESSIONS', 10000, 10, 100000),
    maxRequests: 128, maxBodyBytes: 65536,
  });
}
