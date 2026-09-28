// Invites: how every phone after the first gets onto a log.
//
// The case that matters most is a phone that's already paired joining another
// baby — a second child, or a sitter's phone that already has its own. It must
// join as the caregiver it already is. The old behaviour minted a fresh
// identity, the app swapped its token for the new one, and every log the phone
// was already on stopped recognising it.

import { test } from 'node:test'
import assert from 'node:assert/strict'
import { iso, uuid, withServer } from './support.js'

test('a phone that is already paired joins another log as the caregiver it already is', async () => {
  await withServer({}, async ({ call, enrol, pushBaby, invite }) => {
    const brian = await enrol('Brian')
    const noraID = await pushBaby(brian.token, 'Nora')
    const leoID = await pushBaby(brian.token, 'Leo')

    // Annette's phone has a log of its own before anyone shares with her.
    const annette = await enrol('Annette')
    const ownID = await pushBaby(annette.token, 'Test baby')

    for (const babyID of [noraID, leoID]) {
      const code = await invite(brian.token, babyID)
      const joined = await call('POST', '/v1/pair/invite', {
        token: annette.token,
        body: { code, display_name: 'Annette' },
      })
      assert.equal(joined.status, 200)
      assert.equal(joined.body.token, null, 'she keeps the token she has')
      assert.equal(joined.body.user_id, annette.user_id)
      assert.equal(joined.body.baby.id, babyID)
    }

    const me = await call('GET', '/v1/me', { token: annette.token })
    const roles = Object.fromEntries(me.body.babies.map((b) => [b.name, b.role]))
    assert.deepEqual(roles, { Leo: 'caregiver', Nora: 'caregiver', 'Test baby': 'owner' })

    // And the log she had before still takes her rows.
    const push = await call('POST', '/v1/sync/push', {
      token: annette.token,
      body: { feeds: [{ id: uuid(), baby_id: ownID, start_time: iso(), kind: 'formula', updated_at: iso() }] },
    })
    assert.equal(push.body.applied.length, 1)
  })
})

test('the joining response lists every log the phone is now on', async () => {
  await withServer({}, async ({ call, enrol, pushBaby, invite }) => {
    const brian = await enrol('Brian')
    const noraID = await pushBaby(brian.token, 'Nora')
    const code = await invite(brian.token, noraID)
    const joined = await call('POST', '/v1/pair/invite', { body: { code, display_name: 'Annette' } })
    assert.equal(joined.status, 200)
    assert.ok(joined.body.token, 'a phone with no token gets one')
    assert.deepEqual(joined.body.babies.map((b) => b.id), [noraID])
    assert.equal(joined.body.babies[0].role, 'caregiver')
    assert.ok(joined.body.server_id)
    assert.equal(joined.body.members.length, 2)
  })
})

test('scanning a code again for a log you are already on spends nothing', async () => {
  await withServer({}, async ({ call, enrol, pushBaby, invite }) => {
    const brian = await enrol('Brian')
    const noraID = await pushBaby(brian.token, 'Nora')
    const code = await invite(brian.token, noraID, { max_uses: 2 })

    const annette = await enrol('Annette')
    await call('POST', '/v1/pair/invite', { token: annette.token, body: { code } })
    const again = await call('POST', '/v1/pair/invite', { token: annette.token, body: { code } })
    assert.equal(again.status, 200)
    assert.equal(again.body.token, null)

    // The owner scanning their own code neither spends it nor loses the owner seat.
    const own = await call('POST', '/v1/pair/invite', { token: brian.token, body: { code } })
    assert.equal(own.status, 200)
    const brianMe = await call('GET', '/v1/me', { token: brian.token })
    assert.equal(brianMe.body.babies[0].role, 'owner')

    // So the code's second use is still there for the phone it was meant for.
    const grandma = await call('POST', '/v1/pair/invite', { body: { code, display_name: 'Grandma' } })
    assert.equal(grandma.status, 200)
    const spent = await call('POST', '/v1/pair/invite', { body: { code, display_name: 'Nobody' } })
    assert.equal(spent.status, 410)
    assert.equal(spent.body.code, 'used_code')

    // Even once spent, a re-scan by somebody already on the log is fine.
    const late = await call('POST', '/v1/pair/invite', { token: annette.token, body: { code } })
    assert.equal(late.status, 200)
  })
})

