// Sign in with Apple, end to end over real HTTP.
//
// The verifier is injected, so these are about what the *server* does with a
// verified identity rather than about the crypto — apple.test.js covers that.
//
// Each test gets its own server and its own database, because the setup code
// is now single-use: a shared one would let the order tests happen to run in
// decide whether they pass.

import { test } from 'node:test'
import assert from 'node:assert/strict'
import { mkdtempSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { randomUUID } from 'node:crypto'
import { createApp } from '../src/server.js'

const SECRET = 'test-setup-secret'

/** Stands in for Apple: the "token" is just the subject to hand back. */
async function fakeVerify(identityToken) {
  if (!identityToken || String(identityToken).startsWith('bad')) {
    throw new Error("That sign-in token's signature doesn't check out.")
  }
  return { subject: String(identityToken), email: null, emailVerified: false, isPrivateEmail: false }
}

/** A throwaway server per test, so nothing leaks between them. */
async function withServer(run, { apple = fakeVerify } = {}) {
  const dir = mkdtempSync(join(tmpdir(), 'babyfeed-apple-'))
  const app = createApp({
    dbPath: join(dir, 'test.db'),
    setupSecret: SECRET,
    log: () => {},
    verifyAppleToken: apple,
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

  const signIn = (subject, extra = {}) =>
    call('POST', '/v1/auth/apple', { body: { identity_token: subject, ...extra } })

  const claim = (displayName = 'Owner') =>
    call('POST', '/v1/pair/claim', { body: { secret: SECRET, display_name: displayName } })

  try {
    await run({ call, signIn, claim })
  } finally {
    app.server.close()
    rmSync(dir, { recursive: true, force: true })
  }
}

/** An owner with a baby, which is the starting point for the sharing tests. */
async function ownerWithBaby({ call, claim }) {
  const owner = await claim('Owner')
  const babyID = randomUUID().toUpperCase()
  await call('POST', '/v1/sync/push', {
    token: owner.body.token,
    body: { babies: [{ id: babyID, name: 'Nora', updated_at: new Date().toISOString() }] },
  })
  return { owner, babyID }
}

test('a forged token is refused before anything is created', async () => {
  await withServer(async ({ call }) => {
    const result = await call('POST', '/v1/auth/apple', { body: { identity_token: 'bad-token' } })
    assert.equal(result.status, 401)
    assert.equal(result.body.code, 'bad_apple_token')
  })
})

test('signing in with a new Apple ID and nothing else creates no account', async () => {
  // The point of the whole rule: this endpoint answers to the internet, so it
  // must not be a sign-up form. An account comes from the setup code or an
  // invite, and from nowhere else.
  await withServer(async ({ signIn, claim }) => {
    const result = await signIn('apple-sub-stranger', { display_name: 'Stranger' })
    assert.equal(result.status, 403)
    assert.equal(result.body.code, 'needs_invite')

    // And it really created nothing: the setup code is still unclaimed.
    const owner = await claim()
    assert.equal(owner.status, 200, 'a refused sign-in must not have consumed the setup code')
  })
})

test('the setup code is spent once and cannot be replayed', async () => {
  await withServer(async ({ claim }) => {
    assert.equal((await claim('First')).status, 200)

    const again = await claim('Somebody Who Still Has The Code')
    assert.equal(again.status, 409)
    assert.equal(again.body.code, 'already_claimed')
  })
})

test('a phone paired the old way can attach an account and keep its token', async () => {
  await withServer(async ({ call, signIn, claim }) => {
    const paired = await claim('Owner')
    assert.equal(paired.status, 200)

    const linked = await call('POST', '/v1/auth/apple', {
      token: paired.body.token,
      body: { identity_token: 'apple-sub-linking' },
    })
    assert.equal(linked.status, 200)
    assert.equal(linked.body.user_id, paired.body.user_id, 'links rather than making a second caregiver')
    assert.equal(linked.body.token, null, 'the phone already has one; a second device row would be a stranger')

    // The original token still works.
    const me = await call('GET', '/v1/me', { token: paired.body.token })
    assert.equal(me.body.user_id, paired.body.user_id)

    // And this is the recovery that makes losing a phone survivable.
    const replacement = await signIn('apple-sub-linking', { device_name: 'Replacement iPhone' })
    assert.equal(replacement.status, 200)
    assert.equal(replacement.body.user_id, paired.body.user_id, 'same log on a new phone')
    assert.ok(replacement.body.token)
  })
})

test('the same Apple ID on a second phone returns the same account, not a new one', async () => {
  await withServer(async ({ call, signIn, claim }) => {
    const owner = await claim('Annette')
    await call('POST', '/v1/auth/apple', {
      token: owner.body.token,
      body: { identity_token: 'apple-sub-same' },
    })

    const second = await signIn('apple-sub-same', { device_name: 'iPad' })
    assert.equal(second.body.user_id, owner.body.user_id)
    assert.equal(second.body.is_new_account, false)
    assert.equal(second.body.display_name, 'Annette')
  })
})

test('a later sign-in cannot blank out the name Apple no longer sends', async () => {
  await withServer(async ({ call, signIn, claim }) => {
    const owner = await claim('Sam')
    await call('POST', '/v1/auth/apple', {
      token: owner.body.token,
      body: { identity_token: 'apple-sub-named' },
    })
    const again = await signIn('apple-sub-named', { display_name: '' })
    assert.equal(again.body.display_name, 'Sam')
  })
})

test('an Apple ID already attached to someone else is refused, not merged', async () => {
  await withServer(async ({ call, claim, signIn }) => {
    const { owner, babyID } = await ownerWithBaby({ call, claim })
    await call('POST', '/v1/auth/apple', {
      token: owner.body.token,
      body: { identity_token: 'apple-sub-owner' },
    })

    // A second caregiver, joined properly by invite.
    const invite = await call('POST', `/v1/babies/${babyID}/invites`, { token: owner.body.token })
    const joiner = await signIn('apple-sub-joiner', { invite_code: invite.body.code })
    assert.equal(joiner.status, 200)

    // Now they try to claim the owner's Apple ID.
    const clash = await call('POST', '/v1/auth/apple', {
      token: joiner.body.token,
      body: { identity_token: 'apple-sub-owner' },
    })
    assert.equal(clash.status, 409)
    assert.equal(clash.body.code, 'apple_in_use')
  })
})

test('signing in with an invite code joins that baby in one step', async () => {
  await withServer(async ({ call, claim, signIn }) => {
    const { owner, babyID } = await ownerWithBaby({ call, claim })
    const invite = await call('POST', `/v1/babies/${babyID}/invites`, { token: owner.body.token })
    assert.equal(invite.status, 200)

    const joined = await signIn('apple-sub-joiner', { display_name: 'Joiner', invite_code: invite.body.code })
    assert.equal(joined.status, 200)
    assert.equal(joined.body.baby?.id, babyID, 'lands straight on the shared baby')
    assert.equal(joined.body.babies.length, 1)
    assert.ok(joined.body.token)

    // Spent, exactly like the anonymous path.
    const reuse = await signIn('apple-sub-latecomer', { invite_code: invite.body.code })
    assert.equal(reuse.status, 410)
    assert.equal(reuse.body.code, 'used_code')
  })
})

test('a bad invite code fails without leaving a stray account behind', async () => {
  await withServer(async ({ signIn }) => {
    const refused = await signIn('apple-sub-strays', { invite_code: 'ZZZZZZ' })
    assert.equal(refused.status, 404)

    // Signing in again with no code must still be refused, which it wouldn't
    // be if the failed attempt had quietly created the account first.
    const after = await signIn('apple-sub-strays')
    assert.equal(after.status, 403)
    assert.equal(after.body.code, 'needs_invite')
  })
})

test('sign-in is refused outright when the server has no audience configured', async () => {
  const dir = mkdtempSync(join(tmpdir(), 'babyfeed-noapple-'))
  const app = createApp({ dbPath: join(dir, 'test.db'), setupSecret: SECRET, log: () => {} })
  await new Promise((resolve) => app.server.listen(0, '127.0.0.1', resolve))

  const response = await fetch(`http://127.0.0.1:${app.server.address().port}/v1/auth/apple`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ identity_token: 'anything' }),
  })
  assert.equal(response.status, 503)
  assert.equal((await response.json()).code, 'no_apple')

  app.server.close()
  rmSync(dir, { recursive: true, force: true })
})
