// ABOUTME: Single-instance lock for the relayer: an advisory file next to the DB recording the owner's host and pid.
// ABOUTME: A lock from another host is stale (each Kubernetes Job pod has its own hostname and PID 1).
import fs from 'node:fs';
import os from 'node:os';

const MARKER_TTL_MS = 30_000; // a takeover takes milliseconds; an older marker belongs to a process that died

// Two relayers at once would double-submit and clash nonces, so only one may hold the lock. A second live
// instance on the same host gets { acquired: false } instead of crashing on SQLITE_BUSY. A lock whose owner
// is dead, or that was written on another host, is stale and is taken over: on another host (a previous
// Kubernetes Job pod, where node always runs as PID 1) the pid says nothing about a process here, and the
// scheduler (CronJob concurrencyPolicy: Forbid) is what guarantees there is no other writer.
//
// Takeovers are serialized by an exclusive marker (<lock>.takeover): only the process that creates it may
// replace the stale lock, and only if the lock still holds the stale content it judged. The lock is
// overwritten in place, never removed, so a fresh exclusive create cannot slip in during a takeover.
// Limits, like any lease: a takeover stalled for over MARKER_TTL_MS can lose its marker to another
// contender, and a live owner on another host is not detected. The lock is a second line of defence; the
// scheduler (CronJob Forbid on Kubernetes, `flock -n` in the VM's crontab) is the first.
export function acquireLock(dbFile, { host = os.hostname(), pid = process.pid, isAlive = pidAlive, now = Date.now } = {}) {
  const file = `${dbFile}.lock`;
  const marker = `${file}.takeover`;
  const owner = JSON.stringify({ host, pid });
  const won = () => ({ acquired: true, holder: { host, pid }, release: () => releaseIfOwned(file, owner) });
  const lost = (holder) => ({ acquired: false, holder, release: () => {} });

  for (let attempt = 0; attempt < 3; attempt++) {
    if (createExclusive(file, owner)) return won();
    const text = readIfExists(file);
    if (text === null) continue; // released meanwhile: try to create it again
    const holder = parseOwner(text, host);
    if (holder.host === host && holder.pid && isAlive(holder.pid)) return lost(holder);

    // Stale: dead owner, or written on another host.
    if (!createExclusive(marker, owner)) {
      const stat = statIfExists(marker);
      if (stat && now() - stat.mtimeMs < MARKER_TTL_MS) return lost(parseOwner(readIfExists(marker) ?? '', host));
      fs.rmSync(marker, { force: true }); // left by a takeover that died
      continue;
    }
    try {
      if (readIfExists(file) !== text) continue; // changed hands since we judged it: look again
      fs.writeFileSync(file, owner);
      return won();
    } finally {
      fs.rmSync(marker, { force: true });
    }
  }
  throw new Error(`could not take the lock ${file}: it keeps changing hands`);
}

function createExclusive(file, content) {
  try {
    fs.writeFileSync(file, content, { flag: 'wx' }); // atomic create-if-absent
    return true;
  } catch (e) {
    if (e.code === 'EEXIST') return false;
    throw e;
  }
}

function readIfExists(file) {
  try {
    return fs.readFileSync(file, 'utf8');
  } catch (e) {
    if (e.code === 'ENOENT') return null;
    throw e;
  }
}

function statIfExists(file) {
  try {
    return fs.statSync(file);
  } catch (e) {
    if (e.code === 'ENOENT') return null;
    throw e;
  }
}

// Remove the lock only if it is still ours: never delete a lock another owner has taken over.
function releaseIfOwned(file, owner) {
  if (readIfExists(file) === owner) fs.rmSync(file, { force: true });
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
