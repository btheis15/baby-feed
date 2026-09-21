// Sign in with Apple, end to end over real HTTP.
//
// The verifier is injected, so these tests are about what the *server* does
// with a verified identity rather than about the crypto — apple.test.js covers
// that. The cases worth having are the four that differ: a new caregiver, the
// same caregiver on a second phone, an already-paired phone attaching an
// account, and an Apple ID that belongs to somebody else.

import { test, before, after } from 'node:test'
import assert from 'node:assert/strict'
import { mkdtempSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { randomUUID } from 'node:crypto'
import { createApp } from '../src/server.js'

const SECRET = 'test-setup-secret'
let dir, server, base

/** Stands in for Apple: the "token" is just the subject to hand back. */
async function fakeVerify(identityToken, { rawNonce } = {}) {
  if (!identityToken || String(identityToken).startsWith('bad')) {
    throw new Error("That sign-in token's signature doesn't check out.")
  }
  return { subject: String(identityToken), email: null, emailVerified: false, isPrivateEmail: false }
}

before(async () => {
  dir = mkdtempSync(join(tmpdir(), 'babyfeed-apple-'))
  const app = createApp({
    dbPath: join(dir, 'test.db'),
    setupSecret: SECRET,
    log: () => {},
    verifyAppleToken: fakeVerify,
    pairRateLimit: { limit: 1000, windowMs: 60_000 },
  })
  server = app.server
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve))
  base = `http://127.0.0.1:${server.address().port}`
})

after(() => {
  server.close()
  rmSync(dir, { recursive: true, force: true })
})

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

const signIn = (subject, extra = {}) =>
  call('POST', '/v1/auth/apple', { body: { identity_token: subject, ...extra } })

test('a forged token is refused before anything is created', async () => {
  const result = await call('POST', '/v1/auth/apple', { body: { identity_token: 'bad-token' } })
  assert.equal(result.status, 401)
  assert.equal(result.body.code, 'bad_apple_token')
})

test('a new Apple ID gets an account and a token', async () => {
  const result = await signIn('apple-sub-new', { display_name: 'Brian', device_name: 'iPhone 17 Pro' })
  assert.equal(result.status, 200)
  assert.ok(result.body.token, 'should hand back a device token')
  assert.equal(result.body.display_name, 'Brian')
  assert.equal(result.body.is_new_account, true)
  assert.deepEqual(result.body.babies, [])
})

test('the same Apple ID on a second phone returns the same account', async () => {
  const first = await signIn('apple-sub-same', { display_name: 'Annette' })
  const second = await signIn('apple-sub-same', { device_name: 'iPad' })

  assert.equal(second.status, 200)
  assert.equal(second.body.user_id, first.body.user_id, 'same caregiver, not a new one')
  assert.equal(second.body.is_new_account, false)
  assert.notEqual(second.body.token, first.body.token, 'each phone gets its own token')
  assert.equal(second.body.display_name, 'Annette', 'keeps the name from the first sign-in')
})

test('a later sign-in cannot blank out the name Apple no longer sends', async () => {
  await signIn('apple-sub-named', { display_name: 'Sam' })
  const again = await signIn('apple-sub-named', { display_name: '' })
  assert.equal(again.body.display_name, 'Sam')
})

test('a phone paired the old way can attach an account and keep its token', async () => {
  const paired = await call('POST', '/v1/pair/claim', {
    body: { secret: SECRET, display_name: 'Owner', device_name: 'iPhone' },
  })
  assert.equal(paired.status, 200)

  const linked = await call('POST', '/v1/auth/apple', {
    token: paired.body.token,
    body: { identity_token: 'apple-sub-linking' },
  })
  assert.equal(linked.status, 200)
  assert.equal(linked.body.user_id, paired.body.user_id, 'links rather than making a second caregiver')
  assert.equal(linked.body.token, null, 'the phone already has one; a second device row would be a stranger')
  assert.equal(linked.body.is_new_account, false)

  // The original token still works, and signing in elsewhere reaches the same account.
  const me = await call('GET', '/v1/me', { token: paired.body.token })
  assert.equal(me.status, 200)
  assert.equal(me.body.user_id, paired.body.user_id)

  const elsewhere = await signIn('apple-sub-linking', { device_name: 'Replacement iPhone' })
  assert.equal(elsewhere.body.user_id, paired.body.user_id, 'recovery: same log on a new phone')
  assert.ok(elsewhere.body.token)
})

test('an Apple ID already attached to someone else is refused, not merged', async () => {
  const other = await call('POST', '/v1/pair/claim', {
    body: { secret: SECRET, display_name: 'Somebody Else' },
  })
  const clash = await call('POST', '/v1/auth/apple', {
    token: other.body.token,
    body: { identity_token: 'apple-sub-linking' },
  })
  assert.equal(clash.status, 409)
  assert.equal(clash.body.code, 'apple_in_use')
})

test('signing in with an invite code joins that baby in one step', async () => {
  // An owner with a baby to share.
  const owner = await call('POST', '/v1/pair/claim', {
    body: { secret: SECRET, display_name: 'Owner Two' },
  })
  const babyID = randomUUID().toUpperCase()
  const now = new Date().toISOString()
  const pushed = await call('POST', '/v1/sync/push', {
    token: owner.body.token,
    body: { babies: [{ id: babyID, name: 'Nora', updated_at: now }] },
  })
  assert.equal(pushed.status, 200)

  const invite = await call('POST', `/v1/babies/${babyID}/invites`, { token: owner.body.token })
  assert.equal(invite.status, 200)

  const joined = await signIn('apple-sub-joiner', {
    display_name: 'Joiner',
    invite_code: invite.body.code,
  })
  assert.equal(joined.status, 200)
  assert.equal(joined.body.baby?.id, babyID, 'lands straight on the shared baby')
  assert.equal(joined.body.babies.length, 1)
  assert.ok(joined.body.token)

  // The code is spent, exactly like the anonymous path.
  const reuse = await signIn('apple-sub-latecomer', { invite_code: invite.body.code })
  assert.equal(reuse.status, 410)
  assert.equal(reuse.body.code, 'used_code')
})

test('a bad invite code fails without leaving a stray account behind', async () => {
  const before = await signIn('apple-sub-strays', { invite_code: 'ZZZZZZ' })
  assert.equal(before.status, 404)

  // Signing in again with no code must look like a brand new account, which it
  // wouldn't if the failed attempt had already created one.
  const after = await signIn('apple-sub-strays')
  assert.equal(after.body.is_new_account, true)
})

test('sign-in is refused outright when the server has no audience configured', async () => {
  const otherDir = mkdtempSync(join(tmpdir(), 'babyfeed-noapple-'))
  const app = createApp({
    dbPath: join(otherDir, 'test.db'),
    setupSecret: SECRET,
    log: () => {},
    pairRateLimit: { limit: 1000, windowMs: 60_000 },
  })
  await new Promise((resolve) => app.server.listen(0, '127.0.0.1', resolve))
  const url = `http://127.0.0.1:${app.server.address().port}/v1/auth/apple`

  const response = await fetch(url, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ identity_token: 'anything' }),
  })
  assert.equal(response.status, 503)
  assert.equal((await response.json()).code, 'no_apple')

  app.server.close()
  rmSync(otherDir, { recursive: true, force: true })
})
