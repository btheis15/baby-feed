// The recovery key: the last way into a baby's log when every phone is gone.
//
// The property worth protecting here is that the server never holds anything
// that opens a log. The phone makes the key and keeps it; the server is told a
// hash. So these tests care as much about what the server *can't* do — hand a
// key back, accept a guess, let a non-owner set one — as about recovery
// working.

import { test } from 'node:test'
import assert from 'node:assert/strict'
import { mkdtempSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { randomUUID, createHash, randomBytes } from 'node:crypto'
import { createApp } from '../src/server.js'
import { isPlausibleRecoveryKey, normalizeRecoveryKey, RECOVERY_KEY_LENGTH } from '../src/auth.js'

const SECRET = 'test-setup-secret'
const ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'

/** What the phone does: make a key, hash it, keep the key. */
function mintKey() {
  const bytes = randomBytes(RECOVERY_KEY_LENGTH)
  let key = ''
  for (let i = 0; i < RECOVERY_KEY_LENGTH; i++) key += ALPHABET[bytes[i] % ALPHABET.length]
  return { key, hash: createHash('sha256').update(key).digest('hex') }
}

async function withServer(run) {
  const dir = mkdtempSync(join(tmpdir(), 'babyfeed-recovery-'))
  const app = createApp({
    dbPath: join(dir, 'test.db'),
    setupSecret: SECRET,
    log: () => {},
    pairRateLimit: { limit: 1000, windowMs: 60_000 },
  })
  await new Promise((resolve) => app.server.listen(0, '127.0.0.1', resolve))
  const base = `http://127.0.0.1:${app.server.address().port}`

  async function call(method, path, { token, body } = {}) {
    const response = await fetch(base + path, {
      method,
      headers: {
        ...(body ? { 'content-type': 'application/json' } : {}),
        ...(token ? { authorization: `Bearer ${token}` } : {}),
      },
      body: body ? JSON.stringify(body) : undefined,
    })
    const text = await response.text()
    return { status: response.status, body: text ? JSON.parse(text) : null }
  }

  // An owner with a baby on the server, which is the starting point throughout.
  const owner = (await call('POST', '/v1/pair/claim', {
    body: { secret: SECRET, display_name: 'Brian' },
  })).body
  const babyID = randomUUID().toUpperCase()
  await call('POST', '/v1/sync/push', {
    token: owner.token,
    body: { babies: [{ id: babyID, name: 'Nora', updated_at: new Date().toISOString() }] },
  })

  try {
    await run({ call, owner, babyID })
  } finally {
    app.server.close()
    rmSync(dir, { recursive: true, force: true })
  }
}

test('the key format is 24 characters and shrugs off dashes and case', () => {
  const { key } = mintKey()
  assert.equal(key.length, 24)
  assert.ok(isPlausibleRecoveryKey(key))

  const written = `${key.slice(0, 4)}-${key.slice(4, 8)} ${key.slice(8)}`.toLowerCase()
  assert.equal(normalizeRecoveryKey(written), key)
  assert.ok(isPlausibleRecoveryKey(written), 'how a person writes it down must still count')

  assert.ok(!isPlausibleRecoveryKey(key.slice(0, 23)), 'too short')
  assert.ok(!isPlausibleRecoveryKey(key + 'A'), 'too long')
  assert.ok(!isPlausibleRecoveryKey('I'.repeat(24)), 'I is not in the alphabet')
  assert.ok(!isPlausibleRecoveryKey(''))
})

test('an owner registers a hash, and the server will not give it back', async () => {
  await withServer(async ({ call, owner, babyID }) => {
    const before = await call('GET', `/v1/babies/${babyID}/recovery`, { token: owner.token })
    assert.equal(before.body.exists, false)

    const { hash } = mintKey()
    const set = await call('POST', `/v1/babies/${babyID}/recovery`, {
      token: owner.token,
      body: { key_hash: hash },
    })
    assert.equal(set.status, 200)

    const after = await call('GET', `/v1/babies/${babyID}/recovery`, { token: owner.token })
    assert.equal(after.body.exists, true)
    assert.ok(after.body.created_at)
    // The thing that matters: nothing in the response opens the log.
    const text = JSON.stringify(after.body)
    assert.ok(!text.includes(hash), 'must not echo the hash')
  })
})

test('a recovery key gets the log back on a phone with nothing on it', async () => {
  await withServer(async ({ call, owner, babyID }) => {
    const { key, hash } = mintKey()
    await call('POST', `/v1/babies/${babyID}/recovery`, { token: owner.token, body: { key_hash: hash } })

    // Something worth recovering.
    await call('POST', '/v1/sync/push', {
      token: owner.token,
      body: {
        feeds: [{
          id: randomUUID().toUpperCase(), baby_id: babyID, start_time: new Date().toISOString(),
          kind: 'formula', amount_ml: 90, updated_at: new Date().toISOString(),
        }],
      },
    })

    // A new phone, typed the way somebody reads it off paper.
    const written = `${key.slice(0, 4)}-${key.slice(4, 8)}-${key.slice(8, 12)}-${key.slice(12, 16)}-${key.slice(16, 20)}-${key.slice(20)}`
    const recovered = await call('POST', '/v1/recover', {
      body: { key: written.toLowerCase(), display_name: 'Brian again', device_name: 'New iPhone' },
    })
    assert.equal(recovered.status, 200)
    assert.ok(recovered.body.token)
    assert.equal(recovered.body.baby.id, babyID)

    // And it can actually read the log.
    const pull = await call('GET', `/v1/sync/pull?baby_id=${babyID}`, { token: recovered.body.token })
    assert.equal(pull.status, 200)
    assert.equal(pull.body.feeds.length, 1)
    assert.equal(pull.body.feeds[0].amount_ml, 90)
  })
})

test('recovering restores the owner seat, so invites can be issued again', async () => {
  await withServer(async ({ call, owner, babyID }) => {
    const { key, hash } = mintKey()
    await call('POST', `/v1/babies/${babyID}/recovery`, { token: owner.token, body: { key_hash: hash } })

    const recovered = await call('POST', '/v1/recover', { body: { key, display_name: 'Recovered' } })
    const invite = await call('POST', `/v1/babies/${babyID}/invites`, { token: recovered.body.token })
    assert.equal(invite.status, 200, 'a recovered caregiver must be able to re-share the log')
  })
})

test('recovering a second baby adds to this phone rather than replacing it', async () => {
  // A caregiver can be on more than one log — a real baby and a test one, or
  // two children. A phone holds one token, so recovering the second must join
  // the caregiver this phone already is, not quietly become a different one.
  await withServer(async ({ call, owner, babyID }) => {
    const secondID = randomUUID().toUpperCase()
    await call('POST', '/v1/sync/push', {
      token: owner.token,
      body: { babies: [{ id: secondID, name: 'Test Baby', updated_at: new Date().toISOString() }] },
    })

    const key = mintKey()
    await call('POST', `/v1/babies/${secondID}/recovery`, { token: owner.token, body: { key_hash: key.hash } })

    // A fresh phone recovers the second baby...
    const fresh = await call('POST', '/v1/recover', { body: { key: key.key, display_name: 'Fresh' } })
    assert.equal(fresh.status, 200)
    assert.ok(fresh.body.token)

    // ...and then recovers nothing else; but the owner's phone, which already
    // has a token, can take on a log it lost without losing the one it has.
    const firstKey = mintKey()
    await call('POST', `/v1/babies/${babyID}/recovery`, { token: owner.token, body: { key_hash: firstKey.hash } })
    const onto = await call('POST', '/v1/recover', {
      token: fresh.body.token,
      body: { key: firstKey.key },
    })
    assert.equal(onto.status, 200)
    assert.equal(onto.body.token, null, 'the phone keeps the token it has')
    assert.equal(onto.body.user_id, fresh.body.user_id, 'same caregiver, now on both')

    const me = await call('GET', '/v1/me', { token: fresh.body.token })
    assert.equal(me.body.babies.length, 2, 'both logs reachable from the one phone')
    assert.deepEqual(me.body.babies.map((b) => b.role).sort(), ['owner', 'owner'])
  })
})

test('a wrong key recovers nothing', async () => {
  await withServer(async ({ call, owner, babyID }) => {
    const { hash } = mintKey()
    await call('POST', `/v1/babies/${babyID}/recovery`, { token: owner.token, body: { key_hash: hash } })

    const wrong = await call('POST', '/v1/recover', { body: { key: mintKey().key } })
    assert.equal(wrong.status, 404)
    assert.equal(wrong.body.code, 'bad_key')

    for (const rubbish of ['', 'hello', 'A'.repeat(23), null]) {
      const result = await call('POST', '/v1/recover', { body: { key: rubbish } })
      assert.equal(result.status, 400, `"${rubbish}" should not be taken seriously`)
    }
  })
})

test('replacing the key retires the old one', async () => {
  await withServer(async ({ call, owner, babyID }) => {
    const first = mintKey()
    await call('POST', `/v1/babies/${babyID}/recovery`, { token: owner.token, body: { key_hash: first.hash } })

    const second = mintKey()
    await call('POST', `/v1/babies/${babyID}/recovery`, { token: owner.token, body: { key_hash: second.hash } })

    const old = await call('POST', '/v1/recover', { body: { key: first.key } })
    assert.equal(old.status, 404, 'a key written on paper and since replaced must stop working')

    const current = await call('POST', '/v1/recover', { body: { key: second.key } })
    assert.equal(current.status, 200)
  })
})

test('only the owner can set a key, and a stranger cannot even look', async () => {
  await withServer(async ({ call, owner, babyID }) => {
    const invite = await call('POST', `/v1/babies/${babyID}/invites`, { token: owner.token })
    const caregiver = (await call('POST', '/v1/pair/invite', {
      body: { code: invite.body.code, display_name: 'Annette' },
    })).body

    const attempt = await call('POST', `/v1/babies/${babyID}/recovery`, {
      token: caregiver.token,
      body: { key_hash: mintKey().hash },
    })
    assert.equal(attempt.status, 403)
    assert.equal(attempt.body.code, 'not_owner')

    // A member may see *that* a key exists — useful to know the log is safe.
    const look = await call('GET', `/v1/babies/${babyID}/recovery`, { token: caregiver.token })
    assert.equal(look.status, 200)

    // Somebody with no part in this baby sees nothing at all.
    const otherBabyID = randomUUID().toUpperCase()
    await call('POST', '/v1/sync/push', {
      token: owner.token,
      body: { babies: [{ id: otherBabyID, name: 'Other', updated_at: new Date().toISOString() }] },
    })
    const strangerInvite = await call('POST', `/v1/babies/${otherBabyID}/invites`, { token: owner.token })
    const stranger = (await call('POST', '/v1/pair/invite', {
      body: { code: strangerInvite.body.code, display_name: 'Stranger' },
    })).body
    const peek = await call('GET', `/v1/babies/${babyID}/recovery`, { token: stranger.token })
    assert.equal(peek.status, 404)
  })
})

test('a malformed hash is refused', async () => {
  await withServer(async ({ call, owner, babyID }) => {
    for (const bad of ['', 'nothex', 'a'.repeat(63), 'A'.repeat(64)]) {
      const result = await call('POST', `/v1/babies/${babyID}/recovery`, {
        token: owner.token,
        body: { key_hash: bad },
      })
      assert.equal(result.status, 400, `"${bad}" is not a sha256 hex digest`)
    }
  })
})
