// The pull route sends baby rows straight from the database, where `sealed` is
// a SQLite integer. The phone decodes it as a Bool, and Swift's JSONDecoder
// won't read 1 or 0 as one, so a single integer fails the whole page and a new
// phone never gets past its first pull. sealed.test.js checks the stored value;
// these check what goes over the wire.

import { test } from 'node:test'
import assert from 'node:assert/strict'
import { randomBytes } from 'node:crypto'
import { withServer, uuid, iso } from './support.js'

const SEALED = { 'x-babyfeed-sealed': '1' }

test('pull sends a sealed baby with sealed: true, not 1', async () => {
  await withServer({}, async ({ call, enrol }) => {
    const { token } = await enrol('')
    const id = uuid()
    const pushed = await call('POST', '/v1/sync/push', {
      token, headers: SEALED,
      body: {
        babies: [{ id, name: 'Maple', updated_at: iso(), sealed: true }],
        sealed: [{ id, baby_id: id, updated_at: iso(), sealed: randomBytes(120).toString('base64') }],
      },
    })
    assert.equal(pushed.body.rejected.length, 0, JSON.stringify(pushed.body.rejected))

    const pulled = await call('GET', `/v1/sync/pull?baby_id=${id}`, { token, headers: SEALED })
    assert.equal(pulled.status, 200, JSON.stringify(pulled.body))
    assert.equal(pulled.body.babies.length, 1)
    assert.strictEqual(pulled.body.babies[0].sealed, true)
  })
})

test('pull sends an ordinary baby with sealed: false, not 0', async () => {
  await withServer({}, async ({ call, enrol, pushBaby }) => {
    const { token } = await enrol('Ann')
    const id = await pushBaby(token, 'Rowan')

    const pulled = await call('GET', `/v1/sync/pull?baby_id=${id}`, { token })
    assert.equal(pulled.status, 200, JSON.stringify(pulled.body))
    assert.equal(pulled.body.babies.length, 1)
    assert.strictEqual(pulled.body.babies[0].sealed, false)
  })
})
