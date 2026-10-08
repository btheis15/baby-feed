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
import { randomUUID } from 'node:crypto'

/** Every synced table, and the DTO field order the API speaks. */
export const ROW_TABLES = ['babies', 'feeds', 'weights', 'care_notes', 'diapers', 'solid_foods',
  'concerns', 'medications', 'medication_doses', 'doctor_visits']

/**
 * The database's layout version, in PRAGMA user_version. New tables need no
 * migration (CREATE TABLE IF NOT EXISTS makes them); a column added to a
 * table that already exists does, and goes in COLUMN_ADDITIONS below.
 */
export const SCHEMA_VERSION = 3

/**
 * Columns added to existing tables, oldest first. Append only: an entry is
 * applied once to any database that lacks the column, and never edited.
 */
export const COLUMN_ADDITIONS = [
  ['care_notes', 'concern_id', 'TEXT'],
  // Babies added by newer builds are end-to-end encrypted ("sealed"): the
  // server keeps only ids and timestamps for them, and their rows live in
  // sealed_rows. Babies from before stay as they are, readable, forever.
  ['babies', 'sealed', 'INTEGER NOT NULL DEFAULT 0'],
  // A sealed baby's caregiver names, encrypted with that baby's key.
  ['members', 'sealed_name', 'TEXT'],
]

