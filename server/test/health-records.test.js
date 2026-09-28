// Concerns, medicines, doses and doctor visits: the health half of the log,
// synced like everything else between the two caregivers.

import test from 'node:test'
import assert from 'node:assert/strict'
import { withServer, uuid, iso } from './support.js'

async function twoCaregivers({ call, enrol, pushBaby, invite }) {
  const brian = await enrol('Brian')
  const babyID = await pushBaby(brian.token, 'Nora')
  const annette = await enrol('Annette')
  const code = await invite(brian.token, babyID)
  const joined = await call('POST', '/v1/pair/invite', { token: annette.token, body: { code } })
  assert.equal(joined.status, 200)
  return { brian, annette, babyID }
}

async function pull(call, token, babyID) {
  const result = await call('GET', `/v1/sync/pull?baby_id=${babyID}`, { token })
  assert.equal(result.status, 200)
  return result.body
}

const rows = (babyID) => ({
  concerns: [{
    id: uuid(), baby_id: babyID, title: 'Red left eye', kind: 'eye', started_at: iso(-3 * 86_400_000),
    resolved_at: null, severity: 2, note: 'goopy in the morning', outcome: '', logged_by_name: 'Brian',
    updated_at: iso(),
  }],
  medications: [{
    id: uuid(), baby_id: babyID, name: 'Vitamin D', kind: 'supplement', dose_amount: null, dose_unit: 'drop',
    schedule: 'daily', times_per_day: 1, interval_hours: null, min_hours_between: null, max_doses_per_24h: 1,
    start_date: iso(-86_400_000), end_date: null, instructions: 'with a feed', logged_by_name: 'Brian',
    updated_at: iso(),
  }],
  medication_doses: [{
    id: uuid(), baby_id: babyID, medication_id: null, medication_name: 'Vitamin D', time: iso(-3_600_000),
    amount: 1, unit: 'drop', note: '', logged_by_name: 'Brian', updated_at: iso(),
  }],
  doctor_visits: [{
    id: uuid(), baby_id: babyID, date: iso(-2 * 86_400_000), kind: 'checkup', provider: 'Dr. Patel',
    reason: '1-week weight check', doctor_notes: 'Feeding well.', follow_up_date: null, follow_up_note: '',
    vaccines: '', weight_entry_id: null, logged_by_name: 'Brian', updated_at: iso(),
  }],
})

test('every health record reaches the other caregiver', async () => {
  await withServer({}, async (server) => {
    const { brian, annette, babyID } = await twoCaregivers(server)
    const body = rows(babyID)
    const pushed = await server.call('POST', '/v1/sync/push', { token: brian.token, body })
    assert.equal(pushed.status, 200)
    assert.equal(pushed.body.rejected.length, 0, JSON.stringify(pushed.body.rejected))
    assert.equal(pushed.body.applied.length, 4)

    const got = await pull(server.call, annette.token, babyID)
    for (const table of Object.keys(body)) {
      assert.equal(got[table].length, 1, table)
      const sent = body[table][0]
      const received = got[table][0]
      for (const [key, value] of Object.entries(sent)) {
        if (key === 'updated_at' || key.endsWith('_at') || key === 'date' || key === 'time' || key.endsWith('_date')) {
          if (value) assert.equal(new Date(received[key]).getTime(), new Date(value).getTime(), `${table}.${key}`)
          continue
        }
        assert.deepEqual(received[key], value, `${table}.${key}`)
      }
    }
  })
})

