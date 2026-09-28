// A person's recovery phrase: one thing written down, covering every log that
// person is on — the ones they started and the ones shared with them.
//
// As with the older per-baby keys, the server only ever holds a hash. What's
// new is that the phrase belongs to a caregiver rather than to a log, so two
// children don't mean two phrases, and getting back in brings everything back.

import { test } from 'node:test'
import assert from 'node:assert/strict'
import { iso, mintKey, uuid, withServer } from './support.js'

test('one phrase brings back every log a person is on, owned or shared with them', async () => {
  await withServer({}, async ({ call, enrol, pushBaby, invite }) => {
    const phrase = mintKey()
    const brian = await enrol('Brian', { key_hash: phrase.hash })
    const noraID = await pushBaby(brian.token, 'Nora')
    await call('POST', '/v1/sync/push', {
      token: brian.token,
      body: { feeds: [{ id: uuid(), baby_id: noraID, start_time: iso(), kind: 'formula', amount_ml: 90, updated_at: iso() }] },
    })

    const annette = await enrol('Annette')
    const leoID = await pushBaby(annette.token, 'Leo')
    await call('POST', '/v1/pair/invite', { token: brian.token, body: { code: await invite(annette.token, leoID) } })

    // Every phone is gone. A new one, typed the way somebody reads it off paper.
    const written = phrase.key.match(/.{4}/g).join('-').toLowerCase()
    const back = await call('POST', '/v1/recover', { body: { key: written, device_name: 'New iPhone' } })
    assert.equal(back.status, 200)
    assert.ok(back.body.token)
    assert.equal(back.body.user_id, brian.user_id)
    assert.equal(back.body.merged, false)
    const roles = Object.fromEntries(back.body.babies.map((b) => [b.name, b.role]))
    assert.deepEqual(roles, { Leo: 'caregiver', Nora: 'owner' })

    const pull = await call('GET', `/v1/sync/pull?baby_id=${noraID}`, { token: back.body.token })
    assert.equal(pull.body.feeds[0].amount_ml, 90)
    assert.equal((await call('GET', `/v1/sync/pull?baby_id=${leoID}`, { token: back.body.token })).status, 200)

    const me = await call('GET', '/v1/me', { token: back.body.token })
    assert.ok(me.body.recovery_key.last_used_at, 'the server remembers the phrase was used')
  })
})

test('a phrase is set once; replacing it has to be asked for, and retires the old one', async () => {
  await withServer({}, async ({ call, enrol }) => {
    const brian = await enrol('Brian')
    const first = mintKey()
    const second = mintKey()

    const set = await call('POST', '/v1/me/recovery', { token: brian.token, body: { key_hash: first.hash } })
    assert.equal(set.status, 200)
    assert.equal(set.body.changed, true)
    assert.equal(set.body.exists, true)

    const same = await call('POST', '/v1/me/recovery', { token: brian.token, body: { key_hash: first.hash } })
    assert.equal(same.status, 200)
    assert.equal(same.body.changed, false, 'setting the same phrase again is a no-op, not a replacement')

    // A phone that simply doesn't hold the phrase must not be able to swap it
    // out by accident: that would quietly void the copy on paper.
    const accidental = await call('POST', '/v1/me/recovery', { token: brian.token, body: { key_hash: second.hash } })
    assert.equal(accidental.status, 409)
    assert.equal(accidental.body.code, 'key_exists')

    const replaced = await call('POST', '/v1/me/recovery', {
      token: brian.token,
      body: { key_hash: second.hash, replace: true },
    })
    assert.equal(replaced.status, 200)
    assert.equal(replaced.body.changed, true)

    assert.equal((await call('POST', '/v1/recover', { body: { key: first.key } })).status, 404)
    assert.equal((await call('POST', '/v1/recover', { body: { key: second.key } })).status, 200)
  })
})

test('a phrase belongs to one person', async () => {
  await withServer({}, async ({ call, enrol }) => {
    const phrase = mintKey()
    const brian = await enrol('Brian')
    const annette = await enrol('Annette')
    await call('POST', '/v1/me/recovery', { token: brian.token, body: { key_hash: phrase.hash } })
    const taken = await call('POST', '/v1/me/recovery', { token: annette.token, body: { key_hash: phrase.hash } })
    assert.equal(taken.status, 409)
    assert.equal(taken.body.code, 'key_taken')
  })
})

