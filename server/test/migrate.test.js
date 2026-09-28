// A column added to a table that phones already sync, on a database that
// already has rows: the one kind of schema change CREATE TABLE IF NOT EXISTS
// can't make.

import test from 'node:test'
import assert from 'node:assert/strict'
import { mkdtempSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { DatabaseSync } from 'node:sqlite'
import { openDatabase, schemaVersion, SCHEMA_VERSION } from '../src/db.js'

function tempPath() {
  const dir = mkdtempSync(join(tmpdir(), 'babyfeed-migrate-'))
  return { dir, path: join(dir, 'test.db') }
}

const columns = (db, table) => db.prepare(`PRAGMA table_info(${table})`).all().map((c) => c.name)

test('a fresh database has every column and the current version', () => {
  const { dir, path } = tempPath()
  try {
    const db = openDatabase(path)
    assert.ok(columns(db, 'care_notes').includes('concern_id'))
    assert.equal(schemaVersion(db), SCHEMA_VERSION)
    db.close()
  } finally {
    rmSync(dir, { recursive: true, force: true })
  }
})

test('a database from before concerns gains the column and keeps its notes', () => {
  const { dir, path } = tempPath()
  try {
    // The care_notes table exactly as the previous server made it.
    const old = new DatabaseSync(path)
    old.exec(`CREATE TABLE care_notes (
      id TEXT PRIMARY KEY, baby_id TEXT NOT NULL, date TEXT NOT NULL, kind TEXT NOT NULL,
      note TEXT NOT NULL DEFAULT '', severity INTEGER, resolved_at TEXT, logged_by TEXT,
      logged_by_name TEXT NOT NULL DEFAULT '', updated_at TEXT NOT NULL, deleted_at TEXT,
      server_updated_at TEXT NOT NULL, server_ms INTEGER NOT NULL)`)
    old.prepare(`INSERT INTO care_notes (id, baby_id, date, kind, note, updated_at, server_updated_at, server_ms)
                 VALUES ('N1', 'B1', '2026-09-01T00:00:00.000Z', 'rash', 'red cheeks',
                         '2026-09-01T00:00:00.000Z', '2026-09-01T00:00:00.000Z', 1)`).run()
    old.close()

    const db = openDatabase(path)
    assert.ok(columns(db, 'care_notes').includes('concern_id'))
    const note = db.prepare("SELECT note, concern_id FROM care_notes WHERE id = 'N1'").get()
    assert.equal(note.note, 'red cheeks')
    assert.equal(note.concern_id, null)
    assert.equal(schemaVersion(db), SCHEMA_VERSION)
    db.close()
  } finally {
    rmSync(dir, { recursive: true, force: true })
  }
})

test('opening again changes nothing', () => {
  const { dir, path } = tempPath()
  try {
    openDatabase(path).close()
    const db = openDatabase(path)
    const concernColumns = columns(db, 'care_notes').filter((name) => name === 'concern_id')
    assert.equal(concernColumns.length, 1)
    assert.equal(schemaVersion(db), SCHEMA_VERSION)
    db.close()
  } finally {
    rmSync(dir, { recursive: true, force: true })
  }
})
