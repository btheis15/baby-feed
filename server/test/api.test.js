// End-to-end over real HTTP against a throwaway database, because the parts
// worth testing here are the ones that only show up in combination: a second
// caregiver joining, a conflict between two phones, and a delete that has to
// survive the other phone pushing its stale copy back.

import { test, before, after } from 'node:test'
import assert from 'node:assert/strict'
import { mkdtempSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { randomUUID } from 'node:crypto'
import { createApp } from '../src/server.js'

const SECRET = 'test-setup-secret'
let dir, server, base

before(async () => {
  dir = mkdtempSync(join(tmpdir(), 'babyfeed-test-'))
  const app = createApp({ dbPath: join(dir, 'test.db'), setupSecret: SECRET, log: () => {} })
  server = app.server
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve))
  base = `http://127.0.0.1:${server.address().port}`
})

after(() => {
  server.close()
  rmSync(dir, { recursive: true, force: true })
})

async function call(method, path, { token, body } = {}) {
  const res = await fetch(base + path, {
    method,
    headers: {
      ...(token ? { authorization: `Bearer ${token}` } : {}),
      ...(body ? { 'content-type': 'application/json' } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  })
  return { status: res.status, body: await res.json() }
}

const uuid = () => randomUUID().toUpperCase()
const iso = (offsetMs = 0) => new Date(Date.now() + offsetMs).toISOString()

test('health needs no token', async () => {
  const res = await call('GET', '/v1/health')
  assert.equal(res.status, 200)
  assert.equal(res.body.ok, true)
})

test('nothing else answers without a token', async () => {
  for (const path of ['/v1/me', '/v1/sync/pull?baby_id=' + uuid(), '/v1/devices']) {
    assert.equal((await call('GET', path)).status, 401, path)
  }
  assert.equal((await call('POST', '/v1/sync/push', { body: {} })).status, 401)
})

test('the wrong setup secret does not pair', async () => {
  const res = await call('POST', '/v1/pair/claim', { body: { secret: 'nope', display_name: 'X' } })
  assert.equal(res.status, 401)
  assert.equal(res.body.code, 'bad_secret')
})

let brian, annette, babyID

test('the first phone claims the server and becomes owner by pushing the baby', async () => {
  const claim = await call('POST', '/v1/pair/claim', {
    body: { secret: SECRET, display_name: 'Brian', device_name: "Brian's iPhone" },
  })
  assert.equal(claim.status, 200)
  brian = claim.body.token
  assert.ok(brian)

  babyID = uuid()
  const push = await call('POST', '/v1/sync/push', {
    token: brian,
    body: { babies: [{ id: babyID, name: 'Nora', birth_date: iso(-86400000 * 20), updated_at: iso() }] },
  })
  assert.equal(push.status, 200)
  assert.equal(push.body.applied.length, 1)
  assert.equal(push.body.applied[0].status, 'inserted')

  const me = await call('GET', '/v1/me', { token: brian })
  assert.equal(me.body.babies.length, 1)
  assert.equal(me.body.babies[0].role, 'owner')
  assert.equal(me.body.babies[0].name, 'Nora')
})

test('a stranger with a token sees nothing of that baby', async () => {
  // Pairing a second owner the legitimate way is the only way to get a token
  // without an invite, so that's the stranger here.
  const other = (await call('POST', '/v1/pair/claim', {
    body: { secret: SECRET, display_name: 'Stranger' },
  })).body.token
  const pull = await call('GET', `/v1/sync/pull?baby_id=${babyID}`, { token: other })
  assert.equal(pull.status, 404)
  const push = await call('POST', '/v1/sync/push', {
    token: other,
    body: { feeds: [{ id: uuid(), baby_id: babyID, start_time: iso(), kind: 'formula', updated_at: iso() }] },
  })
  assert.equal(push.body.applied.length, 0)
  assert.equal(push.body.rejected.length, 1)
})

test('an invite code lets the second caregiver join', async () => {
  const invite = await call('POST', `/v1/babies/${babyID}/invites`, { token: brian, body: {} })
  assert.equal(invite.status, 200)
  assert.equal(invite.body.code.length, 6)

  // Typed the way a person types it, lowercase and spaced.
  const spaced = invite.body.code.slice(0, 3).toLowerCase() + ' ' + invite.body.code.slice(3)
  const join = await call('POST', '/v1/pair/invite', {
    body: { code: spaced, display_name: 'Annette', device_name: "Annette's iPhone" },
  })
  assert.equal(join.status, 200)
  annette = join.body.token
  assert.equal(join.body.baby.name, 'Nora')
  assert.equal(join.body.members.length, 2)

  // Single use by default.
  const again = await call('POST', '/v1/pair/invite', {
    body: { code: invite.body.code, display_name: 'Nobody' },
  })
  assert.equal(again.status, 410)
})

test('a feed one phone logs reaches the other', async () => {
  const feedID = uuid()
  await call('POST', '/v1/sync/push', {
    token: annette,
    body: {
      feeds: [{
        id: feedID, baby_id: babyID, start_time: iso(-3600000), kind: 'formula',
        amount_ml: 90, note: '', logged_by_name: 'Annette', updated_at: iso(),
      }],
    },
  })
  const pull = await call('GET', `/v1/sync/pull?baby_id=${babyID}`, { token: brian })
  assert.equal(pull.status, 200)
  assert.equal(pull.body.feeds.length, 1)
  assert.equal(pull.body.feeds[0].id, feedID)
  assert.equal(pull.body.feeds[0].amount_ml, 90)
  assert.equal(pull.body.feeds[0].logged_by_name, 'Annette')
  assert.equal(pull.body.members.length, 2)
})

test('the watermark only returns what is new', async () => {
  const first = await call('GET', `/v1/sync/pull?baby_id=${babyID}`, { token: brian })
  const watermark = first.body.feeds.at(-1).server_updated_at
  const second = await call('GET', `/v1/sync/pull?baby_id=${babyID}&since=${encodeURIComponent(watermark)}`,
    { token: brian })
  assert.equal(second.body.feeds.length, 0)
})

test('last writer wins, and an older copy cannot undo a newer one', async () => {
  const feedID = uuid()
  const early = iso(-60000)
  const late = iso()
  await call('POST', '/v1/sync/push', {
    token: brian,
    body: { feeds: [{ id: feedID, baby_id: babyID, start_time: iso(), kind: 'formula', amount_ml: 60, updated_at: early }] },
  })
  // Annette edits it later: her amount wins.
  await call('POST', '/v1/sync/push', {
    token: annette,
    body: { feeds: [{ id: feedID, baby_id: babyID, start_time: iso(), kind: 'formula', amount_ml: 120, updated_at: late }] },
  })
  // Brian's phone pushes its stale copy again — it must not win.
  const stale = await call('POST', '/v1/sync/push', {
    token: brian,
    body: { feeds: [{ id: feedID, baby_id: babyID, start_time: iso(), kind: 'formula', amount_ml: 60, updated_at: early }] },
  })
  assert.equal(stale.body.applied[0].status, 'kept')

  const pull = await call('GET', `/v1/sync/pull?baby_id=${babyID}`, { token: annette })
  const feed = pull.body.feeds.find((f) => f.id === feedID)
  assert.equal(feed.amount_ml, 120)
})

test('a delete propagates and survives a stale re-push', async () => {
  const feedID = uuid()
  const created = iso(-60000)
  await call('POST', '/v1/sync/push', {
    token: brian,
    body: { feeds: [{ id: feedID, baby_id: babyID, start_time: iso(), kind: 'nursing', duration_minutes: 12, updated_at: created }] },
  })
  await call('POST', '/v1/sync/push', {
    token: brian,
    body: { feeds: [{ id: feedID, baby_id: babyID, start_time: iso(), kind: 'nursing', duration_minutes: 12, updated_at: iso(), deleted_at: iso() }] },
  })
  const stale = await call('POST', '/v1/sync/push', {
    token: annette,
    body: { feeds: [{ id: feedID, baby_id: babyID, start_time: iso(), kind: 'nursing', duration_minutes: 12, updated_at: created }] },
  })
  assert.equal(stale.body.applied[0].status, 'kept')
  const pull = await call('GET', `/v1/sync/pull?baby_id=${babyID}`, { token: annette })
  assert.ok(pull.body.feeds.find((f) => f.id === feedID).deleted_at)
})

test('weights and care notes sync too', async () => {
  const weightID = uuid()
  const noteID = uuid()
  const push = await call('POST', '/v1/sync/push', {
    token: annette,
    body: {
      weights: [{ id: weightID, baby_id: babyID, date: iso(), grams: 3800, logged_by_name: 'Annette', updated_at: iso() }],
      care_notes: [{ id: noteID, baby_id: babyID, date: iso(), kind: 'crying', note: 'Inconsolable at 8pm', severity: 2, logged_by_name: 'Annette', updated_at: iso() }],
    },
  })
  assert.equal(push.body.applied.length, 2)
  const pull = await call('GET', `/v1/sync/pull?baby_id=${babyID}`, { token: brian })
  assert.equal(pull.body.weights.find((w) => w.id === weightID).grams, 3800)
  assert.equal(pull.body.care_notes.find((n) => n.id === noteID).severity, 2)
})

test('a malformed row is refused without spoiling the rest of the push', async () => {
  const goodID = uuid()
  const push = await call('POST', '/v1/sync/push', {
    token: brian,
    body: {
      feeds: [
        { id: 'not-a-uuid', baby_id: babyID, start_time: iso(), kind: 'formula', updated_at: iso() },
        { id: uuid(), baby_id: babyID, start_time: iso(), kind: 'formula', amount_ml: 99999, updated_at: iso() },
        { id: goodID, baby_id: babyID, start_time: iso(), kind: 'formula', amount_ml: 100, updated_at: iso() },
      ],
    },
  })
  assert.equal(push.body.rejected.length, 2)
  assert.equal(push.body.applied.length, 1)
  assert.equal(push.body.applied[0].id, goodID)
})

test('the change feed says who did what', async () => {
  const changes = await call('GET', `/v1/changes?baby_id=${babyID}`, { token: brian })
  assert.ok(changes.body.changes.length > 0)
  const byAnnette = changes.body.changes.filter((c) => !c.by_me)
  assert.ok(byAnnette.length > 0)
  assert.ok(byAnnette.some((c) => c.actor_name === 'Annette'))
})

test('a rename reaches the member list the other caregiver reads', async () => {
  // GET and POST /v1/me share a path. The router used to stop at the first
  // route whose path matched and answer 405, so a rename never landed and the
  // other phone kept showing the old name.
  const renamed = await call('POST', '/v1/me', { token: annette, body: { display_name: 'Annette B' } })
  assert.equal(renamed.status, 200)
  assert.equal(renamed.body.display_name, 'Annette B')

  const members = await call('GET', `/v1/babies/${babyID}/members`, { token: brian })
  assert.ok(members.body.members.some((m) => m.display_name === 'Annette B'))
})

test('a caregiver can leave, and then sees nothing', async () => {
  const me = await call('GET', '/v1/me', { token: annette })
  const res = await call('DELETE', `/v1/babies/${babyID}/members/${me.body.user_id}`, { token: annette })
  assert.equal(res.status, 200)
  assert.equal((await call('GET', `/v1/sync/pull?baby_id=${babyID}`, { token: annette })).status, 404)
})

test('a revoked device stops working', async () => {
  const devices = await call('GET', '/v1/devices', { token: brian })
  const other = (await call('POST', '/v1/pair/claim', { body: { secret: SECRET, display_name: 'Old phone' } })).body.token
  const theirs = await call('GET', '/v1/devices', { token: other })
  await call('DELETE', `/v1/devices/${theirs.body.devices[0].id}`, { token: other })
  assert.equal((await call('GET', '/v1/me', { token: other })).status, 401)
  // Brian's own device is untouched.
  assert.equal((await call('GET', '/v1/me', { token: brian })).status, 200)
  assert.ok(devices.body.devices.some((d) => d.is_this_device))
})

test('both methods on a shared path are reachable, and only they are', async () => {
  const listed = await call('GET', `/v1/babies/${babyID}/invites`, { token: brian })
  assert.equal(listed.status, 200)
  assert.ok(Array.isArray(listed.body.invites))

  const created = await call('POST', `/v1/babies/${babyID}/invites`, { token: brian, body: {} })
  assert.equal(created.status, 200)

  // A path with no handler for the method is still 405, and an unknown path 404.
  assert.equal((await call('DELETE', '/v1/me', { token: brian })).status, 405)
  assert.equal((await call('GET', '/v1/nope', { token: brian })).status, 404)
})
