// Durable per-row state for the relayer, backed by SQLite (node:sqlite — built-in, needs Node 22+;
// prints an "experimental" warning). Rows are keyed by `row_hash` = sha256(submitted_at + calldata),
// i.e. the identity of a Form SUBMISSION, not just the proof bytes. This matters because the escrow has
// no per-proof nonce — a proof stays claimable whenever balances[src] > 0 — so the SAME proof pasted
// again after a fresh lodge() is a legitimately new claim and must be tracked as its own row. (An
// accidental same-second re-paste of identical bytes still collapses, which is fine.) Position-free, so
// deleting / reordering / pruning sheet rows, or pointing at a fresh sheet, is safe.
//
// status:
//   pending    — ingested, not yet acted on
//   confirmed  — claim landed on-chain (terminal)
//   failed     — permanently rejected: malformed, bad proof, or a non-retryable revert (terminal)
//   retry      — not claimable yet (e.g. "No balance lodged" — a deposit may still arrive) → retried next run
import { DatabaseSync } from 'node:sqlite';

export function openStore(path) {
  const db = new DatabaseSync(path);
  db.exec(`
    CREATE TABLE IF NOT EXISTS sheet_rows (
      row_hash     TEXT PRIMARY KEY,    -- sha256(submitted_at + calldata): identity of a Form submission
      calldata     TEXT NOT NULL,
      submitted_at TEXT,                -- Form timestamp, normalized to 'YYYY-MM-DD HH:MM:SS' (sheet timezone)
      status       TEXT NOT NULL DEFAULT 'pending',
      attempts     INTEGER NOT NULL DEFAULT 0,
      tx_hash      TEXT,                -- set on 'confirmed', or on a submitted tx that reverted on-chain
      block        INTEGER,
      last_error   TEXT,
      updated_at   TEXT NOT NULL DEFAULT (datetime('now'))
    );
    CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT);
  `);
  const s = {
    ins: db.prepare(`INSERT OR IGNORE INTO sheet_rows (row_hash, calldata, submitted_at) VALUES (?, ?, ?)`),
    todo: db.prepare(`SELECT row_hash, calldata, submitted_at, attempts FROM sheet_rows WHERE status IN ('pending','retry') ORDER BY submitted_at`),
    set: db.prepare(`UPDATE sheet_rows SET status=?, last_error=?, attempts=attempts+1, updated_at=datetime('now') WHERE row_hash=?`),
    fail: db.prepare(`UPDATE sheet_rows SET status='failed', last_error=?, tx_hash=?, block=?, attempts=attempts+1, updated_at=datetime('now') WHERE row_hash=?`),
    ok: db.prepare(`UPDATE sheet_rows SET status='confirmed', tx_hash=?, block=?, last_error=NULL, attempts=attempts+1, updated_at=datetime('now') WHERE row_hash=?`),
    counts: db.prepare(`SELECT status, COUNT(*) AS n FROM sheet_rows GROUP BY status`),
    getMeta: db.prepare(`SELECT value FROM meta WHERE key=?`),
    setMeta: db.prepare(`INSERT OR REPLACE INTO meta (key, value) VALUES (?, ?)`),
  };
  const err = (e) => String(e ?? '').slice(0, 500);
  return {
    // INSERT OR IGNORE by submission hash → the same submission (timestamp + calldata) is inserted once.
    insertPending: (rowHash, calldata, submittedAt) => s.ins.run(rowHash, calldata, submittedAt ?? null),
    todo: () => s.todo.all(),
    markRetry: (rowHash, e) => s.set.run('retry', err(e), rowHash),
    // txHash/block are recorded only for an on-chain failure (a submitted tx that reverted); a
    // simulation failure passes neither, so tx_hash/block stay NULL — that's how you tell them apart.
    markFailed: (rowHash, e, txHash = null, block = null) => s.fail.run(err(e), txHash ?? null, block ?? null, rowHash),
    markConfirmed: (rowHash, txHash, block) => s.ok.run(txHash, block, rowHash),
    getWatermark: () => s.getMeta.get('watermark')?.value ?? null,
    setWatermark: (ts) => s.setMeta.run('watermark', ts),
    summary: () => (s.counts.all().map((r) => `${r.status}=${r.n}`).join(' ') || '(empty)'),
    close: () => db.close(),
  };
}
