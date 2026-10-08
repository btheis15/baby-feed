// The HTTP API. Node's own http module — no framework, because the routing
// here is a couple of dozen paths and a framework would be the only dependency.
//
// Everything lives under /v1. Every route except /v1/health, the pairing routes
// (enrol, claim, invite) and /v1/recover requires a device token, and every
// route that names a baby checks membership of that baby before it reads or
// writes a single row. That check is the whole access-control story: there is
// no "public" data, and a brand-new caregiver can see nothing until invited.

import { createServer } from 'node:http'
import { randomUUID } from 'node:crypto'
import { openDatabase, primeStamp, serverID, stamp, schemaVersion, ROW_TABLES } from './db.js'
import {
  authenticate, createRateLimiter, hashToken, newInviteCode, newToken,
  normalizeCode, secretsMatch, CODE_LENGTH,
  isPlausibleRecoveryKey, normalizeRecoveryKey,
  enrollRefusal, isLoopbackAddress, ENROLL_MODES,
} from './auth.js'
import {
  normalizeRow, upsertRow, rowsSince, RowError,
  normalizeSealedRow, upsertSealedRow, sealedRowsSince, sealBabyRow,
} from './sync.js'

const MAX_BODY_BYTES = 2 * 1024 * 1024 // a very long catch-up push is ~100 KB
const MAX_PULL_LIMIT = 1000
const DEFAULT_PULL_LIMIT = 500
const KEY_HASH_RE = /^[a-f0-9]{64}$/

// What this server can do, so a newer app can tell an up-to-date server from an
// older one before relying on a behaviour — sending a token with an invite to a
// server that predates join_as_member would mint a second identity.
const API_VERSION = 2
const FEATURES = ['enroll', 'join_as_member', 'member_invites', 'account_keys', 'sealed']

/**
 * Sent by every request from a build that can read sealed (end-to-end
 * encrypted) babies. One without it is never shown one: it would list a baby
 * with no name and pull rows it can't open.
 */
const SEALED_HEADER = 'x-babyfeed-sealed'
const supportsSealed = (req) => req.headers[SEALED_HEADER] === '1'
/** A baby key locked with a phrase: 32 bytes plus AES-GCM's nonce and tag, in base64. */
const WRAPPED_KEY_RE = /^[A-Za-z0-9+/_-]{40,200}={0,2}$/
/** A caregiver's name, sealed with the baby's key. */
const SEALED_NAME_RE = /^[A-Za-z0-9+/_-]{20,2000}={0,2}$/

class HttpError extends Error {
  constructor(status, message, code) {
    super(message)
    this.status = status
    this.code = code
  }
}

function json(res, status, body) {
  const payload = JSON.stringify(body)
  res.writeHead(status, {
    'content-type': 'application/json; charset=utf-8',
    'content-length': Buffer.byteLength(payload),
    'cache-control': 'no-store',
  })
  res.end(payload)
}

async function readJSON(req) {
  const chunks = []
  let size = 0
  for await (const chunk of req) {
    size += chunk.length
    if (size > MAX_BODY_BYTES) throw new HttpError(413, 'That request is too large.')
    chunks.push(chunk)
  }
  if (!size) return {}
  try {
    return JSON.parse(Buffer.concat(chunks).toString('utf8'))
  } catch {
    throw new HttpError(400, "That request body isn't valid JSON.")
  }
}

