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
        );`);
      this.cleanup();
    } catch (error) {
      this.close();
      throw error;
    }
  }

  seal(id, data) {
    const iv = randomBytes(12);
    const cipher = createCipheriv('aes-256-gcm', this.config.encryptionKey, iv);
    cipher.setAAD(Buffer.from(`identity-web-v1:${id}`));
    const ciphertext = Buffer.concat([cipher.update(JSON.stringify(data), 'utf8'), cipher.final()]);
    return Buffer.concat([iv, cipher.getAuthTag(), ciphertext]);
  }

  open(id, blob) {
    const bytes = Buffer.from(blob);
    const cipher = createDecipheriv('aes-256-gcm', this.config.encryptionKey, bytes.subarray(0, 12));
    cipher.setAAD(Buffer.from(`identity-web-v1:${id}`));
    cipher.setAuthTag(bytes.subarray(12, 28));
    return JSON.parse(Buffer.concat([cipher.update(bytes.subarray(28)), cipher.final()]).toString('utf8'));
  }

  cleanup() {
    this.db.prepare('DELETE FROM sessions WHERE expires <= ? OR seen <= ?').run(this.now(), this.now() - this.config.idleMs);
    this.db.prepare('DELETE FROM revocations WHERE expires <= ?').run(this.now());
  }

  create(authenticated = false, sdk = {}) {
    this.cleanup();
    if (this.db.prepare('SELECT (SELECT count(*) FROM sessions) + (SELECT count(*) FROM revocations) AS n').get().n >= this.config.maxSessions) throw new Error('Session capacity');
    const sid = randomToken();
    const now = this.now();
    const row = {
      id: sidHash(sid), created: now, seen: now,
      expires: now + (authenticated ? this.config.absoluteMs : Math.min(this.config.anonymousMs, this.config.absoluteMs)),
      data: { authenticated, csrf: randomToken(), sdk, loginExpires: null, userId: null },
    };
    this.save(row);
    return { sid, row };
  }

  get(sid) {
    const id = sidHash(sid);
    const row = this.db.prepare('SELECT * FROM sessions WHERE id = ?').get(id);
    if (!row) return null;
    if (row.expires <= this.now() || row.seen + this.config.idleMs <= this.now()) {
      this.delete(id);
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

  rotate(oldRow, sdk, userId) {
    this.db.exec('BEGIN IMMEDIATE');
    try {
      this.delete(oldRow.id);
      const next = this.create(true, sdk);
      next.row.data.userId = userId;
      this.save(next.row);
      this.db.exec('COMMIT');
      return next;
    } catch (error) {
      this.db.exec('ROLLBACK');
      throw error;
    }
  }

  delete(id) { this.db.prepare('DELETE FROM sessions WHERE id = ?').run(id); }

  revokeAndDelete(row) {
    this.db.exec('BEGIN IMMEDIATE');
    try {
      if (row.data.sdk['bga-supabase']) {
        this.db.prepare(`INSERT OR IGNORE INTO revocations VALUES (?, ?, 0, ?, ?)`)
          .run(row.id, this.seal(row.id, row.data.sdk), this.now(), this.now() + 86400_000);
      }
      this.delete(row.id);
      this.db.exec('COMMIT');
    } catch (error) { this.db.exec('ROLLBACK'); throw error; }
  }

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
