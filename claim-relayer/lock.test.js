// ABOUTME: Unit tests for the relayer's single-instance lock (lock.js): owner format, stale and foreign locks.
// ABOUTME: Run with `node --test` from claim-relayer/; no network, no chain, temp files only.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { acquireLock } from './lock.js';

function tmpDb(t) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'relayer-lock-'));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  return path.join(dir, 'relayer.db');
}

const readLock = (db) => JSON.parse(fs.readFileSync(`${db}.lock`, 'utf8'));

test('takes a free lock and records host and pid', (t) => {
  const db = tmpDb(t);
  const lock = acquireLock(db, { host: 'pod-a', pid: 7, isAlive: () => false });
  assert.equal(lock.acquired, true);
  assert.deepEqual(readLock(db), { host: 'pod-a', pid: 7 });
});

test('refuses a lock held by a live process on the same host', (t) => {
  const db = tmpDb(t);
  fs.writeFileSync(`${db}.lock`, JSON.stringify({ host: 'vm', pid: 42 }));
  const lock = acquireLock(db, { host: 'vm', pid: 7, isAlive: (pid) => pid === 42 });
  assert.equal(lock.acquired, false);
  assert.deepEqual(lock.holder, { host: 'vm', pid: 42 });
  assert.deepEqual(readLock(db), { host: 'vm', pid: 42 });
});

test('takes over a lock left by a dead process on the same host', (t) => {
  const db = tmpDb(t);
  fs.writeFileSync(`${db}.lock`, JSON.stringify({ host: 'vm', pid: 42 }));
  const lock = acquireLock(db, { host: 'vm', pid: 7, isAlive: () => false });
  assert.equal(lock.acquired, true);
  assert.deepEqual(readLock(db), { host: 'vm', pid: 7 });
});

test('takes over a lock from another host even if that pid is alive here (container PID 1)', (t) => {
  const db = tmpDb(t);
  fs.writeFileSync(`${db}.lock`, JSON.stringify({ host: 'claim-relayer-29012345-abcde', pid: 1 }));
  const lock = acquireLock(db, { host: 'claim-relayer-29012346-fghij', pid: 1, isAlive: () => true });
  assert.equal(lock.acquired, true);
  assert.deepEqual(readLock(db), { host: 'claim-relayer-29012346-fghij', pid: 1 });
});

test('treats a legacy bare-pid lock as same-host (behaviour on the VM is unchanged)', (t) => {
  const db = tmpDb(t);
  fs.writeFileSync(`${db}.lock`, '42');
  const held = acquireLock(db, { host: 'vm', pid: 7, isAlive: (pid) => pid === 42 });
  assert.equal(held.acquired, false);
  assert.deepEqual(held.holder, { host: 'vm', pid: 42 });
  const free = acquireLock(db, { host: 'vm', pid: 7, isAlive: () => false });
  assert.equal(free.acquired, true);
});

test('release removes the lock and is safe to call twice', (t) => {
  const db = tmpDb(t);
  const lock = acquireLock(db, { host: 'pod-a', pid: 7, isAlive: () => false });
  lock.release();
  assert.equal(fs.existsSync(`${db}.lock`), false);
  lock.release();
});

test('release leaves alone a lock that another owner took over', (t) => {
  const db = tmpDb(t);
  const lock = acquireLock(db, { host: 'pod-a', pid: 7, isAlive: () => false });
  fs.writeFileSync(`${db}.lock`, JSON.stringify({ host: 'pod-b', pid: 1 }));
  lock.release();
  assert.deepEqual(readLock(db), { host: 'pod-b', pid: 1 });
});

test('a stale lock is taken over once: the next contender sees the new live owner', (t) => {
  const db = tmpDb(t);
  fs.writeFileSync(`${db}.lock`, JSON.stringify({ host: 'vm', pid: 42 }));
  const alive = new Set();
  const first = acquireLock(db, { host: 'vm', pid: 7, isAlive: (pid) => alive.has(pid) });
  alive.add(7);
  const second = acquireLock(db, { host: 'vm', pid: 8, isAlive: (pid) => alive.has(pid) });
  assert.equal(first.acquired, true);
  assert.equal(second.acquired, false);
  assert.deepEqual(second.holder, { host: 'vm', pid: 7 });
  assert.deepEqual(fs.readdirSync(path.dirname(db)), ['relayer.db.lock']);
});

test('a takeover in progress (fresh marker) makes the contender back off', (t) => {
  const db = tmpDb(t);
  fs.writeFileSync(`${db}.lock`, JSON.stringify({ host: 'vm', pid: 42 }));
  fs.writeFileSync(`${db}.lock.takeover`, JSON.stringify({ host: 'vm', pid: 9 }));
  const lock = acquireLock(db, { host: 'vm', pid: 7, isAlive: () => false });
  assert.equal(lock.acquired, false);
  assert.deepEqual(lock.holder, { host: 'vm', pid: 9 });
  assert.deepEqual(readLock(db), { host: 'vm', pid: 42 });
});

test('a marker left by a takeover that died is cleared after 30 s', (t) => {
  const db = tmpDb(t);
  fs.writeFileSync(`${db}.lock`, JSON.stringify({ host: 'old-pod', pid: 1 }));
  fs.writeFileSync(`${db}.lock.takeover`, JSON.stringify({ host: 'old-pod', pid: 1 }));
  const old = new Date(Date.now() - 60_000);
  fs.utimesSync(`${db}.lock.takeover`, old, old);
  const lock = acquireLock(db, { host: 'new-pod', pid: 1, isAlive: () => true });
  assert.equal(lock.acquired, true);
  assert.deepEqual(readLock(db), { host: 'new-pod', pid: 1 });
  assert.equal(fs.existsSync(`${db}.lock.takeover`), false);
});
