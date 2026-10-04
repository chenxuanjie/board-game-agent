const required = (env, key) => {
  const value = env[key];
  if (typeof value !== 'string' || !value.trim()) throw new Error('Missing private configuration');
  return value.trim();
};
function origin(value) {
  const url = new URL(value);
  if (url.protocol !== 'https:' || url.username || url.password || url.search || url.hash ||
      !['', '/'].includes(url.pathname) || value.endsWith('/')) throw new Error('HTTPS origin required');
  return url.origin;
}
function integer(env, key, fallback, min, max) {
  const value = env[key] === undefined ? fallback : Number(env[key]);
  if (!Number.isSafeInteger(value) || value < min || value > max) throw new Error('Invalid limit');
  return value;
}
export function loadConfig(env = process.env) {
  const key = required(env, 'SESSION_ENCRYPTION_KEY');
  const encryptionKey = Buffer.from(key, 'base64');
  if (encryptionKey.length !== 32 || encryptionKey.toString('base64') !== key) throw new Error('Invalid encryption key');
  const nasId = required(env, 'NAS_INSTANCE_ID');
  if (!/^[a-zA-Z0-9_-]{16,100}$/.test(nasId)) throw new Error('Invalid NAS identifier');
  const databasePath = required(env, 'SESSION_DB_PATH');
  if (!(databasePath.startsWith('/') || /^[A-Za-z]:[\\/]/.test(databasePath))) throw new Error('Absolute private database path required');
  return {
    publicWebOrigin: origin(required(env, 'PUBLIC_WEB_ORIGIN')),
    nasOrigin: origin(required(env, 'SYNOLOGY_ORIGIN')),
    nasId, encryptionKey, databasePath,
    host: '127.0.0.1', port: integer(env, 'PORT', 8787, 1024, 65535),
    idleMs: integer(env, 'SESSION_IDLE_SECONDS', 1800, 60, 3600) * 1000,
    absoluteMs: integer(env, 'SESSION_ABSOLUTE_SECONDS', 86400, 300, 604800) * 1000,
    anonymousMs: 600000,
    timeoutMs: integer(env, 'REQUEST_TIMEOUT_MS', 15000, 1000, 30000),
    maxSessions: integer(env, 'MAX_SESSIONS', 10000, 10, 100000),
    maxBodyBytes: 8192,
  };
}