const SCHEMA = `
PRAGMA journal_mode = WAL;
PRAGMA foreign_keys = ON;
PRAGMA busy_timeout = 5000;

-- Facts about this server itself. server_id is random per database, so a phone
-- can tell "the server was reset" (a new id) from "my token was revoked" (the
-- same id, and a 401).
CREATE TABLE IF NOT EXISTS meta (
  key           TEXT PRIMARY KEY,
  value         TEXT NOT NULL
);

-- A caregiver. There is no email and no password: a user exists because a
-- device was paired — enrolled from the home network, invited, recovered, or
-- (on older builds) claimed with the setup secret.
CREATE TABLE IF NOT EXISTS users (
  id            TEXT PRIMARY KEY,
  display_name  TEXT NOT NULL DEFAULT '',
  created_at    TEXT NOT NULL
);

-- One recovery phrase per person, covering every log they're on — owned or
-- shared with them. Like the per-baby keys below, the phone makes the phrase
-- and keeps it; the server is told only its hash.
CREATE TABLE IF NOT EXISTS account_keys (
  user_id       TEXT PRIMARY KEY REFERENCES users(id),
  key_hash      TEXT NOT NULL UNIQUE,
  created_at    TEXT NOT NULL,
  last_used_at  TEXT
);

-- One per baby: the older way back in when every phone that had the log is
-- gone, kept because builds from before personal phrases hold these. The
-- phone generates the key and keeps it; the server is told only its
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

CREATE TABLE IF NOT EXISTS solid_foods (
  id            TEXT PRIMARY KEY,
  baby_id       TEXT NOT NULL,
  time          TEXT NOT NULL,
  name          TEXT NOT NULL,
  texture       TEXT NOT NULL,
  reaction      TEXT NOT NULL DEFAULT 'ate',
  note          TEXT NOT NULL DEFAULT '',
  logged_by     TEXT,
  logged_by_name TEXT NOT NULL DEFAULT '',
  updated_at    TEXT NOT NULL,
  deleted_at    TEXT,
  server_updated_at TEXT NOT NULL,
  server_ms     INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS solid_foods_pull ON solid_foods(baby_id, server_ms);

-- A health concern: an episode with a start and, once it's over, an end —
-- "Red left eye", started Sep 16. Notes about it link to it by concern_id.
CREATE TABLE IF NOT EXISTS concerns (
  id            TEXT PRIMARY KEY,
  baby_id       TEXT NOT NULL,
  title         TEXT NOT NULL,
  kind          TEXT NOT NULL,
  started_at    TEXT NOT NULL,
  resolved_at   TEXT,
  severity      INTEGER,
  note          TEXT NOT NULL DEFAULT '',
  outcome       TEXT NOT NULL DEFAULT '',
  logged_by     TEXT,
  logged_by_name TEXT NOT NULL DEFAULT '',
  updated_at    TEXT NOT NULL,
  deleted_at    TEXT,
  server_updated_at TEXT NOT NULL,
  server_ms     INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS concerns_pull ON concerns(baby_id, server_ms);

-- A medicine or supplement, as the label or the doctor gives it. Every number
-- here was typed by a parent; the app never suggests one.
CREATE TABLE IF NOT EXISTS medications (
  id            TEXT PRIMARY KEY,
  baby_id       TEXT NOT NULL,
  name          TEXT NOT NULL,
  kind          TEXT NOT NULL DEFAULT 'medicine',
  dose_amount   REAL,
  dose_unit     TEXT NOT NULL DEFAULT 'ml',
  schedule      TEXT NOT NULL DEFAULT 'asNeeded',
  times_per_day INTEGER,
  interval_hours REAL,
  min_hours_between REAL,
  max_doses_per_24h INTEGER,
  start_date    TEXT NOT NULL,
  end_date      TEXT,
  instructions  TEXT NOT NULL DEFAULT '',
  logged_by     TEXT,
  logged_by_name TEXT NOT NULL DEFAULT '',
  updated_at    TEXT NOT NULL,
  deleted_at    TEXT,
  server_updated_at TEXT NOT NULL,
  server_ms     INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS medications_pull ON medications(baby_id, server_ms);

-- One dose given. The medicine's name is copied onto it, so it still reads
-- right after a rename or once the medicine itself is deleted.
CREATE TABLE IF NOT EXISTS medication_doses (
  id            TEXT PRIMARY KEY,
  baby_id       TEXT NOT NULL,
  medication_id TEXT,
  medication_name TEXT NOT NULL,
  time          TEXT NOT NULL,
  amount        REAL,
  unit          TEXT,
  note          TEXT NOT NULL DEFAULT '',
  logged_by     TEXT,
  logged_by_name TEXT NOT NULL DEFAULT '',
  updated_at    TEXT NOT NULL,
  deleted_at    TEXT,
  server_updated_at TEXT NOT NULL,
  server_ms     INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS medication_doses_pull ON medication_doses(baby_id, server_ms);

-- A visit to the doctor, and what they said.
CREATE TABLE IF NOT EXISTS doctor_visits (
  id            TEXT PRIMARY KEY,
  baby_id       TEXT NOT NULL,
  date          TEXT NOT NULL,
  kind          TEXT NOT NULL DEFAULT 'checkup',
  provider      TEXT NOT NULL DEFAULT '',
  reason        TEXT NOT NULL DEFAULT '',
  doctor_notes  TEXT NOT NULL DEFAULT '',
  follow_up_date TEXT,
  follow_up_note TEXT NOT NULL DEFAULT '',
  vaccines      TEXT NOT NULL DEFAULT '',
  weight_entry_id TEXT,
  logged_by     TEXT,
  logged_by_name TEXT NOT NULL DEFAULT '',
  updated_at    TEXT NOT NULL,
  deleted_at    TEXT,
  server_updated_at TEXT NOT NULL,
  server_ms     INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS doctor_visits_pull ON doctor_visits(baby_id, server_ms);

-- Every row of a sealed (end-to-end encrypted) baby, whatever kind it is.
--
-- The phone encrypts the whole row with the baby's key before it leaves, kind
-- and deletion included, so all this server can tell about one is which baby
-- it belongs to and when it last changed. updated_at is the phone's clock and
-- decides conflicts exactly as for the readable tables; server_ms is the pull
-- watermark. Nothing here can be read without a key the server never has.
CREATE TABLE IF NOT EXISTS sealed_rows (
  id            TEXT PRIMARY KEY,
  baby_id       TEXT NOT NULL,
  sealed        TEXT NOT NULL,
  logged_by     TEXT,
  updated_at    TEXT NOT NULL,
  server_updated_at TEXT NOT NULL,
  server_ms     INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS sealed_rows_pull ON sealed_rows(baby_id, server_ms);

-- A sealed baby's key, once per caregiver who has a recovery phrase, locked
-- with a key made from that phrase on the phone. Restoring with the phrase
-- unlocks it again; the server can do neither.
CREATE TABLE IF NOT EXISTS baby_keys (
  baby_id       TEXT NOT NULL,
  user_id       TEXT NOT NULL,
  wrapped       TEXT NOT NULL,
  updated_at    TEXT NOT NULL,
  PRIMARY KEY (baby_id, user_id)
);

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
  migrate(db)
  return db
}

/**
 * Brings an existing database up to SCHEMA_VERSION: adds any column in
 * COLUMN_ADDITIONS that a table lacks, then records the version. One
 * transaction, and safe to run on every open.
 */
export function migrate(db) {
  db.exec('BEGIN IMMEDIATE')
  try {
    for (const [table, column, type] of COLUMN_ADDITIONS) {
      const has = db.prepare(`PRAGMA table_info(${table})`).all().some((c) => c.name === column)
      if (!has) db.exec(`ALTER TABLE ${table} ADD COLUMN ${column} ${type}`)
    }
    db.exec(`PRAGMA user_version = ${SCHEMA_VERSION}`)
    db.exec('COMMIT')
  } catch (error) {
    db.exec('ROLLBACK')
    throw error
  }
}

/** The layout version this database is at. */
export function schemaVersion(db) {
  return db.prepare('PRAGMA user_version').get().user_version
}

/** This database's id, made on first use and never changed after. */
export function serverID(db) {
  db.prepare("INSERT OR IGNORE INTO meta (key, value) VALUES ('server_id', ?)")
    .run(randomUUID().toUpperCase())
  return db.prepare("SELECT value FROM meta WHERE key = 'server_id'").get().value
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
  for (const table of [...ROW_TABLES, 'members', 'changes', 'sealed_rows']) {
    const row = db.prepare(`SELECT MAX(server_ms) AS m FROM ${table}`).get()
    if (row?.m > high) high = row.m
  }
  lastMs = Math.max(lastMs, high)
  return high
}
