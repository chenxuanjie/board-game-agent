import { DatabaseSync } from 'node:sqlite';
import { createCipheriv, createDecipheriv, createHash, randomBytes } from 'node:crypto';
import { mkdirSync, chmodSync, openSync, closeSync, unlinkSync } from 'node:fs';
import { dirname } from 'node:path';

export const randomToken = () => randomBytes(32).toString('base64url');
export const sidHash = (sid) => createHash('sha256').update(sid).digest('hex');

export class SessionStore {
  constructor(config, now = Date.now) {
    this.config = config;
    this.now = now;
    const path = config.databasePath;
    mkdirSync(dirname(path), { recursive: true, mode: 0o700 });
    // One process owns this database. Cross-process refresh races are unsafe.
    this.lockPath = `${path}.lockfile`;
    this.lock = openSync(this.lockPath, 'wx', 0o600);
    try {
      this.db = new DatabaseSync(path);
      chmodSync(path, 0o600);
      this.db.exec(`PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL; PRAGMA busy_timeout=1000;
        CREATE TABLE IF NOT EXISTS sessions (
          id TEXT PRIMARY KEY, created INTEGER NOT NULL, seen INTEGER NOT NULL,
          expires INTEGER NOT NULL, payload BLOB NOT NULL
        ); CREATE INDEX IF NOT EXISTS session_expiry ON sessions(expires);
        CREATE TABLE IF NOT EXISTS revocations (
          id TEXT PRIMARY KEY, payload BLOB NOT NULL, attempts INTEGER NOT NULL,
          next_attempt INTEGER NOT NULL, expires INTEGER NOT NULL
        ); CREATE TABLE IF NOT EXISTS login_limits (
          id TEXT PRIMARY KEY, attempts INTEGER NOT NULL, expires INTEGER NOT NULL
        ); CREATE TABLE IF NOT EXISTS registration (id TEXT PRIMARY KEY, value TEXT NOT NULL);`);
      const pin = sidHash(`${config.nasId}|${config.nasOrigin}|${config.encryptionKey.toString('base64')}`);
      const registration = this.db.prepare('SELECT value FROM registration WHERE id=?').get('synology-auth-v1');
      if (registration && registration.value !== pin) throw new Error('Registration mismatch');
      if (!registration) {
        if (this.db.prepare('SELECT count(*) AS n FROM sessions').get().n) throw new Error('Separate authentication database required');
        this.db.prepare('INSERT INTO registration VALUES (?, ?)').run('synology-auth-v1', pin);
      }
      this.cleanup();
    } catch (error) {
      this.close();
      throw error;
    }
  }

  seal(id, data) {
    const iv = randomBytes(12);
    const cipher = createCipheriv('aes-256-gcm', this.config.encryptionKey, iv);
    cipher.setAAD(Buffer.from(`synology-auth-v1:${id}`));
    const ciphertext = Buffer.concat([cipher.update(JSON.stringify(data), 'utf8'), cipher.final()]);
    return Buffer.concat([iv, cipher.getAuthTag(), ciphertext]);
  }

  open(id, blob) {
    const bytes = Buffer.from(blob);
    const cipher = createDecipheriv('aes-256-gcm', this.config.encryptionKey, bytes.subarray(0, 12));
    cipher.setAAD(Buffer.from(`synology-auth-v1:${id}`));
    cipher.setAuthTag(bytes.subarray(12, 28));
    return JSON.parse(Buffer.concat([cipher.update(bytes.subarray(28)), cipher.final()]).toString('utf8'));
  }

  cleanup() {
    const expired = this.db.prepare('SELECT * FROM sessions WHERE expires <= ? OR seen <= ? LIMIT 1000').all(this.now(), this.now() - this.config.idleMs);
    for (const row of expired) {
      try { this.revokeAndDelete({ ...row, data: this.open(row.id, row.payload) }); }
      catch { this.delete(row.id); }
    }
    this.db.prepare('DELETE FROM revocations WHERE expires <= ?').run(this.now());
    this.db.prepare('DELETE FROM login_limits WHERE expires <= ?').run(this.now());
  }

  create(authenticated = false, nas = {}, user = null, mode = 'web', cleanup = true) {
    if (cleanup) this.cleanup();
    if (!this.capacityAvailable()) throw new Error('Session capacity');
    const sid = randomToken();
    const now = this.now();
    const row = {
      id: sidHash(sid), created: now, seen: now,
      expires: now + (authenticated ? this.config.absoluteMs : Math.min(this.config.anonymousMs, this.config.absoluteMs)),
      data: { authenticated, csrf: randomToken(), nas, user, mode },
    };
    this.save(row);
    return { sid, row };
  }

