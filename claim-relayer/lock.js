// ABOUTME: Single-instance lock for the relayer: an advisory file next to the DB recording the owner's host and pid.
// ABOUTME: A lock from another host is stale (each Kubernetes Job pod has its own hostname and PID 1).
import fs from 'node:fs';
import os from 'node:os';

// Two relayers at once would double-submit and clash nonces, so only one may hold the lock. A second live
// instance on the same host gets { acquired: false } instead of crashing on SQLITE_BUSY. A lock whose owner
// is dead, or that was written on another host, is stale and is taken over: on another host (a previous
// Kubernetes Job pod, where node always runs as PID 1) the pid says nothing about a process here, and the
// scheduler (CronJob concurrencyPolicy: Forbid) is what guarantees there is no other writer.
export function acquireLock(dbFile, { host = os.hostname(), pid = process.pid, isAlive = pidAlive } = {}) {
  const file = `${dbFile}.lock`;
  const owner = JSON.stringify({ host, pid });
  try {
    fs.writeFileSync(file, owner, { flag: 'wx' }); // atomic create-if-absent
  } catch (e) {
    if (e.code !== 'EEXIST') throw e;
    const holder = parseOwner(fs.readFileSync(file, 'utf8'), host);
    if (holder.host === host && holder.pid && isAlive(holder.pid)) return { acquired: false, holder, release: () => {} };
    fs.writeFileSync(file, owner); // stale: dead owner, or written on another host
  }
  return { acquired: true, holder: { host, pid }, release: () => fs.rmSync(file, { force: true }) };
}

// Locks written before this format held only the pid; they come from the host we are on.
function parseOwner(text, host) {
  try {
    const { host: h, pid } = JSON.parse(text);
    if (typeof h === 'string') return { host: h, pid: Number(pid) };
  } catch { /* legacy bare pid */ }
  return { host, pid: parseInt(text.trim(), 10) };
}

function pidAlive(pid) {
  try {
    process.kill(pid, 0);
    return true;
  } catch (err) {
    return err.code === 'EPERM'; // exists but owned by another user
  }
}
