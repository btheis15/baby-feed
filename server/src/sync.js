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
  care_notes: ['id', 'baby_id', 'date', 'kind', 'note', 'severity', 'resolved_at', 'concern_id',
    'logged_by', 'logged_by_name', 'updated_at', 'deleted_at'],
  diapers: ['id', 'baby_id', 'time', 'kind', 'note', 'logged_by', 'logged_by_name',
    'updated_at', 'deleted_at'],
  solid_foods: ['id', 'baby_id', 'time', 'name', 'texture', 'reaction', 'note',
    'logged_by', 'logged_by_name', 'updated_at', 'deleted_at'],
  concerns: ['id', 'baby_id', 'title', 'kind', 'started_at', 'resolved_at', 'severity', 'note', 'outcome',
    'logged_by', 'logged_by_name', 'updated_at', 'deleted_at'],
  medications: ['id', 'baby_id', 'name', 'kind', 'dose_amount', 'dose_unit', 'schedule', 'times_per_day',
    'interval_hours', 'min_hours_between', 'max_doses_per_24h', 'start_date', 'end_date', 'instructions',
    'logged_by', 'logged_by_name', 'updated_at', 'deleted_at'],
  medication_doses: ['id', 'baby_id', 'medication_id', 'medication_name', 'time', 'amount', 'unit', 'note',
    'logged_by', 'logged_by_name', 'updated_at', 'deleted_at'],
  doctor_visits: ['id', 'baby_id', 'date', 'kind', 'provider', 'reason', 'doctor_notes', 'follow_up_date',
    'follow_up_note', 'vaccines', 'weight_entry_id', 'logged_by', 'logged_by_name', 'updated_at', 'deleted_at'],
}

/**
 * Columns added to a table after phones already synced it. An older app
 * doesn't send them, and writing every column on conflict would null what a
 * newer app stored; so these are written only when the row carries the key.
 */
export const LATE_COLUMNS = {
  care_notes: ['concern_id'],
}

const REQUIRED = {
  babies: ['id', 'updated_at'],
  feeds: ['id', 'baby_id', 'start_time', 'kind', 'updated_at'],
  weights: ['id', 'baby_id', 'date', 'grams', 'updated_at'],
  care_notes: ['id', 'baby_id', 'date', 'kind', 'updated_at'],
  diapers: ['id', 'baby_id', 'time', 'kind', 'updated_at'],
  solid_foods: ['id', 'baby_id', 'time', 'name', 'texture', 'updated_at'],
  concerns: ['id', 'baby_id', 'title', 'kind', 'started_at', 'updated_at'],
  medications: ['id', 'baby_id', 'name', 'start_date', 'updated_at'],
  medication_doses: ['id', 'baby_id', 'medication_name', 'time', 'updated_at'],
  doctor_visits: ['id', 'baby_id', 'date', 'updated_at'],
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
    // Late column: left undefined when an older app didn't send it, which
    // upsertRow reads as "keep what's stored".
    if ('concern_id' in raw) {
      row.concern_id = raw.concern_id ? normalizeUUID(raw.concern_id, 'concern_id') : null
    }
  } else if (table === 'concerns') {
    row.title = normalizeText(raw.title, 'title', 200)
    if (!row.title || !row.title.trim()) throw new RowError('title is required')
    // Free text: kinds are added in new app versions, and an older server
    // refusing one would stop every sync from that phone.
    row.kind = normalizeText(raw.kind, 'kind', 40)
    row.started_at = normalizeDate(raw.started_at, 'started_at', { required: true })
    row.resolved_at = normalizeDate(raw.resolved_at, 'resolved_at')
    if (row.resolved_at && row.resolved_at < row.started_at) {
      throw new RowError('resolved_at is before started_at')
    }
    row.severity = normalizeNumber(raw.severity, 'severity', { min: 1, max: 3, integer: true })
    row.note = normalizeText(raw.note, 'note') ?? ''
    row.outcome = normalizeText(raw.outcome, 'outcome', 1000) ?? ''
  } else if (table === 'medications') {
    row.name = normalizeText(raw.name, 'name', 200)
    if (!row.name || !row.name.trim()) throw new RowError('name is required')
    row.kind = normalizeText(raw.kind, 'kind', 40) ?? 'medicine'
    // Bounds catch a unit mix-up or a typo, not a judgment about the dose:
    // the app never suggests one, and neither does this.
    row.dose_amount = normalizeNumber(raw.dose_amount, 'dose_amount', { min: 0, max: 100000 })
    row.dose_unit = normalizeText(raw.dose_unit, 'dose_unit', 20) ?? 'ml'
    row.schedule = normalizeText(raw.schedule, 'schedule', 40) ?? 'asNeeded'
    row.times_per_day = normalizeNumber(raw.times_per_day, 'times_per_day', { min: 1, max: 24, integer: true })
    row.interval_hours = normalizeNumber(raw.interval_hours, 'interval_hours', { min: 0.5, max: 168 })
    row.min_hours_between = normalizeNumber(raw.min_hours_between, 'min_hours_between', { min: 0, max: 168 })
    row.max_doses_per_24h = normalizeNumber(raw.max_doses_per_24h, 'max_doses_per_24h',
      { min: 1, max: 48, integer: true })
    row.start_date = normalizeDate(raw.start_date, 'start_date', { required: true })
    row.end_date = normalizeDate(raw.end_date, 'end_date')
    if (row.end_date && row.end_date < row.start_date) throw new RowError('end_date is before start_date')
    row.instructions = normalizeText(raw.instructions, 'instructions') ?? ''
  } else if (table === 'medication_doses') {
    row.medication_id = raw.medication_id ? normalizeUUID(raw.medication_id, 'medication_id') : null
    row.medication_name = normalizeText(raw.medication_name, 'medication_name', 200)
    if (!row.medication_name || !row.medication_name.trim()) throw new RowError('medication_name is required')
    row.time = normalizeDate(raw.time, 'time', { required: true })
    row.amount = normalizeNumber(raw.amount, 'amount', { min: 0, max: 100000 })
    row.unit = normalizeText(raw.unit, 'unit', 20)
    row.note = normalizeText(raw.note, 'note') ?? ''
  } else if (table === 'doctor_visits') {
    row.date = normalizeDate(raw.date, 'date', { required: true })
    row.kind = normalizeText(raw.kind, 'kind', 40) ?? 'checkup'
    row.provider = normalizeText(raw.provider, 'provider', 200) ?? ''
    row.reason = normalizeText(raw.reason, 'reason', 1000) ?? ''
    row.doctor_notes = normalizeText(raw.doctor_notes, 'doctor_notes') ?? ''
    row.follow_up_date = normalizeDate(raw.follow_up_date, 'follow_up_date')
    row.follow_up_note = normalizeText(raw.follow_up_note, 'follow_up_note', 1000) ?? ''
    row.vaccines = normalizeText(raw.vaccines, 'vaccines', 1000) ?? ''
    row.weight_entry_id = raw.weight_entry_id ? normalizeUUID(raw.weight_entry_id, 'weight_entry_id') : null
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
  // A late column the row didn't carry keeps whatever is stored: an older app
  // editing a note mustn't unlink it from its concern.
  const late = new Set(LATE_COLUMNS[table] ?? [])
  const updated = columns.filter((c) => c !== 'id' && !(late.has(c) && row[c] === undefined))
  db.prepare(
    `INSERT INTO ${table} (${columns.join(', ')}, server_updated_at, server_ms)
     VALUES (${placeholders}, ?, ?)
     ON CONFLICT(id) DO UPDATE SET ${updated.map((c) => `${c} = excluded.${c}`).join(', ')},
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