export function createApp({
  dbPath, setupSecret, log = console.log,
  // Only raised by the tests, which come from one address and would otherwise
  // rate-limit themselves rather than the thing they mean to check.
  pairRateLimit = { limit: 10, windowMs: 60_000 },
  // Who may set a brand-new phone up with nothing typed: 'lan' (phones on the
  // home network), 'off' (nobody — invites and recovery phrases only), or
  // 'lan+loopback' (also this machine; the tests need it).
  enroll = 'lan',
  enrollRateLimit = { limit: 5, windowMs: 60_000 },
  // With enroll 'open', the most new phones a day from anywhere, all told: a
  // ceiling on what a stranger who finds the address can add to this Mac.
  enrollDailyLimit = 50,
  // The address phones use away from home (the DuckDNS one, through Caddy),
  // told to every phone so the QR it shows works from anywhere.
  publicURL = '',
}) {
  if (!ENROLL_MODES.includes(enroll)) {
    throw new Error(`enroll must be one of ${ENROLL_MODES.join(', ')}, not "${enroll}"`)
  }
  const db = openDatabase(dbPath)
  primeStamp(db)
  const SERVER_ID = serverID(db)

  // Only the unauthenticated routes are limited; see auth.js for why.
  const pairLimiter = createRateLimiter(pairRateLimit)
  const enrollLimiter = createRateLimiter(enrollRateLimit)
  const enrollDailyLimiter = createRateLimiter({ limit: enrollDailyLimit, windowMs: 24 * 60 * 60_000 })

  function requireUser(req) {
    const auth = authenticate(db, req.headers.authorization)
    if (!auth) throw new HttpError(401, 'This phone is not paired with the server.', 'unpaired')
    return auth
  }

  function membership(babyID, userID) {
    return db.prepare('SELECT * FROM members WHERE baby_id = ? AND user_id = ?')
      .get(babyID, userID)
  }

  function requireMember(babyID, userID) {
    const member = membership(babyID, userID)
    // 404 rather than 403: an id you have no part in should look like an id
    // that doesn't exist, so the API can't be used to test for real babies.
    if (!member) throw new HttpError(404, "That baby isn't shared with you.", 'not_a_member')
    return member
  }

  function requireOwner(babyID, userID) {
    const member = requireMember(babyID, userID)
    if (member.role !== 'owner') {
      throw new HttpError(403, 'Only the caregiver who started the shared log can do that.', 'not_owner')
    }
    return member
  }

  function babyPayload(babyID) {
    const baby = db.prepare(
      `SELECT id, name, birth_date, sex, due_date, created_by, updated_at, deleted_at, server_updated_at, sealed
       FROM babies WHERE id = ?`).get(babyID)
    return baby ? { ...baby, sealed: baby.sealed === 1 } : null
  }

  function isSealedBaby(babyID) {
    return db.prepare('SELECT sealed FROM babies WHERE id = ?').get(babyID)?.sealed === 1
  }

  /** A sealed baby, asked for by a build that can't open it. */
  function requireCanRead(req, babyID) {
    if (isSealedBaby(babyID) && !supportsSealed(req)) {
      throw new HttpError(409, 'This log is encrypted. Update Baby Feed on this phone to open it.', 'app_update_needed')
    }
  }

  function membersOf(babyID) {
    return db.prepare(
      `SELECT baby_id, user_id, role, display_name, sealed_name, joined_at FROM members
       WHERE baby_id = ? ORDER BY joined_at ASC`).all(babyID)
  }

  /** Checks an invite is real, unexpired and unspent. */
  function requireUsableInvite(rawCode) {
    const code = normalizeCode(rawCode)
    if (code.length !== CODE_LENGTH) {
      throw new HttpError(400, `An invite code is ${CODE_LENGTH} letters and numbers.`, 'bad_code')
    }
    const invite = db.prepare('SELECT * FROM invites WHERE code = ?').get(code)
    if (!invite || invite.revoked_at) throw new HttpError(404, "That invite code isn't valid.", 'bad_code')
    if (new Date(invite.expires_at).getTime() < Date.now()) {
      throw new HttpError(410, 'That invite code has expired. Ask for a new one.', 'expired_code')
    }
    if (invite.uses >= invite.max_uses) {
      throw new HttpError(410, 'That invite code has already been used.', 'used_code')
    }
    return invite
  }

  /**
   * Adds a caregiver to the invite's baby and spends one use of the code —
   * only if it actually added them, so a caregiver re-scanning a code for a log
   * they're already on can't use up somebody else's invite. Caller owns the
   * transaction, because it may also create the caregiver in the same one.
   */
  function redeemInvite(invite, userID, displayName, now, at) {
    if (membership(invite.baby_id, userID)) return false
    db.prepare(`INSERT INTO members (baby_id, user_id, role, display_name, joined_at, server_ms)
                VALUES (?, ?, 'caregiver', ?, ?, ?)`)
      .run(invite.baby_id, userID, isSealedBaby(invite.baby_id) ? '' : displayName, now, at.ms)
    db.prepare('UPDATE invites SET uses = uses + 1 WHERE code = ?').run(invite.code)
    return true
  }

  function issueDevice(userID, deviceName) {
    const token = newToken()
    const now = new Date().toISOString()
    db.prepare(`INSERT INTO devices (id, user_id, token_hash, name, created_at)
                VALUES (?, ?, ?, ?, ?)`)
      .run(randomUUID().toUpperCase(), userID, hashToken(token), String(deviceName ?? '').slice(0, 120), now)
    return token
  }

  /**
   * Every log this person is on. A sealed one comes with this person's locked
   * copy of its key, when they've made one, and is left out altogether for a
   * build that couldn't open it.
   */
  function membershipsOf(userID, req) {
    const rows = db.prepare(
      `SELECT m.role, m.sealed_name, b.id, b.name, b.birth_date, b.sex, b.due_date, b.created_by,
              b.updated_at, b.deleted_at, b.server_updated_at, b.sealed, k.wrapped AS wrapped_key
       FROM members m JOIN babies b ON b.id = m.baby_id
       LEFT JOIN baby_keys k ON k.baby_id = b.id AND k.user_id = m.user_id
       WHERE m.user_id = ? ORDER BY b.name`).all(userID)
    return rows
      .filter((row) => row.sealed !== 1 || supportsSealed(req))
      .map((row) => ({ ...row, sealed: row.sealed === 1 }))
  }

  /** Whether this person has a recovery phrase — never the phrase, never the hash. */
  function recoveryKeyStatus(userID) {
    const row = db.prepare('SELECT created_at, last_used_at FROM account_keys WHERE user_id = ?').get(userID)
    return { exists: Boolean(row), created_at: row?.created_at ?? null, last_used_at: row?.last_used_at ?? null }
  }

  /**
   * What a phone gets back from joining or recovering. `baby` and `members`
   * describe one log, for builds that only understood one; `babies` is every
   * log this caregiver is now on. `token` is null when the phone keeps the
   * token it already has.
   */
  function pairingResponse(token, userID, babyID, req) {
    const user = db.prepare('SELECT id, display_name FROM users WHERE id = ?').get(userID)
    const babies = membershipsOf(userID, req)
    const first = babyID ?? babies[0]?.id ?? null
    return {
      token,
      user_id: userID,
      display_name: user?.display_name ?? '',
      baby: first ? babyPayload(first) : null,
      members: first ? membersOf(first) : [],
      babies,
      server_id: SERVER_ID,
    }
  }

  function requireKeyHash(value) {
    const keyHash = String(value ?? '')
    if (!KEY_HASH_RE.test(keyHash)) {
      throw new HttpError(400, 'A recovery key hash is 64 hex characters.', 'bad_key_hash')
    }
    return keyHash
  }

  function isJSONRequest(req) {
    return String(req.headers['content-type'] ?? '').toLowerCase().startsWith('application/json')
  }

  const routes = []
  const route = (method, pattern, handler) => {
    const names = []
    const regex = new RegExp('^' + pattern.replace(/:([a-zA-Z]+)/g, (_, name) => {
      names.push(name)
      return '([^/]+)'
    }) + '$')
    routes.push({ method, regex, names, handler })
  }

  // ---------------------------------------------------------------- health

  route('GET', '/v1/health', (req) => ({
    ok: true,
    service: 'babyfeed-server',
    api: API_VERSION,
    server_id: SERVER_ID,
    features: FEATURES,
    // What this server can store, so an app with a newer kind of row can say
    // "your Mac mini needs an update" instead of retrying it forever.
    tables: ROW_TABLES,
    schema_version: schemaVersion(db),
    enroll,
    // Whether a new phone could set itself up from where this request came
    // from, so the app can say "connect to your home Wi-Fi" instead of failing.
    enroll_available: enrollRefusal(req, enroll) === null,
    // Where phones reach this server from outside the house, when it can be.
    public_url: publicURL || null,
    server_time: new Date().toISOString(),
    paired_devices: db.prepare('SELECT COUNT(*) AS n FROM devices WHERE revoked_at IS NULL').get().n,
    babies: db.prepare('SELECT COUNT(*) AS n FROM babies WHERE deleted_at IS NULL').get().n,
    feeds: db.prepare('SELECT COUNT(*) AS n FROM feeds WHERE deleted_at IS NULL').get().n,
  }))

  // ---------------------------------------------------------------- pairing

  // A new phone on the home network, setting itself up with nothing typed.
  //
  // This is the one route that makes a caregiver out of nothing, so it only
  // answers to a phone that is plainly in the house: a private address on the
  // socket, no proxy headers, and not loopback (which is where Caddy or a
  // tunnel would connect from — see auth.js). What it makes is an empty
  // caregiver who can see nothing until they push a baby of their own or are
  // invited to one, so a stranger on the Wi-Fi gains nothing but a login.
  //
  // JSON only: a web page on the same Wi-Fi can send a form or text/plain
  // cross-site without asking, but not application/json.
  route('POST', '/v1/pair/enroll', async (req, res, params, ctx) => {
    const refusal = enrollRefusal(req, enroll)
    if (refusal === 'enroll_off') {
      throw new HttpError(403, "This server isn't setting up new phones. Ask for an invite, or use your recovery phrase.", 'enroll_off')
    }
    if (refusal) {
      throw new HttpError(403, 'A new phone can only set itself up on the same Wi-Fi as the server.', 'enroll_lan_only')
    }
    // Open to anywhere, requests come through Caddy, so the forwarded address
    // is the one to limit; on the home network it's the socket's own.
    const enrollKey = enroll === 'open' ? ctx.clientKey : ctx.socketKey
    if (!enrollLimiter(enrollKey)) throw new HttpError(429, 'Too many attempts. Wait a minute.')
    if (enroll === 'open' && !enrollDailyLimiter('all')) {
      throw new HttpError(429, 'This server has set up as many new phones as it will today. Try again tomorrow.', 'enroll_full')
    }
    if (!isJSONRequest(req)) throw new HttpError(415, 'Send JSON.', 'bad_content_type')
    const body = await readJSON(req)

    // Already paired: nothing to create. Idempotent, so retrying after a
    // dropped response can't leave a phone with two identities.
    const caller = authenticate(db, req.headers.authorization)
    if (caller) {
      return { token: null, user_id: caller.user.id, display_name: caller.user.display_name, server_id: SERVER_ID }
    }

    // The person's recovery phrase can ride along, so a phone is never paired
    // without one. A hash that's already here is refused, never taken as proof
    // of who this is: the phrase itself is the proof, and it goes to /v1/recover.
    const keyHash = body.key_hash === undefined || body.key_hash === null || body.key_hash === ''
      ? null
      : requireKeyHash(body.key_hash)
    if (keyHash && db.prepare('SELECT 1 FROM account_keys WHERE key_hash = ?').get(keyHash)) {
      throw new HttpError(409,
        'That recovery phrase already belongs to someone on this server. Restore with it instead.',
        'key_exists')
    }

    const displayName = String(body.display_name ?? '').slice(0, 200)
    const userID = randomUUID().toUpperCase()
    const now = new Date().toISOString()
    let token
    db.exec('BEGIN')
    try {
      db.prepare('INSERT INTO users (id, display_name, created_at) VALUES (?, ?, ?)')
        .run(userID, displayName, now)
      if (keyHash) {
        db.prepare('INSERT INTO account_keys (user_id, key_hash, created_at) VALUES (?, ?, ?)')
          .run(userID, keyHash, now)
      }
      token = issueDevice(userID, body.device_name)
      db.exec('COMMIT')
    } catch (error) {
      db.exec('ROLLBACK')
      throw error
    }
    log(`[pair] "${displayName || 'unnamed'}" enrolled from ${req.socket.remoteAddress} (${userID})`)
    return { token, user_id: userID, display_name: displayName, server_id: SERVER_ID }
  })

  // The first phone, for builds from before enrolment. Newer builds enrol from
  // the home network instead and never ask anybody to type this; the route
  // stays so an older build on a freshly reset server can still get going.
  //
  // The setup secret is spent the moment somebody claims it. It used to be replayable, which
  // meant the code — a short string that gets read aloud, sits in a terminal
  // buffer and lives in a .env — could be used again by anyone who still had
  // it, over and over, on a hostname that answers to the whole internet. Those
  // extra accounts couldn't read anything (membership is per baby and a fresh
  // claim has none), but a server that hands out accounts to a replayed
  // password is not a server worth arguing about.
  //
  // Nothing is lost by spending it: a second caregiver arrives on an invite,
  // and an owner who lost every phone comes back with the recovery key.
  route('POST', '/v1/pair/claim', async (req, res, params, ctx) => {
    if (!pairLimiter(ctx.clientKey)) throw new HttpError(429, 'Too many attempts. Wait a minute.')
    const body = await readJSON(req)
    if (!setupSecret) throw new HttpError(503, 'No setup secret is configured on the server.')
    if (!secretsMatch(body.secret, setupSecret)) {
      throw new HttpError(401, "That setup code doesn't match.", 'bad_secret')
    }
    if (db.prepare('SELECT 1 FROM users LIMIT 1').get()) {
      throw new HttpError(409,
        'This server has already been set up. Scan the QR from a phone that has the log, or use the recovery key.',
        'already_claimed')
    }
    const displayName = String(body.display_name ?? '').slice(0, 200)
    const userID = randomUUID().toUpperCase()
    const now = new Date().toISOString()
    db.prepare('INSERT INTO users (id, display_name, created_at) VALUES (?, ?, ?)')
      .run(userID, displayName, now)
    const token = issueDevice(userID, body.device_name)
    log(`[pair] claimed by "${displayName || 'unnamed'}" (${userID})`)
    return { token, user_id: userID, display_name: displayName }
  })

  // Joining a log from an invite — a scanned QR, a sent link, six characters.
  //
  // A phone that's already paired sends its token, and joins as the caregiver
  // it already is. Minting a fresh identity here is what used to cost a phone
  // its first baby when it joined a second: the new token replaced the old
  // one, and the old logs stopped recognising it. A phone with no token (or a
  // revoked one) gets a new caregiver, as before.
  route('POST', '/v1/pair/invite', async (req, res, params, ctx) => {
    if (!pairLimiter(ctx.clientKey)) throw new HttpError(429, 'Too many attempts. Wait a minute.')
    const body = await readJSON(req)
    const code = normalizeCode(body.code)
    if (code.length !== CODE_LENGTH) {
      throw new HttpError(400, `An invite code is ${CODE_LENGTH} letters and numbers.`, 'bad_code')
    }
    const caller = authenticate(db, req.headers.authorization)
    const offeredName = String(body.display_name ?? '').slice(0, 200)

    // Re-scanning a code for a log you're already on is a success whatever
    // state the code is in — a screenshot, a second scan — and spends nothing.
    if (caller) {
      const existing = db.prepare('SELECT * FROM invites WHERE code = ?').get(code)
      if (existing && !existing.revoked_at && membership(existing.baby_id, caller.user.id)) {
        return pairingResponse(null, caller.user.id, existing.baby_id, req)
      }
    }

    const invite = requireUsableInvite(code)
    const baby = db.prepare('SELECT deleted_at FROM babies WHERE id = ?').get(invite.baby_id)
    if (!baby || baby.deleted_at) {
      throw new HttpError(410, 'The log that invite was for is gone.', 'baby_gone')
    }
    // Before spending the code: an older build couldn't open the log it joined.
    requireCanRead(req, invite.baby_id)

    const now = new Date().toISOString()
    const at = stamp()

    if (caller) {
      db.exec('BEGIN')
      try {
        // A phone that never got a name (enrolled before anyone typed one)
        // takes the one offered here, so its rows aren't logged by nobody.
        if (!caller.user.display_name && offeredName) {
          db.prepare('UPDATE users SET display_name = ? WHERE id = ?').run(offeredName, caller.user.id)
        }
        redeemInvite(invite, caller.user.id, caller.user.display_name || offeredName, now, at)
        db.exec('COMMIT')
      } catch (error) {
        db.exec('ROLLBACK')
        throw error
      }
      log(`[pair] "${caller.user.display_name || offeredName || 'unnamed'}" (already paired) joined baby ${invite.baby_id}`)
      return pairingResponse(null, caller.user.id, invite.baby_id, req)
    }

    const userID = randomUUID().toUpperCase()
    let token
    db.exec('BEGIN')
    try {
      db.prepare('INSERT INTO users (id, display_name, created_at) VALUES (?, ?, ?)')
        .run(userID, offeredName, now)
      redeemInvite(invite, userID, offeredName, now, at)
      token = issueDevice(userID, body.device_name)
      db.exec('COMMIT')
    } catch (error) {
      db.exec('ROLLBACK')
      throw error
    }

    log(`[pair] "${offeredName || 'unnamed'}" joined baby ${invite.baby_id}`)
    return pairingResponse(token, userID, invite.baby_id, req)
  })

  // ------------------------------------------------------------- recovery

  // The last way back in when every phone that had a log is gone.
  //
  // The phone generates the phrase and keeps it; the server is only ever told
  // the hash. That is the whole design: this database, the nightly backups and
  // any copy of them contain nothing that opens a log. It also means the server
  // physically cannot show anyone their phrase again — only the phones that
  // hold it can, which is why the app can reveal it on demand and this API
  // can't.
  //
  // One phrase per person, covering every log they're on, owned or shared
  // with them — so two children is still one thing to write down. The routes
  // below it keep the older one-key-per-baby arrangement working for builds
  // that made those.

  route('POST', '/v1/me/recovery', async (req) => {
    const { user } = requireUser(req)
    const body = await readJSON(req)
    const keyHash = requireKeyHash(body.key_hash)

    const current = db.prepare('SELECT key_hash FROM account_keys WHERE user_id = ?').get(user.id)
    if (current?.key_hash === keyHash) return { ...recoveryKeyStatus(user.id), changed: false }
    // Replacing retires the phrase somebody may have on paper, so it has to be
    // asked for. A phone that merely lacks a local copy must never do it.
    if (current && body.replace !== true) {
      throw new HttpError(409, 'You already have a recovery phrase. Replacing it retires the old one.', 'key_exists')
    }
    const holder = db.prepare('SELECT user_id FROM account_keys WHERE key_hash = ?').get(keyHash)
    if (holder && holder.user_id !== user.id) {
      throw new HttpError(409, 'That recovery phrase belongs to someone else on this server.', 'key_taken')
    }

    const now = new Date().toISOString()
    db.prepare(`INSERT INTO account_keys (user_id, key_hash, created_at) VALUES (?, ?, ?)
                ON CONFLICT(user_id) DO UPDATE SET key_hash = excluded.key_hash,
                                                   created_at = excluded.created_at,
                                                   last_used_at = NULL`)
      .run(user.id, keyHash, now)
    log(`[recovery] ${current ? 'replaced' : 'set'} the phrase for "${user.display_name || 'unnamed'}"`)
    return { ...recoveryKeyStatus(user.id), changed: true }
  })

  // Whether the phrase this phone holds is the one the server knows — so a
  // phone can tell "mine is current" from "another phone replaced it" without
  // the server ever saying what the phrase is. POST so the hash never lands in
  // an access log as a query string.
  route('POST', '/v1/me/recovery/check', async (req) => {
    const { user } = requireUser(req)
    const body = await readJSON(req)
    const keyHash = requireKeyHash(body.key_hash)
    const current = db.prepare('SELECT key_hash FROM account_keys WHERE user_id = ?').get(user.id)
    return { exists: Boolean(current), matches: current?.key_hash === keyHash }
  })

  route('POST', '/v1/babies/:babyID/recovery', async (req, res, params) => {
    const { user } = requireUser(req)
    requireOwner(params.babyID, user.id)
    const body = await readJSON(req)

    // Only ever the hash. If a key itself turned up here it would mean the
    // phone had sent the one thing this endpoint is designed never to learn.
    const keyHash = String(body.key_hash ?? '')
    if (!/^[a-f0-9]{64}$/.test(keyHash)) {
      throw new HttpError(400, 'A recovery key hash is 64 hex characters.', 'bad_key_hash')
    }

    const now = new Date().toISOString()
    db.prepare(`INSERT INTO recovery_keys (baby_id, key_hash, created_at)
                VALUES (?, ?, ?)
                ON CONFLICT(baby_id) DO UPDATE SET key_hash = excluded.key_hash,
                                                   created_at = excluded.created_at,
                                                   last_used_at = NULL`)
      .run(params.babyID, keyHash, now)
    log(`[recovery] key set for baby ${params.babyID}`)
    return { baby_id: params.babyID, created_at: now }
  })

  /** Whether a log has a recovery key yet — never the key, and never the hash. */
  route('GET', '/v1/babies/:babyID/recovery', (req, res, params) => {
    const { user } = requireUser(req)
    requireMember(params.babyID, user.id)
    const row = db.prepare('SELECT created_at, last_used_at FROM recovery_keys WHERE baby_id = ?')
      .get(params.babyID)
    return { exists: Boolean(row), created_at: row?.created_at ?? null, last_used_at: row?.last_used_at ?? null }
  })

  /**
   * A person's phrase, redeemed. On a phone with nothing, it becomes that
   * person. On a phone that's already them, nothing changes. On a phone set up
   * as somebody else — typically a fresh enrolment made before the phrase
   * turned up — that somebody is folded in: their logs join the person's, their
   * phones follow, and the phone keeps the token it has. Nothing anybody
   * logged is lost, and no phone ends up holding two identities.
   */
  function recoverPerson(account, caller, deviceName, req) {
    const userID = account.user_id
    const now = new Date().toISOString()
    let token = null
    let merged = false
    let retiredKey = false

    db.exec('BEGIN')
    try {
      if (!caller) {
        token = issueDevice(userID, deviceName)
      } else if (caller.user.id !== userID) {
        const person = db.prepare('SELECT display_name FROM users WHERE id = ?').get(userID)
        for (const seat of db.prepare('SELECT * FROM members WHERE user_id = ?').all(caller.user.id)) {
          const mine = membership(seat.baby_id, userID)
          if (!mine) {
            db.prepare(`INSERT INTO members (baby_id, user_id, role, display_name, joined_at, server_ms)
                        VALUES (?, ?, ?, ?, ?, ?)`)
              .run(seat.baby_id, userID, seat.role, isSealedBaby(seat.baby_id) ? '' : person?.display_name ?? '',
                now, stamp().ms)
          } else if (seat.role === 'owner' && mine.role !== 'owner') {
            db.prepare("UPDATE members SET role = 'owner', server_ms = ? WHERE baby_id = ? AND user_id = ?")
              .run(stamp().ms, seat.baby_id, userID)
          }
        }
        db.prepare('DELETE FROM members WHERE user_id = ?').run(caller.user.id)
        db.prepare('UPDATE devices SET user_id = ? WHERE user_id = ?').run(userID, caller.user.id)
        // The folded-in identity's own phrase, if it had one, now opens an
        // empty caregiver. Retire it rather than leave a phrase that looks
        // like it works; the response says so, so the phone can too.
        retiredKey = db.prepare('DELETE FROM account_keys WHERE user_id = ?').run(caller.user.id).changes > 0
        merged = true
      }
      db.prepare('UPDATE account_keys SET last_used_at = ? WHERE user_id = ?').run(now, userID)
      db.exec('COMMIT')
    } catch (error) {
      db.exec('ROLLBACK')
      throw error
    }

    log(`[recovery] phrase used for ${userID}${merged ? ` (folded in ${caller.user.id})` : ''}`)
    return { ...pairingResponse(token, userID, null, req), merged, retired_key: retiredKey }
  }

  // Redeeming a phrase or an older per-baby key. No token required — the key
  // *is* the credential, which is the point of having it. Rate limited like the
  // other unauthenticated routes: 24 characters from a 32-letter alphabet is
  // about 120 bits, so guessing is not the threat, but there's no reason to
  // allow the attempt.
  route('POST', '/v1/recover', async (req, res, params, ctx) => {
    if (!pairLimiter(ctx.clientKey)) throw new HttpError(429, 'Too many attempts. Wait a minute.')
    const body = await readJSON(req)
    const key = normalizeRecoveryKey(body.key)
    if (!isPlausibleRecoveryKey(key)) {
      throw new HttpError(400, "That doesn't look like a recovery key.", 'bad_key')
    }

    // A person's phrase first: it covers every log they're on.
    const keyHash = hashToken(key)
    const account = db.prepare('SELECT * FROM account_keys WHERE key_hash = ?').get(keyHash)
    if (account) {
      return recoverPerson(account, authenticate(db, req.headers.authorization), body.device_name, req)
    }

    const row = db.prepare('SELECT * FROM recovery_keys WHERE key_hash = ?').get(keyHash)
    if (!row) throw new HttpError(404, "That recovery key doesn't match any log on this server.", 'bad_key')

    const baby = db.prepare('SELECT * FROM babies WHERE id = ?').get(row.baby_id)
    if (!baby || baby.deleted_at) {
      throw new HttpError(410, 'The log that key belonged to is gone.', 'baby_gone')
    }

    // A phone holds one token, and a caregiver can be on more than one baby.
    // So a phone that's already paired adds this log to the caregiver it
    // already is, rather than becoming a second one — otherwise recovering a
    // second baby would quietly cost you the first.
    const caller = authenticate(db, req.headers.authorization)
    const displayName = String(body.display_name ?? '').slice(0, 200)
    const now = new Date().toISOString()
    const userID = caller?.user.id ?? randomUUID().toUpperCase()
    const at = stamp()

    db.exec('BEGIN')
    try {
      if (!caller) {
        db.prepare('INSERT INTO users (id, display_name, created_at) VALUES (?, ?, ?)')
          .run(userID, displayName, now)
      }
      // Recovering restores the owner's seat: whoever holds the key is the
      // person who can hand the log to anyone else, and a caregiver who
      // couldn't issue invites would be locked out of doing exactly that.
      const already = membership(row.baby_id, userID)
      if (already) {
        db.prepare("UPDATE members SET role = 'owner' WHERE baby_id = ? AND user_id = ?")
          .run(row.baby_id, userID)
      } else {
        db.prepare(`INSERT INTO members (baby_id, user_id, role, display_name, joined_at, server_ms)
                    VALUES (?, ?, 'owner', ?, ?, ?)`)
          .run(row.baby_id, userID, isSealedBaby(row.baby_id) ? '' : caller?.user.display_name ?? displayName,
            now, at.ms)
      }
      db.prepare('UPDATE recovery_keys SET last_used_at = ? WHERE baby_id = ?').run(now, row.baby_id)
      db.exec('COMMIT')
    } catch (error) {
      db.exec('ROLLBACK')
      throw error
    }

    const user = db.prepare('SELECT * FROM users WHERE id = ?').get(userID)
    const token = caller ? null : issueDevice(userID, body.device_name)
    log(`[recovery] baby ${row.baby_id} recovered by "${user.display_name || 'unnamed'}"`)
    return pairingResponse(token, userID, row.baby_id, req)
  })

  // ---------------------------------------------------------------- account

  route('GET', '/v1/me', (req) => {
    const { user, device } = requireUser(req)
    return {
      user_id: user.id,
      display_name: user.display_name,
      device_id: device.id,
      babies: membershipsOf(user.id, req),
      recovery_key: recoveryKeyStatus(user.id),
      server_id: SERVER_ID,
      server_time: new Date().toISOString(),
    }
  })

  route('POST', '/v1/me', async (req) => {
    const { user } = requireUser(req)
    const body = await readJSON(req)
    const displayName = String(body.display_name ?? '').slice(0, 200)
    db.prepare('UPDATE users SET display_name = ? WHERE id = ?').run(displayName, user.id)
    // The name shows next to every row this caregiver logged, so a rename has
    // to reach the member list the other phone reads, not just this one.
    // Not on a sealed log: there the name is the sealed one the phone sets.
    db.prepare(`UPDATE members SET display_name = ?, server_ms = ?
                WHERE user_id = ? AND baby_id NOT IN (SELECT id FROM babies WHERE sealed = 1)`)
      .run(displayName, stamp().ms, user.id)
    return { user_id: user.id, display_name: displayName }
  })

  route('GET', '/v1/devices', (req) => {
    const { user, device } = requireUser(req)
    const devices = db.prepare(
      `SELECT id, name, created_at, last_seen_at, revoked_at FROM devices
       WHERE user_id = ? ORDER BY created_at`).all(user.id)
    return { devices: devices.map((d) => ({ ...d, is_this_device: d.id === device.id })) }
  })

  route('DELETE', '/v1/devices/:id', (req, res, params) => {
    const { user } = requireUser(req)
    const result = db.prepare(
      'UPDATE devices SET revoked_at = ? WHERE id = ? AND user_id = ? AND revoked_at IS NULL')
      .run(new Date().toISOString(), params.id, user.id)
    if (!result.changes) throw new HttpError(404, "That phone isn't on your account.")
    return { revoked: params.id }
  })

  // ---------------------------------------------------------------- sharing

  route('GET', '/v1/babies/:babyID/members', (req, res, params) => {
    const { user } = requireUser(req)
    requireMember(params.babyID.toUpperCase(), user.id)
    return { members: membersOf(params.babyID.toUpperCase()) }
  })

  // Any caregiver on a log can bring the next one in: the person holding the
  // phone out to be scanned is the whole of the check, and a grandparent
  // shouldn't need the owner in the room to hand the log to a sitter.
  route('POST', '/v1/babies/:babyID/invites', async (req, res, params) => {
    const { user } = requireUser(req)
    const babyID = params.babyID.toUpperCase()
    requireMember(babyID, user.id)
    const body = await readJSON(req)
    // Short by default: an invite is scanned off the other phone's screen in
    // the next minute, not mailed. A code that outlives the moment is a code
    // that's still valid when a screenshot of it isn't.
    const minutes = Math.min(Math.max(Number(body.expires_in_minutes) || 60, 5), 60 * 24 * 7)
    const maxUses = Math.min(Math.max(Number(body.max_uses) || 1, 1), 10)
    const now = new Date()
    const expires = new Date(now.getTime() + minutes * 60_000)

    let code
    for (let attempt = 0; attempt < 10; attempt++) {
      const candidate = newInviteCode()
      if (!db.prepare('SELECT 1 FROM invites WHERE code = ?').get(candidate)) {
        code = candidate
        break
      }
    }
    if (!code) throw new HttpError(500, 'Could not generate an invite code.')

    db.prepare(`INSERT INTO invites (code, baby_id, created_by, created_at, expires_at, max_uses)
                VALUES (?, ?, ?, ?, ?, ?)`)
      .run(code, babyID, user.id, now.toISOString(), expires.toISOString(), maxUses)
    return { code, baby_id: babyID, expires_at: expires.toISOString(), max_uses: maxUses }
  })

  // The owner sees every live invite; anyone else sees the ones they made.
  route('GET', '/v1/babies/:babyID/invites', (req, res, params) => {
    const { user } = requireUser(req)
    const babyID = params.babyID.toUpperCase()
    const member = requireMember(babyID, user.id)
    const everyone = member.role === 'owner' ? 1 : 0
    const invites = db.prepare(
      `SELECT code, created_by, created_at, expires_at, max_uses, uses, revoked_at FROM invites
       WHERE baby_id = ? AND revoked_at IS NULL AND expires_at > ? AND uses < max_uses
         AND (? = 1 OR created_by = ?)
       ORDER BY created_at DESC`).all(babyID, new Date().toISOString(), everyone, user.id)
    return { invites }
  })

  // Cancelled by whoever made it, or by the owner.
  route('DELETE', '/v1/babies/:babyID/invites/:code', (req, res, params) => {
    const { user } = requireUser(req)
    const babyID = params.babyID.toUpperCase()
    const member = requireMember(babyID, user.id)
    const code = normalizeCode(params.code)
    const invite = db.prepare('SELECT created_by FROM invites WHERE baby_id = ? AND code = ?').get(babyID, code)
    if (!invite) throw new HttpError(404, "That invite code isn't valid.", 'bad_code')
    if (member.role !== 'owner' && invite.created_by !== user.id) {
      throw new HttpError(403, 'Only whoever made an invite, or the owner, can cancel it.', 'not_owner')
    }
    db.prepare('UPDATE invites SET revoked_at = ? WHERE baby_id = ? AND code = ?')
      .run(new Date().toISOString(), babyID, code)
    return { revoked: code }
  })

  // This caregiver's locked copy of a sealed baby's key: the baby's key,
  // encrypted on the phone with a key made from their recovery phrase. It is
  // what lets the phrase bring an encrypted log back on a new phone, and the
  // server can't open it.
  route('PUT', '/v1/babies/:babyID/key', async (req, res, params) => {
    const { user } = requireUser(req)
    const babyID = params.babyID.toUpperCase()
    requireMember(babyID, user.id)
    if (!isSealedBaby(babyID)) throw new HttpError(409, 'This log is not encrypted.', 'not_sealed')
    const body = await readJSON(req)
    const wrapped = String(body.wrapped ?? '')
    if (!WRAPPED_KEY_RE.test(wrapped)) throw new HttpError(400, "That isn't a locked key.", 'bad_wrapped_key')
    db.prepare(`INSERT INTO baby_keys (baby_id, user_id, wrapped, updated_at) VALUES (?, ?, ?, ?)
                ON CONFLICT(baby_id, user_id) DO UPDATE SET wrapped = excluded.wrapped, updated_at = excluded.updated_at`)
      .run(babyID, user.id, wrapped, new Date().toISOString())
    return { baby_id: babyID, stored: true }
  })

  // This caregiver's name on a sealed log, encrypted with the log's key, so
  // the other phones can show who logged what and the server can't.
  route('PUT', '/v1/babies/:babyID/members/me', async (req, res, params) => {
    const { user } = requireUser(req)
    const babyID = params.babyID.toUpperCase()
    requireMember(babyID, user.id)
    if (!isSealedBaby(babyID)) throw new HttpError(409, 'This log is not encrypted.', 'not_sealed')
    const body = await readJSON(req)
    const sealedName = String(body.sealed_name ?? '')
    if (!SEALED_NAME_RE.test(sealedName)) throw new HttpError(400, "That isn't a sealed name.", 'bad_sealed_name')
    db.prepare('UPDATE members SET sealed_name = ?, display_name = ?, server_ms = ? WHERE baby_id = ? AND user_id = ?')
      .run(sealedName, '', stamp().ms, babyID, user.id)
    return { baby_id: babyID, stored: true }
  })

  route('DELETE', '/v1/babies/:babyID/members/:userID', (req, res, params) => {
    const { user } = requireUser(req)
    const babyID = params.babyID.toUpperCase()
    const targetID = params.userID.toUpperCase()
    // Anyone can remove themselves; only the owner can remove anyone else.
    if (targetID !== user.id) requireOwner(babyID, user.id)
    else requireMember(babyID, user.id)
    const target = membership(babyID, targetID)
    if (!target) throw new HttpError(404, "That caregiver isn't on this log.")
    if (target.role === 'owner') {
      throw new HttpError(409, 'The owner of a shared log cannot be removed.', 'owner_locked')
    }
    db.prepare('DELETE FROM members WHERE baby_id = ? AND user_id = ?').run(babyID, targetID)
    return { removed: targetID }
  })

  // ---------------------------------------------------------------- syncing

  route('POST', '/v1/sync/push', async (req) => {
    const { user } = requireUser(req)
    const body = await readJSON(req)
    const applied = []
    const rejected = []

    db.exec('BEGIN IMMEDIATE')
    try {
      for (const table of ROW_TABLES) {
        const rows = body[table]
        if (rows === undefined || rows === null) continue
        if (!Array.isArray(rows)) throw new HttpError(400, `${table} must be a list of rows.`)
        for (const raw of rows) {
          let row
          try {
            row = normalizeRow(table, raw, { userID: user.id })
          } catch (error) {
            if (error instanceof RowError) {
              rejected.push({ table, id: raw?.id ?? null, reason: error.message, code: 'malformed' })
              continue
            }
            throw error
          }

          // Pushing a baby the server has never seen is how a log becomes
          // shared: the phone that does it becomes the owner. There is no
          // separate "start sharing" call to get out of step with this.
          let claimsOwnership = false
          if (table === 'babies') {
            const existing = db.prepare('SELECT id, created_by, sealed FROM babies WHERE id = ?').get(row.id)
            // Sealed or not is settled when the baby first arrives.
            sealBabyRow(row, existing ? existing.sealed : undefined)
            if (!existing) {
              claimsOwnership = true
              row.created_by = user.id
            } else if (!membership(row.id, user.id)) {
              rejected.push({ table, id: row.id, reason: 'not a caregiver on this baby', code: 'not_a_member' })
              continue
            } else {
              // Who started the log doesn't change because somebody else
              // edited the name; every phone sends its own id here.
              row.created_by = existing.created_by
            }
          } else if (!membership(row.baby_id, user.id)) {
            rejected.push({ table, id: row.id, reason: 'not a caregiver on this baby', code: 'not_a_member' })
            continue
          } else if (isSealedBaby(row.baby_id)) {
            // A readable row in an encrypted log would be the one thing the
            // log promised not to hold. Refused, not stored.
            rejected.push({ table, id: row.id, reason: 'this log is encrypted', code: 'sealed_baby' })
            continue
          } else {
            // Checked where the row is stored, not only where the phone says
            // it belongs: otherwise a caregiver on one log could move another
            // log's row into theirs by knowing its id.
            const stored = db.prepare(`SELECT baby_id FROM ${table} WHERE id = ?`).get(row.id)
            if (stored && stored.baby_id !== row.baby_id && !membership(stored.baby_id, user.id)) {
              rejected.push({ table, id: row.id, reason: 'that row belongs to a baby you are not on', code: 'not_a_member' })
              continue
            }
          }

          const result = upsertRow(db, table, row, {
            userID: user.id,
            actorName: row.logged_by_name || user.display_name,
          })
          // After the insert, not before: members has a foreign key to babies.
          if (claimsOwnership) {
            const at = stamp()
            db.prepare(`INSERT INTO members (baby_id, user_id, role, display_name, joined_at, server_ms)
                        VALUES (?, ?, 'owner', ?, ?, ?)
                        ON CONFLICT(baby_id, user_id) DO NOTHING`)
              .run(row.id, user.id, row.sealed === 1 ? '' : user.display_name, at.iso, at.ms)
          }
          applied.push({ table, id: row.id, ...result })
        }
      }

      // Sealed rows, after the babies above so a new sealed baby's first rows
      // can ride in the same push as the baby itself.
      if (body.sealed !== undefined && body.sealed !== null) {
        if (!Array.isArray(body.sealed)) throw new HttpError(400, 'sealed must be a list of rows.')
        for (const raw of body.sealed) {
          let row
          try {
            row = normalizeSealedRow(raw)
          } catch (error) {
            if (error instanceof RowError) {
              rejected.push({ table: 'sealed', id: raw?.id ?? null, reason: error.message, code: 'malformed' })
              continue
            }
            throw error
          }
          if (!membership(row.baby_id, user.id)) {
            rejected.push({ table: 'sealed', id: row.id, reason: 'not a caregiver on this baby', code: 'not_a_member' })
            continue
          }
          if (!isSealedBaby(row.baby_id)) {
            rejected.push({ table: 'sealed', id: row.id, reason: 'this log is not encrypted', code: 'not_sealed' })
            continue
          }
          const stored = db.prepare('SELECT baby_id FROM sealed_rows WHERE id = ?').get(row.id)
          if (stored && stored.baby_id !== row.baby_id) {
            rejected.push({ table: 'sealed', id: row.id, reason: 'that row belongs to another baby', code: 'not_a_member' })
            continue
          }
          applied.push({ table: 'sealed', id: row.id, ...upsertSealedRow(db, row, { userID: user.id }) })
        }
      }
      db.exec('COMMIT')
    } catch (error) {
      db.exec('ROLLBACK')
      throw error
    }

    return { applied, rejected, server_time: new Date().toISOString() }
  })

  /** A row's server stamp, in milliseconds. */
  const msOf = (row) => new Date(row.server_updated_at).getTime()

  route('GET', '/v1/sync/pull', (req, res, params, ctx) => {
    const { user } = requireUser(req)
    const babyID = String(ctx.query.get('baby_id') ?? '').toUpperCase()
    if (!babyID) throw new HttpError(400, 'baby_id is required.')
    requireMember(babyID, user.id)
    requireCanRead(req, babyID)

    const sinceRaw = ctx.query.get('since')
    const sinceMs = sinceRaw ? new Date(sinceRaw).getTime() : 0
    if (Number.isNaN(sinceMs)) throw new HttpError(400, 'since is not a date.')
    const limit = Math.min(Number(ctx.query.get('limit')) || DEFAULT_PULL_LIMIT, MAX_PULL_LIMIT)

    // Each table gives up to `limit` rows. If any of them filled its page,
    // every table is cut at the earliest of those last rows, so a page never
    // runs ahead of itself: a table with a few late rows (a weigh-in) can't
    // carry the cursor past the feeds still waiting behind a full page. The
    // cursor for the next page is exact, and stamps never repeat, so nothing
    // falls between pages and nothing is sent twice.
    const pages = {}
    let cutoff = Infinity
    // Sealed rows page alongside the readable tables, under the same cutoff.
    const pagedTables = [...ROW_TABLES, 'sealed']
    for (const table of pagedTables) {
      const rows = table === 'sealed'
        ? sealedRowsSince(db, babyID, sinceMs, limit)
        : rowsSince(db, table, babyID, sinceMs, limit)
      pages[table] = rows
      if (rows.length >= limit) cutoff = Math.min(cutoff, msOf(rows[rows.length - 1]))
    }
    const hasMore = Number.isFinite(cutoff)
    const payload = { baby_id: babyID }
    let newest = sinceMs
    for (const table of pagedTables) {
      const rows = hasMore ? pages[table].filter((row) => msOf(row) <= cutoff) : pages[table]
      payload[table] = rows
      for (const row of rows) newest = Math.max(newest, msOf(row))
    }
    payload.members = membersOf(babyID)
    payload.has_more = hasMore
    // Where the next pull starts: exactly the newest row this page sent.
    payload.next_since = newest > 0 ? new Date(hasMore ? cutoff : newest).toISOString() : (sinceRaw || null)
    payload.server_time = new Date().toISOString()
    return payload
  })

  // What changed and who did it. Nothing sends push notifications yet; this is
  // what the phone polls on foreground so "Annette logged a feed" costs one
  // small request instead of a full pull.
  route('GET', '/v1/changes', (req, res, params, ctx) => {
    const { user } = requireUser(req)
    const babyID = String(ctx.query.get('baby_id') ?? '').toUpperCase()
    if (!babyID) throw new HttpError(400, 'baby_id is required.')
    requireMember(babyID, user.id)
    const sinceSeq = Number(ctx.query.get('since_seq')) || 0
    const limit = Math.min(Number(ctx.query.get('limit')) || 100, 500)
    const changes = db.prepare(
      `SELECT seq, table_name, row_id, user_id, actor_name, kind, at FROM changes
       WHERE baby_id = ? AND seq > ? ORDER BY seq ASC LIMIT ?`).all(babyID, sinceSeq, limit)
    const latest = db.prepare('SELECT MAX(seq) AS seq FROM changes WHERE baby_id = ?').get(babyID)
    return {
      changes: changes.map((c) => ({ ...c, by_me: c.user_id === user.id })),
      latest_seq: latest?.seq ?? 0,
      server_time: new Date().toISOString(),
    }
  })

  // ---------------------------------------------------------------- plumbing

  async function handle(req, res) {
    const url = new URL(req.url, 'http://localhost')
    const socketAddress = req.socket.remoteAddress || 'unknown'
    const forwarded = String(req.headers['x-forwarded-for'] ?? '').split(',')[0].trim()
    const ctx = {
      query: url.searchParams,
      // Behind Caddy every request arrives from loopback, so there the
      // forwarded address is the only one that means anything. Anywhere else
      // the header is just something the client typed, and trusting it would
      // let any phone on the Wi-Fi pick its own rate-limit bucket.
      clientKey: isLoopbackAddress(socketAddress) && forwarded ? forwarded : socketAddress,
      socketKey: socketAddress,
    }

    // Keep looking after a path match whose method doesn't fit: two verbs can
    // share a path, and stopping at the first one made whichever was
    // registered second unreachable. 405 is only right once every route with
    // this path has been tried.
    let pathExists = false
    for (const r of routes) {
      const match = r.regex.exec(url.pathname)
      if (!match) continue
      if (r.method !== req.method) {
        pathExists = true
        continue
      }
      const params = Object.fromEntries(r.names.map((name, i) => [name, decodeURIComponent(match[i + 1])]))
      return await r.handler(req, res, params, ctx)
    }
    if (pathExists) throw new HttpError(405, `${req.method} isn't allowed here.`)
    throw new HttpError(404, 'No such endpoint.')
  }

  const server = createServer((req, res) => {
    handle(req, res)
      .then((body) => {
        if (res.writableEnded) return
        json(res, 200, body)
      })
      .catch((error) => {
        if (res.writableEnded) return
        if (error instanceof HttpError) {
          json(res, error.status, { error: error.message, code: error.code ?? null })
        } else {
          log(`[error] ${req.method} ${req.url}: ${error.stack ?? error}`)
          json(res, 500, { error: 'Something went wrong on the server.' })
        }
      })
  })

  server.on('close', () => db.close())
  return { server, db }
}
