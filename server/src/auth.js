// Pairing, tokens and the rate limits in front of them.
//
// There is no sign-in. A user exists because a phone was paired, and a phone is
// paired in exactly two ways:
//
//   1. The first phone, once, with the setup secret printed by setup.sh. That
//      phone becomes the owner.
//   2. Every phone after that, with a six-character invite code the owner's
//      phone generates and shows as a QR.
//
// That is deliberately the whole of it. An open "create an account" endpoint on
// a public hostname is a thing to defend; not having one is not.

import { randomBytes, createHash, timingSafeEqual } from 'node:crypto'

/** No I, O, 0 or 1 — these get read aloud and typed in at 3 a.m. */
const CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'
export const CODE_LENGTH = 6 // matches SyncMerge.inviteCodeLength

export function newInviteCode() {
  const bytes = randomBytes(CODE_LENGTH * 2)
  let code = ''
  for (let i = 0; code.length < CODE_LENGTH; i++) {
    code += CODE_ALPHABET[bytes[i] % CODE_ALPHABET.length]
  }
  return code
}

/** Mirrors SyncMerge.normalizedInviteCode: "abc 123" -> "ABC123". */
export function normalizeCode(input) {
  return String(input ?? '').toUpperCase().replace(/[^A-Z0-9]/g, '')
}

export function newToken() {
  return randomBytes(32).toString('base64url')
}

/**
 * The recovery key's shape, so the phone and the server agree on what counts
 * as the same key. Six groups of four from the same unambiguous alphabet as an
 * invite code — 24 characters, about 120 bits, and no character anyone has to
 * squint at when they're copying it onto paper at 3 a.m.
 *
 * The server never sees a key it didn't already have the hash of: the phone
 * makes it, keeps it, and sends the hash. So this is only for normalising what
 * somebody types back in.
 */
export const RECOVERY_KEY_GROUPS = 6
export const RECOVERY_KEY_GROUP_SIZE = 4
export const RECOVERY_KEY_LENGTH = RECOVERY_KEY_GROUPS * RECOVERY_KEY_GROUP_SIZE

/** "abcd efgh-JKLM…" -> "ABCDEFGHJKLM…", so dashes and spaces don't matter. */
export function normalizeRecoveryKey(input) {
  return normalizeCode(input)
}

export function isPlausibleRecoveryKey(input) {
  const key = normalizeRecoveryKey(input)
  if (key.length !== RECOVERY_KEY_LENGTH) return false
  return [...key].every((character) => CODE_ALPHABET.includes(character))
}

export function hashToken(token) {
  return createHash('sha256').update(token).digest('hex')
}

export function secretsMatch(a, b) {
  const left = Buffer.from(String(a ?? ''))
  const right = Buffer.from(String(b ?? ''))
  if (left.length !== right.length || left.length === 0) return false
  return timingSafeEqual(left, right)
}

/**
 * Resolves `Authorization: Bearer <token>` to a user, and records the device as
 * seen. Returns null for anything unknown or revoked.
 */
export function authenticate(db, header) {
  const match = /^Bearer\s+(.+)$/i.exec(header ?? '')
  if (!match) return null
  const device = db
    .prepare('SELECT * FROM devices WHERE token_hash = ? AND revoked_at IS NULL')
    .get(hashToken(match[1].trim()))
  if (!device) return null
  const user = db.prepare('SELECT * FROM users WHERE id = ?').get(device.user_id)
  if (!user) return null
  db.prepare('UPDATE devices SET last_seen_at = ? WHERE id = ?')
    .run(new Date().toISOString(), device.id)
  return { user, device }
}

/**
 * A fixed-window limiter, in memory, keyed by client address.
 *
 * It exists for the two endpoints that are reachable without a token — claiming
 * with the setup secret and redeeming an invite code. A six-character code from
 * a 32-letter alphabet is a billion possibilities; at ten guesses a minute it
 * would take a couple of centuries, which is the point. Sync traffic from a
 * paired phone is not limited: a caregiver catching up after a flight can
 * legitimately push a hundred rows at once.
 */
export function createRateLimiter({ limit, windowMs }) {
  const hits = new Map()
  return function allow(key) {
    const now = Date.now()
    const entry = hits.get(key)
    if (!entry || now >= entry.resetAt) {
      hits.set(key, { count: 1, resetAt: now + windowMs })
      if (hits.size > 5000) {
        for (const [k, v] of hits) if (now >= v.resetAt) hits.delete(k)
      }
      return true
    }
    entry.count += 1
    return entry.count <= limit
  }
}
