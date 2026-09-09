// Durable per-row state for the relayer, backed by SQLite (node:sqlite — built-in, needs Node 22+;
// prints an "experimental" warning). Replaces the single-integer cursor: it tracks each sheet row's
// status so rows can be RETRIED (e.g. a claim pasted before its deposit lands) and survive restarts.
//
// status:
//   pending    — ingested, not yet acted on
//   confirmed  — claim landed on-chain (terminal)
//   failed     — permanently rejected: malformed, bad/duplicate proof, or a non-retryable revert (terminal)
//   retry      — not claimable yet (e.g. "No balance lodged" — deposit may still arrive) → retried next run
import { DatabaseSync } from 'node:sqlite';

export function openStore(path) {
  const db = new DatabaseSync(path);
  db.exec(`
    CREATE TABLE IF NOT EXISTS rows (
      row_index  INTEGER PRIMARY KEY,   -- sheet data-row index (0-based; responses append-only => stable)
      calldata   TEXT NOT NULL,
      status     TEXT NOT NULL DEFAULT 'pending',
      attempts   INTEGER NOT NULL DEFAULT 0,
      tx_hash    TEXT,
      block      INTEGER,
      last_error TEXT,
      updated_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
  `);
  const s = {
    off: db.prepare(`SELECT COALESCE(MAX(row_index) + 1, 0) AS off FROM rows`),
    ins: db.prepare(`INSERT OR IGNORE INTO rows (row_index, calldata) VALUES (?, ?)`),
    todo: db.prepare(`SELECT row_index, calldata, attempts FROM rows WHERE status IN ('pending','retry') ORDER BY row_index`),
    set: db.prepare(`UPDATE rows SET status=?, last_error=?, attempts=attempts+1, updated_at=datetime('now') WHERE row_index=?`),
    ok: db.prepare(`UPDATE rows SET status='confirmed', tx_hash=?, block=?, last_error=NULL, attempts=attempts+1, updated_at=datetime('now') WHERE row_index=?`),
    counts: db.prepare(`SELECT status, COUNT(*) AS n FROM rows GROUP BY status`),
  };
  const err = (e) => String(e ?? '').slice(0, 500);
  return {
    // Next sheet offset to read = one past the highest row already ingested.
    ingestOffset: () => s.off.get().off,
    insertPending: (index, calldata) => s.ins.run(index, calldata),
    todo: () => s.todo.all(),
    markRetry: (index, e) => s.set.run('retry', err(e), index),
    markFailed: (index, e) => s.set.run('failed', err(e), index),
    markConfirmed: (index, txHash, block) => s.ok.run(txHash, block, index),
    summary: () => (s.counts.all().map((r) => `${r.status}=${r.n}`).join(' ') || '(empty)'),
    close: () => db.close(),
  };
}
