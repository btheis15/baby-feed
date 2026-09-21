// Apple identity token verification, against a key set this test controls.
//
// The real keys live at appleid.apple.com, so the verifier takes its fetcher as
// an argument and here it gets one backed by a throwaway RSA key. That lets the
// tests mint both tokens that should pass and the specific forgeries that must
// not — which is the half worth testing, since a verifier that accepts
// everything also passes every happy-path test.

import { test } from 'node:test'
import assert from 'node:assert/strict'
import { generateKeyPairSync, createSign, createHash, randomUUID } from 'node:crypto'
import { createAppleVerifier, hashNonce, AppleAuthError } from '../src/apple.js'

const AUDIENCE = 'com.babyfeed.BabyFeed'
const KID = 'test-key-1'

const { privateKey, publicKey } = generateKeyPairSync('rsa', { modulusLength: 2048 })

function jwks(kid = KID) {
  return [{ ...publicKey.export({ format: 'jwk' }), kid, alg: 'RS256', use: 'sig' }]
}

function base64url(value) {
  return Buffer.from(typeof value === 'string' ? value : JSON.stringify(value)).toString('base64url')
}

/** Mints a token the way Apple would, so a test can then bend one thing. */
function mintToken({ header = {}, payload = {}, signWith = privateKey, tamper = false } = {}) {
  const now = Math.floor(Date.now() / 1000)
  const fullHeader = { alg: 'RS256', kid: KID, ...header }
  const fullPayload = {
    iss: 'https://appleid.apple.com',
    aud: AUDIENCE,
    sub: '001234.abcdef.5678',
    iat: now,
    exp: now + 600,
    ...payload,
  }
  const signingInput = `${base64url(fullHeader)}.${base64url(fullPayload)}`
  const signer = createSign('RSA-SHA256')
  signer.update(signingInput)
  let signature = signer.sign(signWith)
  if (tamper) signature[0] ^= 0xff
  return `${signingInput}.${signature.toString('base64url')}`
}

function verifier(fetchKeys = async () => jwks()) {
  return createAppleVerifier({ audience: AUDIENCE, fetchKeys })
}

test('a well-formed token yields the Apple subject', async () => {
  const verify = verifier()
  const result = await verify(mintToken({ payload: { email: 'nobody@example.com', email_verified: 'true' } }))
  assert.equal(result.subject, '001234.abcdef.5678')
  assert.equal(result.email, 'nobody@example.com')
  assert.equal(result.emailVerified, true)
})

test('the nonce must match the one the phone used', async () => {
  const verify = verifier()
  const rawNonce = randomUUID()
  const token = mintToken({ payload: { nonce: hashNonce(rawNonce) } })

  const result = await verify(token, { rawNonce })
  assert.equal(result.subject, '001234.abcdef.5678')

  await assert.rejects(() => verify(token, { rawNonce: randomUUID() }), AppleAuthError)
})

test('the nonce is the hash of the raw value, not the raw value', async () => {
  const rawNonce = 'a-nonce'
  const expected = createHash('sha256').update(rawNonce).digest('hex')
  assert.equal(hashNonce(rawNonce), expected)

  const verify = verifier()
  // A token carrying the unhashed nonce is not what Apple sends back.
  await assert.rejects(
    () => verify(mintToken({ payload: { nonce: rawNonce } }), { rawNonce }),
    AppleAuthError)
})

test('a token minted for another app is refused', async () => {
  const verify = verifier()
  await assert.rejects(
    () => verify(mintToken({ payload: { aud: 'com.someone.else' } })),
    AppleAuthError)
})

test('a token from the wrong issuer is refused', async () => {
  const verify = verifier()
  await assert.rejects(
    () => verify(mintToken({ payload: { iss: 'https://evil.example.com' } })),
    AppleAuthError)
})

test('an expired token is refused', async () => {
  const verify = verifier()
  const now = Math.floor(Date.now() / 1000)
  await assert.rejects(
    () => verify(mintToken({ payload: { iat: now - 7200, exp: now - 3600 } })),
    AppleAuthError)
})

test('a tampered signature is refused', async () => {
  const verify = verifier()
  await assert.rejects(() => verify(mintToken({ tamper: true })), AppleAuthError)
})

test('a token signed by a key Apple does not publish is refused', async () => {
  const other = generateKeyPairSync('rsa', { modulusLength: 2048 })
  const verify = verifier()
  await assert.rejects(() => verify(mintToken({ signWith: other.privateKey })), AppleAuthError)
})

test('"alg: none" is refused rather than trusted', async () => {
  const verify = verifier()
  const header = base64url({ alg: 'none', kid: KID })
  const payload = base64url({ iss: 'https://appleid.apple.com', aud: AUDIENCE, sub: 'x', exp: 9999999999 })
  await assert.rejects(() => verify(`${header}.${payload}.`), AppleAuthError)
})

test('rubbish in place of a token is refused', async () => {
  const verify = verifier()
  for (const bad of ['', 'not-a-token', 'a.b', null, undefined]) {
    await assert.rejects(() => verify(bad), AppleAuthError)
  }
})

test('an unknown key id refetches once before giving up', async () => {
  let fetches = 0
  // Apple rotated: the first key set is stale, the second has the key.
  const verify = createAppleVerifier({
    audience: AUDIENCE,
    fetchKeys: async () => {
      fetches += 1
      return fetches === 1 ? jwks('some-older-key') : jwks()
    },
  })
  const result = await verify(mintToken())
  assert.equal(result.subject, '001234.abcdef.5678')
  assert.equal(fetches, 2, 'should have refetched exactly once')
})

test('a genuinely unknown key id fails without refetching forever', async () => {
  let fetches = 0
  const verify = createAppleVerifier({
    audience: AUDIENCE,
    fetchKeys: async () => {
      fetches += 1
      return jwks('never-the-right-one')
    },
  })
  await assert.rejects(() => verify(mintToken()), AppleAuthError)
  assert.equal(fetches, 2, 'one refetch, then stop')
})

test('a token with a nonce but no nonce supplied is refused', async () => {
  const verify = verifier()
  await assert.rejects(
    () => verify(mintToken({ payload: { nonce: hashNonce('something') } })),
    AppleAuthError)
})
