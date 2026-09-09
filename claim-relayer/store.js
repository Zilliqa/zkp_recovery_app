// Durable per-row state for the relayer, backed by SQLite (node:sqlite — built-in, needs Node 22+;
// prints an "experimental" warning). Rows are keyed by a hash of the CALLDATA (content), NOT by sheet
// position — so deleting / reordering / pruning sheet rows, or pointing at a fresh sheet, is safe: each
// claim is deduped by content and processed once, regardless of where (or whether) it sits in the sheet.
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
    CREATE TABLE IF NOT EXISTS sheet_rows (
      calldata_hash TEXT PRIMARY KEY,   -- sha256(lowercased calldata): the content key; dedups duplicates
      calldata      TEXT NOT NULL,
      row_index     INTEGER,            -- sheet data-row index at first ingest (reference only; NOT stable if rows are deleted)
      submitted_at  TEXT,               -- the Form's timestamp (column A), as shown in the sheet
      status        TEXT NOT NULL DEFAULT 'pending',
      attempts      INTEGER NOT NULL DEFAULT 0,
      tx_hash       TEXT,
      block         INTEGER,
      last_error    TEXT,
      updated_at    TEXT NOT NULL DEFAULT (datetime('now'))
    );
  `);
  const s = {
    ins: db.prepare(`INSERT OR IGNORE INTO sheet_rows (calldata_hash, calldata, row_index, submitted_at) VALUES (?, ?, ?, ?)`),
    todo: db.prepare(`SELECT calldata_hash, calldata, row_index, attempts FROM sheet_rows WHERE status IN ('pending','retry') ORDER BY row_index`),
    set: db.prepare(`UPDATE sheet_rows SET status=?, last_error=?, attempts=attempts+1, updated_at=datetime('now') WHERE calldata_hash=?`),
    ok: db.prepare(`UPDATE sheet_rows SET status='confirmed', tx_hash=?, block=?, last_error=NULL, attempts=attempts+1, updated_at=datetime('now') WHERE calldata_hash=?`),
    counts: db.prepare(`SELECT status, COUNT(*) AS n FROM sheet_rows GROUP BY status`),
  };
  const err = (e) => String(e ?? '').slice(0, 500);
  return {
    // INSERT OR IGNORE by content hash → a calldata already seen (any status) is skipped.
    insertPending: (hash, calldata, rowIndex, submittedAt) => s.ins.run(hash, calldata, rowIndex ?? null, submittedAt ?? null),
    todo: () => s.todo.all(),
    markRetry: (hash, e) => s.set.run('retry', err(e), hash),
    markFailed: (hash, e) => s.set.run('failed', err(e), hash),
    markConfirmed: (hash, txHash, block) => s.ok.run(txHash, block, hash),
    summary: () => (s.counts.all().map((r) => `${r.status}=${r.n}`).join(' ') || '(empty)'),
    close: () => db.close(),
  };
}
