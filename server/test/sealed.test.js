// Sealed babies: end-to-end encrypted logs, and the open enrolment that lets
// another family's phone set itself up from their own house.
//
// The server here never sees anything it could read for a sealed baby: the
// tests push opaque base64 the way the phone would, and check what the server
// keeps, refuses and hands back. The readable babies from before must carry on
// exactly as they were, so a few tests are about that too.

import { test } from 'node:test'
import assert from 'node:assert/strict'
import { randomBytes } from 'node:crypto'
import { DatabaseSync } from 'node:sqlite'
import { withServer, uuid, iso, mintKey } from './support.js'

const SEALED = { 'x-babyfeed-sealed': '1' }
/** What an AES-GCM box looks like from here: bytes nobody can read. */
const box = (size = 120) => randomBytes(size).toString('base64')

async function sealedBaby(call, token) {
  const id = uuid()
  const result = await call('POST', '/v1/sync/push', {
    token, headers: SEALED,
    body: {
      babies: [{ id, name: 'Nora', birth_date: iso(), sex: 'female', updated_at: iso(), sealed: true }],
      sealed: [{ id, baby_id: id, updated_at: iso(), sealed: box() }],
    },
  })
  assert.equal(result.status, 200, JSON.stringify(result.body))
  assert.equal(result.body.rejected.length, 0, JSON.stringify(result.body.rejected))
  return id
}

test('a sealed baby keeps no name or dates, and its rows only as opaque boxes', async () => {
  await withServer({}, async ({ call, enrol, dbPath }) => {
    const { token } = await enrol('')
    const babyID = await sealedBaby(call, token)
    const feed = { id: uuid(), baby_id: babyID, updated_at: iso(), sealed: box(300) }
    const pushed = await call('POST', '/v1/sync/push', { token, headers: SEALED, body: { sealed: [feed] } })
    assert.deepEqual(pushed.body.applied.map((a) => [a.table, a.status]), [['sealed', 'inserted']])

    const db = new DatabaseSync(dbPath)
    const baby = db.prepare('SELECT * FROM babies WHERE id = ?').get(babyID)
    assert.equal(baby.sealed, 1)
    assert.equal(baby.name, '', 'the name sent alongside is not kept')
    assert.equal(baby.birth_date, null)
    assert.equal(baby.sex, null)
    const stored = db.prepare('SELECT * FROM sealed_rows WHERE id = ?').get(feed.id)
    assert.equal(stored.sealed, feed.sealed)
    assert.deepEqual(Object.keys(stored).sort(),
      ['baby_id', 'id', 'logged_by', 'sealed', 'server_ms', 'server_updated_at', 'updated_at'],
      'no kind, no deletion, nothing else about the row')
    const change = db.prepare('SELECT * FROM changes WHERE row_id = ?').get(feed.id)
    assert.equal(change.table_name, 'sealed')
    assert.equal(change.actor_name, '')
    db.close()
  })
})

test('pulling a sealed baby pages its boxes, last writer wins by updated_at', async () => {
  await withServer({}, async ({ call, enrol }) => {
    const { token } = await enrol('')
    const babyID = await sealedBaby(call, token)
    const id = uuid()
    const newer = box()
    await call('POST', '/v1/sync/push', { token, headers: SEALED,
      body: { sealed: [{ id, baby_id: babyID, updated_at: iso(1000), sealed: newer }] } })
    const stale = await call('POST', '/v1/sync/push', { token, headers: SEALED,
      body: { sealed: [{ id, baby_id: babyID, updated_at: iso(-60_000), sealed: box() }] } })
    assert.equal(stale.body.applied[0].status, 'kept')

    const pulled = await call('GET', `/v1/sync/pull?baby_id=${babyID}`, { token, headers: SEALED })
    assert.equal(pulled.status, 200)
    const row = pulled.body.sealed.find((r) => r.id === id)
    assert.equal(row.sealed, newer)
    assert.equal(pulled.body.sealed.length, 2, 'the baby record and the one row')
    assert.equal(pulled.body.feeds.length, 0)

    const again = await call('GET', `/v1/sync/pull?baby_id=${babyID}&since=${pulled.body.next_since}`,
      { token, headers: SEALED })
    assert.equal(again.body.sealed.length, 0, 'nothing twice')
  })
})

