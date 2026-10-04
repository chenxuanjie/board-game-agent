import test from 'node:test';
import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { mkdtempSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { SessionStore } from '../src/store.js';

function config(t) {
  const directory = mkdtempSync(join(tmpdir(), 'bga-identity-store-'));
  t.after(() => rmSync(directory, { recursive: true, force: true }));
  return { databasePath: join(directory, 'session.sqlite'), nasId: 'store_fixture_nas_2026',
    nasOrigin: 'https://nas.example.test:5001', encryptionKey: randomBytes(32),
    maxSessions: 10, idleMs: 300000, absoluteMs: 3600000, anonymousMs: 600000 };
}
test('revocation outbox and account attempt limits survive service restart', t => {
  const settings = config(t); let store = new SessionStore(settings);
  const nas = { sid: 'private-session', authPath: 'entry.cgi' };
  const next = store.create(true, nas, { id: 'fixture-user' }, 'native');
  store.revokeAndDelete(next.row);
  for (let i = 0; i < 5; i++) assert.equal(store.consumeLogin('fixture'), true);
  store.close();
  store = new SessionStore(settings);
  try {
    assert.equal(store.get(next.sid), null);
    assert.equal(store.consumeLogin('fixture'), false);
    const pending = store.pendingRevocations();
    assert.equal(pending.length, 1);
    assert.equal(store.open(pending[0].id, pending[0].payload).sid, nas.sid);
    store.finishRevocation(pending[0].id, true);
    assert.equal(store.pendingRevocations().length, 0);
  } finally { store.close(); }
});
test('database rejects changed NAS realm or encryption key rather than adopting identities', t => {
  const settings = config(t); const store = new SessionStore(settings); store.close();
  assert.throws(() => new SessionStore({ ...settings, nasId: 'different_nas_realm_2026' }));
  assert.throws(() => new SessionStore({ ...settings, encryptionKey: randomBytes(32) }));
  const valid = new SessionStore(settings); valid.close();
});
test('tampered session payload cannot authenticate and fails closed', t => {
  const store = new SessionStore(config(t));
  try {
    const next = store.create(true, { sid: 'private' }, { id: 'fixture' }, 'native');
    store.db.prepare('UPDATE sessions SET payload=? WHERE id=?').run(Buffer.from('tampered'), next.row.id);
    assert.equal(store.get(next.sid), null);
    assert.equal(store.has(next.sid), false);
  } finally { store.close(); }
});
