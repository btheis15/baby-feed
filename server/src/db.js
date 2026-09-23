// The database. SQLite, one file, no server process of its own.
//
// WHY SQLITE AND NOT POSTGRES: PLAN.md said Postgres because the DTOs are
// snake_case and were shaped for one. The column names still are — but the
// workload here is two phones and a few thousand rows, and a second daemon to
// keep alive across reboots buys nothing for that. A single file is also the
// only backup story that can't be got wrong: copy the file.
//
// node:sqlite is built into Node 22.5+, so this server has no dependencies at
// all. Nothing to `npm install`, nothing to go stale, nothing to audit.

import { DatabaseSync } from 'node:sqlite'
import { mkdirSync } from 'node:fs'
import { dirname } from 'node:path'

/** Every synced table, and the DTO field order the API speaks. */
export const ROW_TABLES = ['babies', 'feeds', 'weights', 'care_notes', 'diapers']

const SCHEMA = `
PRAGMA journal_mode = WAL;
PRAGMA foreign_keys = ON;
PRAGMA busy_timeout = 5000;

-- A caregiver. There is no email and no password: a user exists because a
-- device was paired, either with the setup secret or with an invite code.
CREATE TABLE IF NOT EXISTS users (
  id            TEXT PRIMARY KEY,
  display_name  TEXT NOT NULL DEFAULT '',
  created_at    TEXT NOT NULL
);

-- One per baby: the last way back in when every phone that had the log is
-- gone. The phone generates the key and keeps it; the server is told only its
-- hash, so a stolen database file yields no way into anything — the same
-- reasoning as device tokens, and the reason the key can be shown on a phone
-- but never re-sent by the server.
CREATE TABLE IF NOT EXISTS recovery_keys (
  baby_id       TEXT PRIMARY KEY REFERENCES babies(id),
  key_hash      TEXT NOT NULL UNIQUE,
  created_at    TEXT NOT NULL,
  last_used_at  TEXT
);
CREATE INDEX IF NOT EXISTS recovery_keys_hash ON recovery_keys(key_hash);

-- One row per phone. Tokens are stored hashed, so a stolen database file
-- can't be replayed against a running server.
CREATE TABLE IF NOT EXISTS devices (
  id            TEXT PRIMARY KEY,
  user_id       TEXT NOT NULL REFERENCES users(id),
  token_hash    TEXT NOT NULL UNIQUE,
  name          TEXT NOT NULL DEFAULT '',
  created_at    TEXT NOT NULL,
  last_seen_at  TEXT,
  revoked_at    TEXT
);
CREATE INDEX IF NOT EXISTS devices_user ON devices(user_id);

-- The synced rows. Column names match SyncDTOs exactly, so the JSON the phone
-- sends maps straight onto a row with no translation layer.
--
-- server_ms is the pull watermark: milliseconds, assigned by the server, and
-- strictly increasing (see stamp() below). The phone's updated_at decides
-- conflicts; server_ms only decides what a pull has already seen. Keeping the
-- two apart is what makes a phone with a wrong clock unable to hide rows from
-- another phone's pull.
CREATE TABLE IF NOT EXISTS babies (
  id            TEXT PRIMARY KEY,
  name          TEXT NOT NULL DEFAULT '',
  birth_date    TEXT,
  sex           TEXT,
  due_date      TEXT,
  created_by    TEXT NOT NULL,
  updated_at    TEXT NOT NULL,
  deleted_at    TEXT,
  server_updated_at TEXT NOT NULL,
  server_ms     INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS babies_ms ON babies(server_ms);

CREATE TABLE IF NOT EXISTS members (
  baby_id       TEXT NOT NULL REFERENCES babies(id),
  user_id       TEXT NOT NULL REFERENCES users(id),
  role          TEXT NOT NULL DEFAULT 'caregiver',
  display_name  TEXT NOT NULL DEFAULT '',
  joined_at     TEXT NOT NULL,
  server_ms     INTEGER NOT NULL,
  PRIMARY KEY (baby_id, user_id)
);
CREATE INDEX IF NOT EXISTS members_user ON members(user_id);

CREATE TABLE IF NOT EXISTS feeds (
  id            TEXT PRIMARY KEY,
  baby_id       TEXT NOT NULL,
  start_time    TEXT NOT NULL,
  kind          TEXT NOT NULL,
  amount_ml     REAL,
  duration_minutes INTEGER,
  side          TEXT,
  note          TEXT NOT NULL DEFAULT '',
  logged_by     TEXT,
  logged_by_name TEXT NOT NULL DEFAULT '',
  updated_at    TEXT NOT NULL,
  deleted_at    TEXT,
  server_updated_at TEXT NOT NULL,
  server_ms     INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS feeds_pull ON feeds(baby_id, server_ms);

CREATE TABLE IF NOT EXISTS weights (
  id            TEXT PRIMARY KEY,
  baby_id       TEXT NOT NULL,
  date          TEXT NOT NULL,
  grams         REAL NOT NULL,
  note          TEXT NOT NULL DEFAULT '',
  logged_by     TEXT,
  logged_by_name TEXT NOT NULL DEFAULT '',
  updated_at    TEXT NOT NULL,
  deleted_at    TEXT,
  server_updated_at TEXT NOT NULL,
  server_ms     INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS weights_pull ON weights(baby_id, server_ms);

CREATE TABLE IF NOT EXISTS care_notes (
  id            TEXT PRIMARY KEY,
  baby_id       TEXT NOT NULL,
  date          TEXT NOT NULL,
  kind          TEXT NOT NULL,
  note          TEXT NOT NULL DEFAULT '',
  severity      INTEGER,
  resolved_at   TEXT,
  logged_by     TEXT,
  logged_by_name TEXT NOT NULL DEFAULT '',
  updated_at    TEXT NOT NULL,
  deleted_at    TEXT,
  server_updated_at TEXT NOT NULL,
  server_ms     INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS care_notes_pull ON care_notes(baby_id, server_ms);

CREATE TABLE IF NOT EXISTS diapers (
  id            TEXT PRIMARY KEY,
  baby_id       TEXT NOT NULL,
  time          TEXT NOT NULL,
  kind          TEXT NOT NULL,
  note          TEXT NOT NULL DEFAULT '',
  logged_by     TEXT,
  logged_by_name TEXT NOT NULL DEFAULT '',
  updated_at    TEXT NOT NULL,
  deleted_at    TEXT,
  server_updated_at TEXT NOT NULL,
  server_ms     INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS diapers_pull ON diapers(baby_id, server_ms);

-- Invite codes. Six characters, matching SyncMerge.inviteCodeLength, so the
-- normalising and validation the app already ships against are the rules here.
CREATE TABLE IF NOT EXISTS invites (
  code          TEXT PRIMARY KEY,
  baby_id       TEXT NOT NULL REFERENCES babies(id),
  created_by    TEXT NOT NULL REFERENCES users(id),
  created_at    TEXT NOT NULL,
  expires_at    TEXT NOT NULL,
  max_uses      INTEGER NOT NULL DEFAULT 1,
  uses          INTEGER NOT NULL DEFAULT 0,
  revoked_at    TEXT
);
CREATE INDEX IF NOT EXISTS invites_baby ON invites(baby_id);

-- Who changed what, so the other caregiver's phone can be told "Annette logged
-- a feed" without diffing the whole log. Nothing pushes from this yet; the
-- feed is here so the notification work is a client change, not a schema one.
CREATE TABLE IF NOT EXISTS changes (
  seq           INTEGER PRIMARY KEY AUTOINCREMENT,
  baby_id       TEXT NOT NULL,
  table_name    TEXT NOT NULL,
  row_id        TEXT NOT NULL,
  user_id       TEXT,
  actor_name    TEXT NOT NULL DEFAULT '',
  kind          TEXT NOT NULL DEFAULT 'upsert',
  at            TEXT NOT NULL,
  server_ms     INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS changes_pull ON changes(baby_id, seq);
`

export function openDatabase(path) {
  mkdirSync(dirname(path), { recursive: true })
  const db = new DatabaseSync(path)
  db.exec(SCHEMA)
  return db
}

// A server timestamp that never repeats and never goes backwards.
//
// Two phones pushing in the same millisecond would otherwise get the same
// watermark, and a pull asking for "> that" would skip whichever row landed
// second — a feed silently missing from the other phone, which is exactly the
// failure this app can't have. Bumping by a millisecond costs nothing.
let lastMs = 0
export function stamp() {
  const now = Date.now()
  lastMs = now > lastMs ? now : lastMs + 1
  return { ms: lastMs, iso: new Date(lastMs).toISOString() }
}

/** Restores the monotonic counter after a restart. */
export function primeStamp(db) {
  let high = 0
  for (const table of [...ROW_TABLES, 'members', 'changes']) {
    const row = db.prepare(`SELECT MAX(server_ms) AS m FROM ${table}`).get()
    if (row?.m > high) high = row.m
  }
  lastMs = Math.max(lastMs, high)
  return high
}