test('a readable row is refused for a sealed baby, and a box for a readable one', async () => {
  await withServer({}, async ({ call, enrol, pushBaby }) => {
    const { token } = await enrol('Brian')
    const sealedID = await sealedBaby(call, token)
    const plainID = await pushBaby(token, 'Theo')

    const plain = await call('POST', '/v1/sync/push', { token, headers: SEALED, body: {
      feeds: [{ id: uuid(), baby_id: sealedID, start_time: iso(), kind: 'formula', updated_at: iso() }],
    } })
    assert.equal(plain.body.rejected[0].code, 'sealed_baby')

    const boxed = await call('POST', '/v1/sync/push', { token, headers: SEALED, body: {
      sealed: [{ id: uuid(), baby_id: plainID, updated_at: iso(), sealed: box() }],
    } })
    assert.equal(boxed.body.rejected[0].code, 'not_sealed')
  })
})

test('a sealed baby stays sealed when an older build edits it without the flag', async () => {
  await withServer({}, async ({ call, enrol, dbPath }) => {
    const { token } = await enrol('')
    const babyID = await sealedBaby(call, token)
    const edit = await call('POST', '/v1/sync/push', { token, body: {
      babies: [{ id: babyID, name: 'Leaked name', updated_at: iso(5000) }],
    } })
    assert.equal(edit.status, 200)
    const db = new DatabaseSync(dbPath)
    const baby = db.prepare('SELECT sealed, name FROM babies WHERE id = ?').get(babyID)
    db.close()
    assert.equal(baby.sealed, 1)
    assert.equal(baby.name, '')
  })
})

test('a readable baby stays readable when a newer build asks for it to be sealed', async () => {
  await withServer({}, async ({ call, enrol, pushBaby, dbPath }) => {
    const { token } = await enrol('Brian')
    const babyID = await pushBaby(token, 'Theo')
    await call('POST', '/v1/sync/push', { token, headers: SEALED, body: {
      babies: [{ id: babyID, name: 'Theo', updated_at: iso(5000), sealed: true }],
    } })
    const db = new DatabaseSync(dbPath)
    const baby = db.prepare('SELECT sealed, name FROM babies WHERE id = ?').get(babyID)
    db.close()
    assert.equal(baby.sealed, 0, 'existing logs are left exactly as they are')
    assert.equal(baby.name, 'Theo')
  })
})

test('an older build is never shown a sealed baby, and cannot join or pull one', async () => {
  await withServer({}, async ({ call, enrol, invite }) => {
    const owner = await enrol('')
    const babyID = await sealedBaby(call, owner.token)

    const old = await call('GET', '/v1/me', { token: owner.token })
    assert.equal(old.body.babies.length, 0)
    const fresh = await call('GET', '/v1/me', { token: owner.token, headers: SEALED })
    assert.equal(fresh.body.babies.length, 1)
    assert.equal(fresh.body.babies[0].sealed, true)

    const pull = await call('GET', `/v1/sync/pull?baby_id=${babyID}`, { token: owner.token })
    assert.equal(pull.status, 409)
    assert.equal(pull.body.code, 'app_update_needed')

    const code = await invite(owner.token, babyID)
    const join = await call('POST', '/v1/pair/invite', { body: { code, display_name: 'Grandma' } })
    assert.equal(join.status, 409)
    const stillUsable = await call('POST', '/v1/pair/invite', { headers: SEALED, body: { code, display_name: '' } })
    assert.equal(stillUsable.status, 200, 'refusing an old build did not spend the code')
    assert.equal(stillUsable.body.baby.sealed, true)
  })
})