test('any caregiver can bring the next one in', async () => {
  await withServer({}, async ({ call, enrol, pushBaby, invite }) => {
    const brian = await enrol('Brian')
    const noraID = await pushBaby(brian.token, 'Nora')
    const annette = (await call('POST', '/v1/pair/invite', {
      body: { code: await invite(brian.token, noraID), display_name: 'Annette' },
    })).body

    const code = await invite(annette.token, noraID)
    const grandma = await call('POST', '/v1/pair/invite', { body: { code, display_name: 'Grandma' } })
    assert.equal(grandma.status, 200)

    const members = await call('GET', `/v1/babies/${noraID}/members`, { token: brian.token })
    assert.deepEqual(members.body.members.map((m) => m.display_name), ['Brian', 'Annette', 'Grandma'])
    assert.deepEqual(members.body.members.map((m) => m.role), ['owner', 'caregiver', 'caregiver'])
  })
})

test('an invite is seen and cancelled by whoever made it, or by the owner', async () => {
  await withServer({}, async ({ call, enrol, pushBaby, invite }) => {
    const brian = await enrol('Brian')
    const noraID = await pushBaby(brian.token, 'Nora')
    const annette = (await call('POST', '/v1/pair/invite', {
      body: { code: await invite(brian.token, noraID), display_name: 'Annette' },
    })).body

    const hers = await invite(annette.token, noraID)
    const his = await invite(brian.token, noraID)

    const herList = await call('GET', `/v1/babies/${noraID}/invites`, { token: annette.token })
    assert.deepEqual(herList.body.invites.map((i) => i.code), [hers])
    const hisList = await call('GET', `/v1/babies/${noraID}/invites`, { token: brian.token })
    assert.deepEqual(hisList.body.invites.map((i) => i.code).sort(), [hers, his].sort())

    const notHers = await call('DELETE', `/v1/babies/${noraID}/invites/${his}`, { token: annette.token })
    assert.equal(notHers.status, 403)
    assert.equal((await call('DELETE', `/v1/babies/${noraID}/invites/${hers}`, { token: annette.token })).status, 200)
    assert.equal((await call('DELETE', `/v1/babies/${noraID}/invites/ZZZZZZ`, { token: brian.token })).status, 404)

    const cancelled = await call('POST', '/v1/pair/invite', { body: { code: hers, display_name: 'Too late' } })
    assert.equal(cancelled.status, 404)
  })
})

test('a revoked token scanning a code is treated as a phone with no token', async () => {
  await withServer({}, async ({ call, enrol, pushBaby, invite }) => {
    const brian = await enrol('Brian')
    const noraID = await pushBaby(brian.token, 'Nora')

    const old = await enrol('Old phone')
    const devices = await call('GET', '/v1/devices', { token: old.token })
    await call('DELETE', `/v1/devices/${devices.body.devices[0].id}`, { token: old.token })

    const joined = await call('POST', '/v1/pair/invite', {
      token: old.token,
      body: { code: await invite(brian.token, noraID), display_name: 'Old phone' },
    })
    assert.equal(joined.status, 200)
    assert.ok(joined.body.token, 'a new token, because the old one no longer means anything')
    assert.notEqual(joined.body.user_id, old.user_id)
  })
})

test('an invite for a log that has since been deleted is refused', async () => {
  await withServer({}, async ({ call, enrol, pushBaby, invite }) => {
    const brian = await enrol('Brian')
    const noraID = await pushBaby(brian.token, 'Nora')
    const code = await invite(brian.token, noraID)
    await call('POST', '/v1/sync/push', {
      token: brian.token,
      body: { babies: [{ id: noraID, name: 'Nora', updated_at: iso(1000), deleted_at: iso(1000) }] },
    })
    const refused = await call('POST', '/v1/pair/invite', { body: { code, display_name: 'Annette' } })
    assert.equal(refused.status, 410)
    assert.equal(refused.body.code, 'baby_gone')
  })
})