test('health rows that make no sense are refused, and nothing else is', async () => {
  await withServer({}, async (server) => {
    const { brian, babyID } = await twoCaregivers(server)
    const good = rows(babyID)
    const body = {
      concerns: [
        { ...good.concerns[0], id: uuid(), title: '   ' },
        { ...good.concerns[0], id: uuid(), resolved_at: iso(-10 * 86_400_000) },
      ],
      medications: [
        { ...good.medications[0], id: uuid(), name: '' },
        { ...good.medications[0], id: uuid(), end_date: iso(-30 * 86_400_000) },
        { ...good.medications[0], id: uuid(), times_per_day: 0 },
      ],
      medication_doses: [
        { ...good.medication_doses[0], id: uuid(), medication_name: '' },
        { ...good.medication_doses[0], id: uuid(), amount: -1 },
      ],
      doctor_visits: [{ ...good.doctor_visits[0], id: uuid(), date: 'soon' }],
    }
    const pushed = await server.call('POST', '/v1/sync/push', { token: brian.token, body })
    assert.equal(pushed.body.applied.length, 0)
    assert.equal(pushed.body.rejected.length, 8)
    assert.ok(pushed.body.rejected.every((r) => r.code === 'malformed'))
  })
})

test('a new kind of concern from a newer app is kept, not refused', async () => {
  await withServer({}, async (server) => {
    const { brian, annette, babyID } = await twoCaregivers(server)
    const concern = { ...rows(babyID).concerns[0], kind: 'somethingAddedLater' }
    const pushed = await server.call('POST', '/v1/sync/push', { token: brian.token, body: { concerns: [concern] } })
    assert.equal(pushed.body.rejected.length, 0)
    const got = await pull(server.call, annette.token, babyID)
    assert.equal(got.concerns[0].kind, 'somethingAddedLater')
  })
})

test('a deleted dose disappears on the other phone, and a stale re-push is kept out', async () => {
  await withServer({}, async (server) => {
    const { brian, annette, babyID } = await twoCaregivers(server)
    const dose = rows(babyID).medication_doses[0]
    await server.call('POST', '/v1/sync/push', { token: brian.token, body: { medication_doses: [dose] } })

    const deleted = { ...dose, deleted_at: iso(), updated_at: iso(1000) }
    await server.call('POST', '/v1/sync/push', { token: annette.token, body: { medication_doses: [deleted] } })

    // Brian's phone, offline, pushes its old copy again.
    const stale = await server.call('POST', '/v1/sync/push', { token: brian.token, body: { medication_doses: [dose] } })
    assert.equal(stale.body.applied[0].status, 'kept')

    const got = await pull(server.call, brian.token, babyID)
    assert.ok(got.medication_doses[0].deleted_at, 'the delete stands')
  })
})

test('a note keeps its concern when an older app edits it', async () => {
  await withServer({}, async (server) => {
    const { brian, annette, babyID } = await twoCaregivers(server)
    const concernID = uuid()
    const note = {
      id: uuid(), baby_id: babyID, date: iso(), kind: 'eye', note: 'less red today', severity: null,
      resolved_at: null, concern_id: concernID, logged_by_name: 'Brian', updated_at: iso(),
    }
    await server.call('POST', '/v1/sync/push', { token: brian.token, body: { care_notes: [note] } })

    // An app from before concerns doesn't know the key, and doesn't send it.
    const { concern_id: _, ...older } = note
    await server.call('POST', '/v1/sync/push', {
      token: annette.token, body: { care_notes: [{ ...older, note: 'much better', updated_at: iso(1000) }] },
    })
    let got = await pull(server.call, brian.token, babyID)
    assert.equal(got.care_notes[0].note, 'much better')
    assert.equal(got.care_notes[0].concern_id, concernID, 'an absent key keeps what was stored')

    // An explicit null is an unlink, and is honoured.
    await server.call('POST', '/v1/sync/push', {
      token: brian.token, body: { care_notes: [{ ...note, concern_id: null, updated_at: iso(2000) }] },
    })
    got = await pull(server.call, brian.token, babyID)
    assert.equal(got.care_notes[0].concern_id, null)
  })
})

test('health says what this server can store', async () => {
  await withServer({}, async ({ call }) => {
    const health = await call('GET', '/v1/health')
    for (const table of ['concerns', 'medications', 'medication_doses', 'doctor_visits', 'care_notes']) {
      assert.ok(health.body.tables.includes(table), table)
    }
    assert.equal(health.body.schema_version, 2)
  })
})
