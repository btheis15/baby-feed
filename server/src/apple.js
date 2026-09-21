// Verifying a Sign in with Apple identity token.
//
// The phone does the whole sign-in with Apple and hands us the identity token
// it got back. That token is a JWT signed by Apple, so the only thing this
// server has to do — and the only thing it must not get wrong — is check the
// signature against Apple's published keys and then check the claims say what
// we think they say.
//
// Doing it here rather than trusting the phone matters: the token arrives over
// the network from something claiming to be our app, and a forged one would
// otherwise be a free account. Everything below is `node:crypto`, so the server
// still has no dependencies.

import { createHash, createPublicKey, verify as verifySignature, timingSafeEqual } from 'node:crypto'

const APPLE_ISSUER = 'https://appleid.apple.com'
const APPLE_KEYS_URL = 'https://appleid.apple.com/auth/keys'

/** Apple rotates signing keys; an hour is well inside how often they change. */
const KEY_CACHE_MS = 60 * 60 * 1000

/** Clocks drift. A minute each way is generous and still useless to an attacker. */
const CLOCK_SKEW_SECONDS = 60

function decodeBase64URL(text) {
  return Buffer.from(String(text), 'base64url')
}

function decodeJSONSegment(segment) {
  try {
    return JSON.parse(decodeBase64URL(segment).toString('utf8'))
  } catch {
    return null
  }
}

/** Compares without leaking where two strings first differ. */
function constantTimeEquals(a, b) {
  const left = Buffer.from(String(a ?? ''))
  const right = Buffer.from(String(b ?? ''))
  if (left.length !== right.length || left.length === 0) return false
  return timingSafeEqual(left, right)
}

/** What the phone puts in the request is the hash, not the nonce itself. */
export function hashNonce(rawNonce) {
  return createHash('sha256').update(String(rawNonce)).digest('hex')
}

export class AppleAuthError extends Error {
  constructor(message) {
    super(message)
    this.name = 'AppleAuthError'
  }
}

/**
 * @param audience  The app's bundle identifier. Apple puts it in `aud`, and it
 *                  is what stops a token minted for somebody else's app from
 *                  working here.
 * @param fetchKeys Injected so the tests can supply their own key set instead
 *                  of reaching Apple; production leaves it alone.
 */
export function createAppleVerifier({ audience, fetchKeys = defaultFetchKeys } = {}) {
  if (!audience) throw new Error('createAppleVerifier needs the app bundle identifier as audience')

  let cache = { keys: [], fetchedAt: 0 }

  async function keysFor(kid, { allowRefresh = true } = {}) {
    const fresh = Date.now() - cache.fetchedAt < KEY_CACHE_MS
    if (!fresh || !cache.keys.length) {
      cache = { keys: await fetchKeys(), fetchedAt: Date.now() }
    }
    const found = cache.keys.find((key) => key.kid === kid)
    if (found) return found
    // An unknown kid usually means Apple rotated keys inside the cache window
    // rather than that the token is bogus, so refetch once before refusing.
    if (allowRefresh) {
      cache = { keys: await fetchKeys(), fetchedAt: Date.now() }
      return keysFor(kid, { allowRefresh: false })
    }
    return null
  }

  /**
   * Returns the caregiver's stable Apple identifier plus whatever else the
   * token carried. Throws AppleAuthError on anything that doesn't check out.
   */
  return async function verifyIdentityToken(identityToken, { rawNonce } = {}) {
    const parts = String(identityToken ?? '').split('.')
    if (parts.length !== 3) throw new AppleAuthError('That sign-in token is malformed.')

    const [headerSegment, payloadSegment, signatureSegment] = parts
    const header = decodeJSONSegment(headerSegment)
    if (!header) throw new AppleAuthError('That sign-in token is malformed.')
    // Pinned: leaving the algorithm up to the token is how you get "alg: none".
    if (header.alg !== 'RS256') throw new AppleAuthError('Unexpected sign-in token algorithm.')

    const jwk = await keysFor(header.kid)
    if (!jwk) throw new AppleAuthError("That sign-in token wasn't signed by a key Apple publishes.")

    const signed = Buffer.from(`${headerSegment}.${payloadSegment}`, 'utf8')
    const signature = decodeBase64URL(signatureSegment)
    const publicKey = createPublicKey({ key: jwk, format: 'jwk' })
    if (!verifySignature('RSA-SHA256', signed, publicKey, signature)) {
      throw new AppleAuthError("That sign-in token's signature doesn't check out.")
    }

    const payload = decodeJSONSegment(payloadSegment)
    if (!payload) throw new AppleAuthError('That sign-in token is malformed.')

    if (payload.iss !== APPLE_ISSUER) throw new AppleAuthError('That sign-in token came from the wrong issuer.')

    // `aud` is a string for a native app, but accept the array form too rather
    // than break if Apple ever sends one.
    const audiences = Array.isArray(payload.aud) ? payload.aud : [payload.aud]
    if (!audiences.includes(audience)) {
      throw new AppleAuthError('That sign-in token was issued for a different app.')
    }

    const now = Math.floor(Date.now() / 1000)
    if (typeof payload.exp !== 'number' || payload.exp + CLOCK_SKEW_SECONDS < now) {
      throw new AppleAuthError('That sign-in token has expired. Try again.')
    }
    if (typeof payload.iat === 'number' && payload.iat - CLOCK_SKEW_SECONDS > now) {
      throw new AppleAuthError('That sign-in token is dated in the future.')
    }

    // The nonce is what stops a token captured from one sign-in being replayed
    // into another. The phone hashes it before handing it to Apple, so what
    // comes back is the hash of what the phone tells us it used.
    if (rawNonce !== undefined && rawNonce !== null) {
      if (!constantTimeEquals(payload.nonce, hashNonce(rawNonce))) {
        throw new AppleAuthError("That sign-in couldn't be matched to this device's request.")
      }
    } else if (payload.nonce) {
      throw new AppleAuthError('That sign-in token expects a nonce this request did not supply.')
    }

    if (!payload.sub) throw new AppleAuthError('That sign-in token has no subject.')

    return {
      subject: String(payload.sub),
      email: payload.email ? String(payload.email) : null,
      emailVerified: payload.email_verified === true || payload.email_verified === 'true',
      isPrivateEmail: payload.is_private_email === true || payload.is_private_email === 'true',
    }
  }
}

async function defaultFetchKeys() {
  const response = await fetch(APPLE_KEYS_URL, { signal: AbortSignal.timeout(10_000) })
  if (!response.ok) throw new AppleAuthError(`Couldn't reach Apple to check the sign-in (${response.status}).`)
  const body = await response.json()
  if (!Array.isArray(body?.keys)) throw new AppleAuthError('Apple returned a key set this server did not understand.')
  return body.keys
}
