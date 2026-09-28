// Push and pull.
//
// The merge rule lives on the phone (SyncMerge) and is mirrored here, because
// both ends have to agree: last writer wins by `updated_at`, and a tie leaves
// what's already stored alone. The phone keeps an un-pushed local edit on a tie;
// the server keeps what it has. Both are "the newcomer must be strictly newer",
// read from each side.
//
// Deletes are soft. A row with `deleted_at` set is still pushed, still pulled,
// and still wins or loses on `updated_at` like any other change — otherwise a
// feed deleted on one phone would come back from the other's next push.

import { stamp } from './db.js'

/** Column lists, in the order the DTOs declare them. */
const COLUMNS = {
  babies: ['id', 'name', 'birth_date', 'sex', 'due_date', 'created_by', 'updated_at', 'deleted_at'],
  feeds: ['id', 'baby_id', 'start_time', 'kind', 'amount_ml', 'duration_minutes', 'side', 'note',
    'logged_by', 'logged_by_name', 'updated_at', 'deleted_at'],
  weights: ['id', 'baby_id', 'date', 'grams', 'note', 'logged_by', 'logged_by_name',
    'updated_at', 'deleted_at'],
  care_notes: ['id', 'baby_id', 'date', 'kind', 'note', 'severity', 'resolved_at', 'logged_by',
    'logged_by_name', 'updated_at', 'deleted_at'],
  diapers: ['id', 'baby_id', 'time', 'kind', 'note', 'logged_by', 'logged_by_name',
    'updated_at', 'deleted_at'],
  solid_foods: ['id', 'baby_id', 'time', 'name', 'texture', 'reaction', 'note',
    'logged_by', 'logged_by_name', 'updated_at', 'deleted_at'],
}

const REQUIRED = {
  babies: ['id', 'updated_at'],
  feeds: ['id', 'baby_id', 'start_time', 'kind', 'updated_at'],
  weights: ['id', 'baby_id', 'date', 'grams', 'updated_at'],
  care_notes: ['id', 'baby_id', 'date', 'kind', 'updated_at'],
  diapers: ['id', 'baby_id', 'time', 'kind', 'updated_at'],
  solid_foods: ['id', 'baby_id', 'time', 'name', 'texture', 'updated_at'],
}

/** Mirrors DiaperKind on the phone; anything else is a malformed row. */
const DIAPER_KINDS = new Set(['wet', 'dirty', 'both'])

/** Mirror FoodTexture and FoodReaction on the phone. */
const FOOD_TEXTURES = new Set(['puree', 'mashed', 'fingerFood', 'familyFood'])
const FOOD_REACTIONS = new Set(['loved', 'ate', 'refused', 'possibleReaction'])

const UUID_RE = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/

export class RowError extends Error {}

function normalizeUUID(value, field) {
  const text = String(value ?? '')
  if (!UUID_RE.test(text)) throw new RowError(`${field} must be a UUID`)
  return text.toUpperCase()
}

function normalizeDate(value, field, { required = false } = {}) {
  if (value === null || value === undefined || value === '') {
    if (required) throw new RowError(`${field} is required`)
    return null
  }
  const date = new Date(value)
  if (Number.isNaN(date.getTime())) throw new RowError(`${field} is not a date`)
  return date.toISOString()
}

function normalizeText(value, field, max = 4000) {
  if (value === null || value === undefined) return null
  const text = String(value)
  if (text.length > max) throw new RowError(`${field} is too long`)
  return text
}

function normalizeNumber(value, field, { min, max, integer = false } = {}) {
  if (value === null || value === undefined || value === '') return null
  const num = Number(value)
  if (!Number.isFinite(num)) throw new RowError(`${field} is not a number`)
  if (integer && !Number.isInteger(num)) throw new RowError(`${field} must be a whole number`)
  if (min !== undefined && num < min) throw new RowError(`${field} is below ${min}`)
  if (max !== undefined && num > max) throw new RowError(`${field} is above ${max}`)
  return num
}

/**
 * Turns one JSON row from a phone into the values that go in the table.
 *
 * Everything is checked. The phones are the only clients today, but this is a
 * public endpoint and a row that arrives malformed should be refused here
 * rather than stored and handed to the other caregiver's app to crash on.
 */
