// ABOUTME: Unit tests for the relayer's single-instance lock (lock.js): owner format, stale and foreign locks.
// ABOUTME: Run with `node --test` from claim-relayer/; no network, no chain, temp files only.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { acquireLock } from './lock.js';

function tmpDb() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'relayer-lock-'));
  return path.join(dir, 'relayer.db');
}

const readLock = (db) => JSON.parse(fs.readFileSync(`${db}.lock`, 'utf8'));

test('takes a free lock and records host and pid', () => {
  const db = tmpDb();
  const lock = acquireLock(db, { host: 'pod-a', pid: 7, isAlive: () => false });
  assert.equal(lock.acquired, true);
  assert.deepEqual(readLock(db), { host: 'pod-a', pid: 7 });
});

test('refuses a lock held by a live process on the same host', () => {
  const db = tmpDb();
  fs.writeFileSync(`${db}.lock`, JSON.stringify({ host: 'vm', pid: 42 }));
  const lock = acquireLock(db, { host: 'vm', pid: 7, isAlive: (pid) => pid === 42 });
  assert.equal(lock.acquired, false);
  assert.deepEqual(lock.holder, { host: 'vm', pid: 42 });
  assert.deepEqual(readLock(db), { host: 'vm', pid: 42 });
});

test('takes over a lock left by a dead process on the same host', () => {
  const db = tmpDb();
  fs.writeFileSync(`${db}.lock`, JSON.stringify({ host: 'vm', pid: 42 }));
  const lock = acquireLock(db, { host: 'vm', pid: 7, isAlive: () => false });
  assert.equal(lock.acquired, true);
  assert.deepEqual(readLock(db), { host: 'vm', pid: 7 });
});

test('takes over a lock from another host even if that pid is alive here (container PID 1)', () => {
  const db = tmpDb();
  fs.writeFileSync(`${db}.lock`, JSON.stringify({ host: 'claim-relayer-29012345-abcde', pid: 1 }));
  const lock = acquireLock(db, { host: 'claim-relayer-29012346-fghij', pid: 1, isAlive: () => true });
  assert.equal(lock.acquired, true);
  assert.deepEqual(readLock(db), { host: 'claim-relayer-29012346-fghij', pid: 1 });
});

test('treats a legacy bare-pid lock as same-host (behaviour on the VM is unchanged)', () => {
  const db = tmpDb();
  fs.writeFileSync(`${db}.lock`, '42');
  const held = acquireLock(db, { host: 'vm', pid: 7, isAlive: (pid) => pid === 42 });
  assert.equal(held.acquired, false);
  assert.deepEqual(held.holder, { host: 'vm', pid: 42 });
  const free = acquireLock(db, { host: 'vm', pid: 7, isAlive: () => false });
  assert.equal(free.acquired, true);
});

test('release removes the lock and is safe to call twice', () => {
  const db = tmpDb();
  const lock = acquireLock(db, { host: 'pod-a', pid: 7, isAlive: () => false });
  lock.release();
  assert.equal(fs.existsSync(`${db}.lock`), false);
  lock.release();
});
