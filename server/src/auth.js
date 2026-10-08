// Pairing, tokens and the rate limits in front of them.
//
// There is no sign-in and no password. A caregiver exists because a phone was
// paired, and a phone gets its token in one of four ways:
//
//   1. Enrolling from the home network (POST /v1/pair/enroll). A phone on the
//      same Wi-Fi as the Mac mini sets itself up with nothing typed. It is
//      refused through a proxy and from loopback — where Caddy or a tunnel
//      would connect from — so "reachable from the internet" never becomes
//      "can mint an account".
//   2. An invite code from a phone already on a baby's log, shown as a QR.
//   3. A recovery phrase: a person's (covering every log they're on), or one of
//      the older per-baby keys.
//   4. The setup secret, for builds from before enrolment existed. Spent on
//      first use.
//
// A token with no memberships can read nothing: every route that names a baby
// checks membership first. Enrolment only ever creates an empty caregiver.

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

// ------------------------------------------------------------ home network

/**
 * Whether an address is on the home network: private IPv4 (10/8, 172.16/12,
 * 192.168/16), link-local (169.254/16, fe80::/10) or IPv6 unique-local
 * (fc00::/7).
 *
 * Loopback is deliberately not the home network unless asked for. Loopback is
 * where Caddy, a tunnel or anything else running on this Mac connects from, so
 * counting it would make "on the home network" mean "reached through whatever
 * happens to be forwarding to this machine". Tailscale's 100.64/10 isn't either:
 * it's a network you'd have to have set up on purpose, not the house's Wi-Fi.
 */
export function isLanAddress(address, { allowLoopback = false } = {}) {
  let text = String(address ?? '').trim().toLowerCase()
  if (!text) return false
  const zone = text.indexOf('%')
  if (zone !== -1) text = text.slice(0, zone)
  if (text.startsWith('::ffff:') && text.includes('.')) text = text.slice('::ffff:'.length)

  if (text.includes('.')) {
    const parts = text.split('.')
    if (parts.length !== 4 || !parts.every((part) => /^\d{1,3}$/.test(part))) return false
    const [a, b] = parts.map(Number)
    if (parts.some((part) => Number(part) > 255)) return false
    if (a === 127) return allowLoopback
    if (a === 10) return true
    if (a === 172 && b >= 16 && b <= 31) return true
    if (a === 192 && b === 168) return true
    if (a === 169 && b === 254) return true
    return false
  }

  if (text.includes(':')) {
    if (text === '::1') return allowLoopback
    const first = text.split(':')[0]
    if (!/^[0-9a-f]{1,4}$/.test(first)) return false
    const word = parseInt(first, 16)
    if ((word & 0xfe00) === 0xfc00) return true // fc00::/7, unique local
    if ((word & 0xffc0) === 0xfe80) return true // fe80::/10, link local
    return false
  }
  return false
}

export function isLoopbackAddress(address) {
  let text = String(address ?? '').trim().toLowerCase()
  if (text.startsWith('::ffff:')) text = text.slice('::ffff:'.length)
  return text === '::1' || /^127\.\d{1,3}\.\d{1,3}\.\d{1,3}$/.test(text)
}

/**
 * Headers a reverse proxy, tunnel or CDN adds. Any of them means the request
 * didn't come straight off the home network, whatever address it arrived from.
 */
const PROXY_HEADERS = ['x-forwarded-for', 'forwarded', 'x-real-ip', 'cf-connecting-ip', 'true-client-ip']

export function hasProxyHeaders(headers) {
  return PROXY_HEADERS.some((name) => headers?.[name] !== undefined)
}

/**
 * 'lan' is the default; 'lan+loopback' exists for the tests, which can only
 * connect over loopback. 'open' lets a phone set itself up from anywhere,
 * through Caddy: for sharing the server with other families. What a stranger
 * gets from it is an empty caregiver who can read nothing, behind a per-address
 * and a per-day limit; with sealed babies, nobody else's log is readable here
 * anyway, including by whoever runs the Mac.
 */
export const ENROLL_MODES = ['lan', 'off', 'lan+loopback', 'open']

/** Why this request may not enrol a new phone, or null when it may. */
export function enrollRefusal(req, mode) {
  if (mode === 'off') return 'enroll_off'
  if (mode === 'open') return null
  if (hasProxyHeaders(req.headers)) return 'enroll_lan_only'
  if (!isLanAddress(req.socket?.remoteAddress, { allowLoopback: mode === 'lan+loopback' })) {
    return 'enroll_lan_only'
  }
  return null
}

// ------------------------------------------------------------------ tokens

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
 * It exists for the endpoints that are reachable without a token — enrolling,
 * claiming with the setup secret, redeeming an invite code and redeeming a
 * recovery phrase. A six-character code from
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