export function normalizeRow(table, raw, { userID }) {
  if (!raw || typeof raw !== 'object') throw new RowError('row is not an object')
  for (const field of REQUIRED[table]) {
    if (raw[field] === null || raw[field] === undefined || raw[field] === '') {
      throw new RowError(`${field} is required`)
    }
  }
  const row = {
    id: normalizeUUID(raw.id, 'id'),
    updated_at: normalizeDate(raw.updated_at, 'updated_at', { required: true }),
    deleted_at: normalizeDate(raw.deleted_at, 'deleted_at'),
  }

  if (table === 'babies') {
    row.name = normalizeText(raw.name, 'name', 200) ?? ''
    row.birth_date = normalizeDate(raw.birth_date, 'birth_date')
    row.sex = normalizeText(raw.sex, 'sex', 20)
    row.due_date = normalizeDate(raw.due_date, 'due_date')
    row.created_by = raw.created_by ? normalizeUUID(raw.created_by, 'created_by') : userID
    return row
  }

  row.baby_id = normalizeUUID(raw.baby_id, 'baby_id')
  row.logged_by = raw.logged_by ? normalizeUUID(raw.logged_by, 'logged_by') : userID
  row.logged_by_name = normalizeText(raw.logged_by_name, 'logged_by_name', 200) ?? ''

  if (table === 'feeds') {
    row.start_time = normalizeDate(raw.start_time, 'start_time', { required: true })
    row.kind = normalizeText(raw.kind, 'kind', 40)
    // 4 litres is far past any real bottle; it catches a unit mix-up, not a big feed.
    row.amount_ml = normalizeNumber(raw.amount_ml, 'amount_ml', { min: 0, max: 4000 })
    row.duration_minutes = normalizeNumber(raw.duration_minutes, 'duration_minutes',
      { min: 0, max: 600, integer: true })
    row.side = normalizeText(raw.side, 'side', 40)
    row.note = normalizeText(raw.note, 'note') ?? ''
  } else if (table === 'weights') {
    row.date = normalizeDate(raw.date, 'date', { required: true })
    row.grams = normalizeNumber(raw.grams, 'grams', { min: 0, max: 60000 })
    row.note = normalizeText(raw.note, 'note') ?? ''
  } else if (table === 'care_notes') {
    row.date = normalizeDate(raw.date, 'date', { required: true })
    row.kind = normalizeText(raw.kind, 'kind', 40)
    row.note = normalizeText(raw.note, 'note') ?? ''
    row.severity = normalizeNumber(raw.severity, 'severity', { min: 1, max: 3, integer: true })
    row.resolved_at = normalizeDate(raw.resolved_at, 'resolved_at')
  } else if (table === 'diapers') {
    row.time = normalizeDate(raw.time, 'time', { required: true })
    row.kind = normalizeText(raw.kind, 'kind', 40)
    if (!DIAPER_KINDS.has(row.kind)) throw new RowError('kind must be wet, dirty or both')
    row.note = normalizeText(raw.note, 'note') ?? ''
  } else if (table === 'solid_foods') {
    row.time = normalizeDate(raw.time, 'time', { required: true })
    row.name = normalizeText(raw.name, 'name', 200)
    if (!row.name || !row.name.trim()) throw new RowError('name is required')
    row.texture = normalizeText(raw.texture, 'texture', 40)
    if (!FOOD_TEXTURES.has(row.texture)) throw new RowError('texture is not one the app produces')
    row.reaction = normalizeText(raw.reaction, 'reaction', 40) ?? 'ate'
    if (!FOOD_REACTIONS.has(row.reaction)) throw new RowError('reaction is not one the app produces')
    row.note = normalizeText(raw.note, 'note') ?? ''
  }
  return row
}

/** Mirror of SyncMerge.remoteWins, read from the server's side of the wire. */
export function incomingWins(incomingUpdatedAt, storedUpdatedAt) {
  if (!storedUpdatedAt) return true
  return new Date(incomingUpdatedAt).getTime() > new Date(storedUpdatedAt).getTime()
}

function recordChange(db, { babyID, table, rowID, userID, actorName, kind, at }) {
  db.prepare(`INSERT INTO changes (baby_id, table_name, row_id, user_id, actor_name, kind, at, server_ms)
              VALUES (?, ?, ?, ?, ?, ?, ?, ?)`)
    .run(babyID, table, rowID, userID, actorName ?? '', kind, at.iso, at.ms)
}

/**
 * Writes one row and returns its watermark.
 *
 * `server_ms` is only bumped when the row actually changed. A phone that pushes
 * the same unchanged row again — which happens, because `needsUpload` is
 * cleared on the response and a dropped response means a retry — doesn't drag
 * every other phone into re-pulling it.
 */
export function upsertRow(db, table, row, { userID, actorName }) {
  const stored = db.prepare(`SELECT updated_at, server_updated_at, server_ms FROM ${table} WHERE id = ?`)
    .get(row.id)

  if (stored && !incomingWins(row.updated_at, stored.updated_at)) {
    return { status: 'kept', server_updated_at: stored.server_updated_at }
  }

  const at = stamp()
  const columns = COLUMNS[table]
  const values = columns.map((c) => (row[c] === undefined ? null : row[c]))
  const placeholders = columns.map(() => '?').join(', ')
  db.prepare(
    `INSERT INTO ${table} (${columns.join(', ')}, server_updated_at, server_ms)
     VALUES (${placeholders}, ?, ?)
     ON CONFLICT(id) DO UPDATE SET ${columns.filter((c) => c !== 'id').map((c) => `${c} = excluded.${c}`).join(', ')},
       server_updated_at = excluded.server_updated_at, server_ms = excluded.server_ms`
  ).run(...values, at.iso, at.ms)

  recordChange(db, {
    babyID: table === 'babies' ? row.id : row.baby_id,
    table,
    rowID: row.id,
    userID,
    actorName,
    kind: row.deleted_at ? 'delete' : stored ? 'update' : 'insert',
    at,
  })

  return { status: stored ? 'updated' : 'inserted', server_updated_at: at.iso }
}

/** Rows a baby's log has gained or changed since a watermark. */
export function rowsSince(db, table, babyID, sinceMs, limit) {
  const where = table === 'babies' ? 'id = ?' : 'baby_id = ?'
  return db.prepare(
    `SELECT ${COLUMNS[table].join(', ')}, server_updated_at
     FROM ${table} WHERE ${where} AND server_ms > ?
     ORDER BY server_ms ASC LIMIT ?`
  ).all(babyID, sinceMs, limit)
}

export { COLUMNS }