test('the phrase-locked key is kept per caregiver and comes back with the phrase', async () => {
  await withServer({}, async ({ call, enrol }) => {
    const phrase = mintKey()
    const owner = await enrol('', { key_hash: phrase.hash })
    const babyID = await sealedBaby(call, owner.token)
    const wrapped = box(60)

    const bad = await call('PUT', `/v1/babies/${babyID}/key`, { token: owner.token, headers: SEALED, body: { wrapped: 'nope' } })
    assert.equal(bad.status, 400)
    const stored = await call('PUT', `/v1/babies/${babyID}/key`, { token: owner.token, headers: SEALED, body: { wrapped } })
    assert.equal(stored.status, 200)

    // A new phone with nothing on it, and only the phrase.
    const restored = await call('POST', '/v1/recover', { headers: SEALED, body: { key: phrase.key } })
    assert.equal(restored.status, 200)
    const membership = restored.body.babies.find((b) => b.id === babyID)
    assert.equal(membership.wrapped_key, wrapped)
    assert.equal(membership.sealed, true)
  })
})

test('a sealed name replaces the readable one on that log only, and rename skips it', async () => {
  await withServer({}, async ({ call, enrol, pushBaby }) => {
    const { token } = await enrol('Brian')
    const sealedID = await sealedBaby(call, token)
    const plainID = await pushBaby(token, 'Theo')

    let members = await call('GET', `/v1/babies/${sealedID}/members`, { token, headers: SEALED })
    assert.equal(members.body.members[0].display_name, '', 'not copied onto a sealed log')

    const sealedName = box(40)
    const put = await call('PUT', `/v1/babies/${sealedID}/members/me`, { token, headers: SEALED, body: { sealed_name: sealedName } })
    assert.equal(put.status, 200)
    await call('POST', '/v1/me', { token, body: { display_name: 'Brian T' } })

    members = await call('GET', `/v1/babies/${sealedID}/members`, { token, headers: SEALED })
    assert.equal(members.body.members[0].sealed_name, sealedName)
    assert.equal(members.body.members[0].display_name, '')
    const plain = await call('GET', `/v1/babies/${plainID}/members`, { token })
    assert.equal(plain.body.members[0].display_name, 'Brian T')
  })
})

test('open enrolment works through a proxy, within the per-address and daily limits', async () => {
  await withServer({ enroll: 'open', enrollRateLimit: { limit: 2, windowMs: 60_000 }, enrollDailyLimit: 3 },
    async ({ call }) => {
      const from = (address) => ({ 'x-forwarded-for': address })
      const health = await call('GET', '/v1/health', { headers: from('203.0.113.5') })
      assert.equal(health.body.enroll, 'open')
      assert.equal(health.body.enroll_available, true)
      assert.ok(health.body.features.includes('sealed'))

      const enrolFrom = (address) => call('POST', '/v1/pair/enroll', {
        headers: from(address), body: { display_name: '', device_name: 'iPhone' },
      })
      assert.equal((await enrolFrom('203.0.113.5')).status, 200)
      assert.equal((await enrolFrom('203.0.113.5')).status, 200)
      assert.equal((await enrolFrom('203.0.113.5')).status, 429, 'per address')
      assert.equal((await enrolFrom('198.51.100.7')).status, 200)
      const full = await enrolFrom('192.0.2.44')
      assert.equal(full.status, 429, 'per day, whoever is asking')
      assert.equal(full.body.code, 'enroll_full')
    })
})

test('health tells phones the public address when there is one', async () => {
  await withServer({ publicURL: 'https://babyfeed.example.org:4443' }, async ({ call }) => {
    const health = await call('GET', '/v1/health')
    assert.equal(health.body.public_url, 'https://babyfeed.example.org:4443')
  })
  await withServer({}, async ({ call }) => {
    assert.equal((await call('GET', '/v1/health')).body.public_url, null)
  })
})