  get(sid) {
    const id = sidHash(sid);
    const row = this.db.prepare('SELECT * FROM sessions WHERE id = ?').get(id);
    if (!row) return null;
    if (row.expires <= this.now() || row.seen + this.config.idleMs <= this.now()) {
      try { this.revokeAndDelete({ ...row, data: this.open(id, row.payload) }); }
      catch { this.delete(id); }
      return null;
    }
    try {
      return { ...row, data: this.open(id, row.payload) };
    } catch {
      // Corrupt or wrong-key rows cannot authenticate anyone.
      this.delete(id);
      return null;
    }
  }

  save(row) {
    row.seen = this.now();
    this.db.prepare(`INSERT INTO sessions (id, created, seen, expires, payload) VALUES (?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET seen=excluded.seen, payload=excluded.payload`)
      .run(row.id, row.created, row.seen, row.expires, this.seal(row.id, row.data));
  }

  isLive(id) {
    const row = this.db.prepare('SELECT seen, expires FROM sessions WHERE id=?').get(id);
    return !!row && row.expires > this.now() && row.seen + this.config.idleMs > this.now();
  }

  has(sid) { return !!this.db.prepare('SELECT id FROM sessions WHERE id=?').get(sidHash(sid)); }

  capacityAvailable() {
    return this.db.prepare('SELECT (SELECT count(*) FROM sessions) + (SELECT count(*) FROM revocations) AS n').get().n < this.config.maxSessions;
  }

  rotate(oldRow, nas, user, mode) {
    this.cleanup();
    this.db.exec('BEGIN IMMEDIATE');
    try {
      if (oldRow) this.delete(oldRow.id);
      const next = this.create(true, nas, user, mode, false);
      this.db.exec('COMMIT');
      return next;
    } catch (error) {
      this.db.exec('ROLLBACK');
      throw error;
    }
  }

  delete(id) { this.db.prepare('DELETE FROM sessions WHERE id = ?').run(id); }

  enqueueRevocation(id, nas) {
    this.db.prepare('INSERT OR IGNORE INTO revocations VALUES (?, ?, 0, ?, ?)')
      .run(id, this.seal(id, nas), this.now(), this.now() + 86400_000);
  }

  revokeAndDelete(row) {
    this.db.exec('BEGIN IMMEDIATE');
    try {
      if (row.data.nas?.sid) {
        this.db.prepare(`INSERT OR IGNORE INTO revocations VALUES (?, ?, 0, ?, ?)`)
          .run(row.id, this.seal(row.id, row.data.nas), this.now(), this.now() + 86400_000);
      }
      this.delete(row.id);
      this.db.exec('COMMIT');
    } catch (error) { this.db.exec('ROLLBACK'); throw error; }
  }

  consumeLogin(account) {
    this.db.prepare('DELETE FROM login_limits WHERE expires <= ?').run(this.now());
    const id = sidHash(`${this.config.nasId}|${account.toLowerCase()}`);
    const existing = this.db.prepare('SELECT * FROM login_limits WHERE id=?').get(id);
    if (!existing && this.db.prepare('SELECT count(*) AS n FROM login_limits').get().n >= this.config.maxSessions) return false;
    if (existing && existing.expires > this.now() && existing.attempts >= 5) return false;
    if (!existing || existing.expires <= this.now()) {
      this.db.prepare('INSERT OR REPLACE INTO login_limits VALUES (?, 1, ?)').run(id, this.now() + 900000);
    } else this.db.prepare('UPDATE login_limits SET attempts=attempts+1 WHERE id=?').run(id);
    return true;
  }
  clearLoginLimit(account) { this.db.prepare('DELETE FROM login_limits WHERE id=?').run(sidHash(`${this.config.nasId}|${account.toLowerCase()}`)); }

  pendingRevocations() {
    this.cleanup();
    return this.db.prepare('SELECT * FROM revocations WHERE next_attempt <= ? AND attempts < 12 LIMIT 8').all(this.now());
  }

  finishRevocation(id, success, sdk) {
    if (success) this.db.prepare('DELETE FROM revocations WHERE id = ?').run(id);
    else if (sdk) this.db.prepare(`UPDATE revocations SET attempts=attempts+1, payload=?,
      next_attempt=? + min(3600000, 5000 * (1 << attempts)) WHERE id=?`).run(this.seal(id, sdk), this.now(), id);
    else this.db.prepare(`UPDATE revocations SET attempts=attempts+1,
      next_attempt=? + min(3600000, 5000 * (1 << attempts)) WHERE id=?`).run(this.now(), id);
  }
  close() {
    this.db?.close();
    if (this.lock !== undefined) { closeSync(this.lock); unlinkSync(this.lockPath); this.lock = undefined; }
  }
}