test('check says whether the phrase on this phone is the one the server knows, and nothing more', async () => {
  await withServer({}, async ({ call, enrol }) => {
    const brian = await enrol('Brian')
    const mine = mintKey()
    const other = mintKey()

    const none = await call('POST', '/v1/me/recovery/check', { token: brian.token, body: { key_hash: mine.hash } })
    assert.deepEqual(none.body, { exists: false, matches: false })

    await call('POST', '/v1/me/recovery', { token: brian.token, body: { key_hash: mine.hash } })
    const matches = await call('POST', '/v1/me/recovery/check', { token: brian.token, body: { key_hash: mine.hash } })
    assert.deepEqual(matches.body, { exists: true, matches: true })
    const differs = await call('POST', '/v1/me/recovery/check', { token: brian.token, body: { key_hash: other.hash } })
    assert.deepEqual(differs.body, { exists: true, matches: false })

    assert.equal((await call('POST', '/v1/me/recovery/check', { body: { key_hash: mine.hash } })).status, 401)
    assert.equal((await call('POST', '/v1/me/recovery/check', {
      token: brian.token, body: { key_hash: 'nope' },
    })).status, 400)
  })
})

test('restoring onto a phone that was set up as somebody else folds them in, and nothing is lost', async () => {
  await withServer({}, async ({ call, enrol, pushBaby }) => {
    const phrase = mintKey()
    const brian = await enrol('Brian', { key_hash: phrase.hash })
    const noraID = await pushBaby(brian.token, 'Nora')

    // A replacement phone, set up fresh before the phrase turned up — it even
    // made a phrase of its own and started a log.
    const stray = mintKey()
    const newPhone = await enrol('New phone', { key_hash: stray.hash })
    const tempID = await pushBaby(newPhone.token, 'Logged before restoring')

    const restored = await call('POST', '/v1/recover', { token: newPhone.token, body: { key: phrase.key } })
    assert.equal(restored.status, 200)
    assert.equal(restored.body.token, null, 'the phone keeps its token')
    assert.equal(restored.body.user_id, brian.user_id)
    assert.equal(restored.body.merged, true)
    assert.equal(restored.body.retired_key, true, "the stray phrase would open nothing now, so it's retired")

    const me = await call('GET', '/v1/me', { token: newPhone.token })
    assert.equal(me.body.user_id, brian.user_id, 'the phone is Brian now')
    const roles = Object.fromEntries(me.body.babies.map((b) => [b.id, b.role]))
    assert.deepEqual(roles, { [noraID]: 'owner', [tempID]: 'owner' })

    // Brian's original phone is untouched, and sees the folded-in log too.
    const original = await call('GET', '/v1/me', { token: brian.token })
    assert.equal(original.body.babies.length, 2)

    assert.equal((await call('POST', '/v1/recover', { body: { key: stray.key } })).status, 404)
  })
})

test('restoring onto the same person changes nothing', async () => {
  await withServer({}, async ({ call, enrol, pushBaby }) => {
    const phrase = mintKey()
    const brian = await enrol('Brian', { key_hash: phrase.hash })
    await pushBaby(brian.token, 'Nora')
    const again = await call('POST', '/v1/recover', { token: brian.token, body: { key: phrase.key } })
    assert.equal(again.status, 200)
    assert.equal(again.body.token, null)
    assert.equal(again.body.merged, false)
    assert.equal(again.body.babies.length, 1)
  })
})

test('the older per-baby keys still work next to personal phrases', async () => {
  await withServer({}, async ({ call, enrol, pushBaby }) => {
    const brian = await enrol('Brian', { key_hash: mintKey().hash })
    const noraID = await pushBaby(brian.token, 'Nora')
    const perBaby = mintKey()
    await call('POST', `/v1/babies/${noraID}/recovery`, { token: brian.token, body: { key_hash: perBaby.hash } })

    const back = await call('POST', '/v1/recover', { body: { key: perBaby.key, display_name: 'Brian' } })
    assert.equal(back.status, 200)
    assert.ok(back.body.token)
    assert.equal(back.body.baby.id, noraID)
    assert.deepEqual(back.body.babies.map((b) => b.id), [noraID])
    assert.ok(back.body.server_id)
  })
})
