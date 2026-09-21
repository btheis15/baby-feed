// The HTTP API. Node's own http module — no framework, because the routing
// here is a dozen paths and a framework would be the only dependency.
//
// Everything lives under /v1. Every route except /v1/health and the two pairing
// routes requires a device token, and every route that names a baby checks
// membership of that baby before it reads or writes a single row. That check is
// the whole access-control story: there is no "public" data.

import { createServer } from 'node:http'
import { randomUUID } from 'node:crypto'
import { openDatabase, primeStamp, stamp, ROW_TABLES } from './db.js'
import {
  authenticate, createRateLimiter, hashToken, newInviteCode, newToken,
  normalizeCode, secretsMatch, CODE_LENGTH,
} from './auth.js'
import { normalizeRow, upsertRow, rowsSince, RowError } from './sync.js'
import { createAppleVerifier } from './apple.js'

const MAX_BODY_BYTES = 2 * 1024 * 1024 // a very long catch-up push is ~100 KB
const MAX_PULL_LIMIT = 1000
const DEFAULT_PULL_LIMIT = 500

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

/**
 * @param appleAudience  The app's bundle identifier. Sign in with Apple is off
 *                       unless this is set, so a server that hasn't been told
 *                       which app it serves says so rather than trusting any
 *                       token that turns up.
 * @param verifyAppleToken  Injected by the tests; production builds its own.
 */
export function createApp({
  dbPath, setupSecret, log = console.log,
  appleAudience = null,
  verifyAppleToken = appleAudience ? createAppleVerifier({ audience: appleAudience }) : null,
  // Only raised by the tests, which come from one address and would otherwise
  // rate-limit themselves rather than the thing they mean to check.
  pairRateLimit = { limit: 10, windowMs: 60_000 },
}) {
  const db = openDatabase(dbPath)
  primeStamp(db)

  // Only the unauthenticated routes are limited; see auth.js for why.
  const pairLimiter = createRateLimiter(pairRateLimit)

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
      `SELECT id, name, birth_date, sex, due_date, created_by, updated_at, deleted_at, server_updated_at
       FROM babies WHERE id = ?`).get(babyID)
    return baby ?? null
  }

  function membersOf(babyID) {
    return db.prepare(
      `SELECT baby_id, user_id, role, display_name, joined_at FROM members
       WHERE baby_id = ? ORDER BY joined_at ASC`).all(babyID)
  }

  /**
   * Checks an invite is real, unexpired and unspent. Separate from redeeming
   * it so a sign-in can fail on a bad code before it creates an account.
   */
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
   * Adds a caregiver to the invite's baby and spends the code. Caller owns the
   * transaction, because sign-in also creates the user in the same one.
   */
  function redeemInvite(invite, userID, displayName, now, at) {
    const already = membership(invite.baby_id, userID)
    if (!already) {
      db.prepare(`INSERT INTO members (baby_id, user_id, role, display_name, joined_at, server_ms)
                  VALUES (?, ?, 'caregiver', ?, ?, ?)`)
        .run(invite.baby_id, userID, displayName, now, at.ms)
    }
    db.prepare('UPDATE invites SET uses = uses + 1 WHERE code = ?').run(invite.code)
  }

  function issueDevice(userID, deviceName) {
    const token = newToken()
    const now = new Date().toISOString()
    db.prepare(`INSERT INTO devices (id, user_id, token_hash, name, created_at)
                VALUES (?, ?, ?, ?, ?)`)
      .run(randomUUID().toUpperCase(), userID, hashToken(token), String(deviceName ?? '').slice(0, 120), now)
    return token
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

  route('GET', '/v1/health', () => ({
    ok: true,
    service: 'babyfeed-server',
    server_time: new Date().toISOString(),
    paired_devices: db.prepare('SELECT COUNT(*) AS n FROM devices WHERE revoked_at IS NULL').get().n,
    babies: db.prepare('SELECT COUNT(*) AS n FROM babies WHERE deleted_at IS NULL').get().n,
    feeds: db.prepare('SELECT COUNT(*) AS n FROM feeds WHERE deleted_at IS NULL').get().n,
  }))

  // ---------------------------------------------------------------- pairing

  // The first phone, and only ever the first. The setup secret is printed once
  // by setup.sh and is meant to be typed in on that phone and then forgotten.
  //
  // It is spent the moment somebody claims it. It used to be replayable, which
  // meant the code — a short string that gets read aloud, sits in a terminal
  // buffer and lives in a .env — could be used again by anyone who still had
  // it, over and over, on a hostname that answers to the whole internet. Those
  // extra accounts couldn't read anything (membership is per baby and a fresh
  // claim has none), but a server that hands out accounts to a replayed
  // password is not a server worth arguing about.
  //
  // Nothing is lost by spending it: a second caregiver arrives on an invite,
  // and an owner who replaces their phone comes back with Sign in with Apple.
  route('POST', '/v1/pair/claim', async (req, res, params, ctx) => {
    if (!pairLimiter(ctx.clientKey)) throw new HttpError(429, 'Too many attempts. Wait a minute.')
    const body = await readJSON(req)
    if (!setupSecret) throw new HttpError(503, 'No setup secret is configured on the server.')
    if (!secretsMatch(body.secret, setupSecret)) {
      throw new HttpError(401, "That setup code doesn't match.", 'bad_secret')
    }
    if (db.prepare('SELECT 1 FROM users LIMIT 1').get()) {
      throw new HttpError(409,
        'This server has already been set up. Sign in with Apple to get back in, or ask for an invite.',
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

  // Every phone after the first.
  route('POST', '/v1/pair/invite', async (req, res, params, ctx) => {
    if (!pairLimiter(ctx.clientKey)) throw new HttpError(429, 'Too many attempts. Wait a minute.')
    const body = await readJSON(req)
    const code = normalizeCode(body.code)
    if (code.length !== CODE_LENGTH) {
      throw new HttpError(400, `An invite code is ${CODE_LENGTH} letters and numbers.`, 'bad_code')
    }
    const invite = requireUsableInvite(code)

    const displayName = String(body.display_name ?? '').slice(0, 200)
    const now = new Date().toISOString()
    const userID = randomUUID().toUpperCase()
    const at = stamp()

    db.exec('BEGIN')
    try {
      db.prepare('INSERT INTO users (id, display_name, created_at) VALUES (?, ?, ?)')
        .run(userID, displayName, now)
      redeemInvite(invite, userID, displayName, now, at)
      db.exec('COMMIT')
    } catch (error) {
      db.exec('ROLLBACK')
      throw error
    }

    const token = issueDevice(userID, body.device_name)
    log(`[pair] "${displayName || 'unnamed'}" joined baby ${invite.baby_id}`)
    return {
      token,
      user_id: userID,
      display_name: displayName,
      baby: babyPayload(invite.baby_id),
      members: membersOf(invite.baby_id),
    }
  })

  // ------------------------------------------------------------- sign-in

  // Sign in with Apple. This is the only way back into your own log on a phone
  // that isn't the one you paired — the device token is device-bound, and only
  // an owner can issue invites, so before this an owner who wiped their phone
  // was locked out of their own baby's log for good.
  //
  // Four things can be happening here, and which one it is falls out of
  // whether we've seen this Apple ID before and whether the phone already
  // holds a token:
  //
  //   known Apple ID, no token   -> signing in on a new phone. Hand back a
  //                                 token for the account they already have.
  //   new Apple ID, holds token  -> a phone that paired the old way, now
  //                                 attaching an account so it's recoverable.
  //                                 Keeps its token; nothing else changes.
  //   new Apple ID + invite      -> the invited caregiver. Joins that baby.
  //   new Apple ID, nothing else -> refused. See below.
  //   known Apple ID, different
  //   account holds the token    -> refused. Merging two caregivers' histories
  //                                 is not something to guess at.
  //
  // That last-but-one rule is the important one. Signing in cannot conjure an
  // account out of nothing, because an account with no baby on it is worth
  // nothing to its owner and the endpoint is worth quite a lot to everybody
  // else: this hostname answers to the internet, and an open sign-up is a
  // thing to defend. An account here only ever comes from the one setup code
  // or an invite the owner issued.
  route('POST', '/v1/auth/apple', async (req, res, params, ctx) => {
    if (!verifyAppleToken) {
      throw new HttpError(503, 'Signing in with Apple is not configured on this server.', 'no_apple')
    }
    if (!pairLimiter(ctx.clientKey)) throw new HttpError(429, 'Too many attempts. Wait a minute.')
    const body = await readJSON(req)

    let identity
    try {
      identity = await verifyAppleToken(body.identity_token, { rawNonce: body.raw_nonce })
    } catch (error) {
      throw new HttpError(401, error.message || "That Apple sign-in couldn't be verified.", 'bad_apple_token')
    }

    // Validate the invite before creating anything, so a mistyped code doesn't
    // leave a stray account behind.
    const invite = body.invite_code ? requireUsableInvite(body.invite_code) : null

    // An already-paired phone attaching an account, rather than signing in.
    const caller = authenticate(db, req.headers.authorization)
    const existing = db.prepare('SELECT * FROM credentials WHERE type = ? AND subject = ?')
      .get('apple', identity.subject)

    if (existing && caller && existing.user_id !== caller.user.id) {
      throw new HttpError(409,
        'That Apple Account is already attached to a different caregiver on this server.',
        'apple_in_use')
    }

    if (!existing && !caller && !invite) {
      throw new HttpError(403,
        "Nothing on this server is shared with your Apple Account yet. Ask whoever set it up to send you an invite.",
        'needs_invite')
    }

    const requestedName = String(body.display_name ?? '').trim().slice(0, 200)
    const now = new Date().toISOString()
    const at = stamp()
    const isNewAccount = !existing && !caller
    const userID = existing?.user_id ?? caller?.user.id ?? randomUUID().toUpperCase()

    db.exec('BEGIN')
    try {
      if (isNewAccount) {
        db.prepare('INSERT INTO users (id, display_name, created_at) VALUES (?, ?, ?)')
          .run(userID, requestedName, now)
      } else if (requestedName) {
        // Apple only hands over the name the very first time someone authorises
        // the app, so a later sign-in sends nothing. Never let that blank out a
        // name that's already on the caregiver's feeds.
        db.prepare('UPDATE users SET display_name = ? WHERE id = ? AND display_name = \'\'')
          .run(requestedName, userID)
      }
      if (!existing) {
        db.prepare(`INSERT INTO credentials (type, subject, user_id, created_at, last_used_at)
                    VALUES (?, ?, ?, ?, ?)`)
          .run('apple', identity.subject, userID, now, now)
      } else {
        db.prepare('UPDATE credentials SET last_used_at = ? WHERE type = ? AND subject = ?')
          .run(now, 'apple', identity.subject)
      }
      if (invite) {
        const user = db.prepare('SELECT display_name FROM users WHERE id = ?').get(userID)
        redeemInvite(invite, userID, user?.display_name ?? requestedName, now, at)
      }
      db.exec('COMMIT')
    } catch (error) {
      db.exec('ROLLBACK')
      throw error
    }

    const user = db.prepare('SELECT * FROM users WHERE id = ?').get(userID)
    const babies = db.prepare(
      `SELECT m.role, b.id, b.name, b.birth_date, b.sex, b.due_date, b.created_by,
              b.updated_at, b.deleted_at, b.server_updated_at
       FROM members m JOIN babies b ON b.id = m.baby_id
       WHERE m.user_id = ? ORDER BY b.name`).all(userID)

    // A phone that already holds a token keeps it: it's the same phone, and a
    // second device row for it would show up as a stranger under Caregivers.
    const token = caller ? null : issueDevice(userID, body.device_name)
    log(`[auth] apple ${existing ? 'sign-in' : caller ? 'link' : 'new account'} for ${userID}`)

    return {
      token,
      user_id: userID,
      display_name: user.display_name,
      is_new_account: isNewAccount,
      baby: invite ? babyPayload(invite.baby_id) : null,
      babies,
    }
  })

  // ---------------------------------------------------------------- account

  route('GET', '/v1/me', (req) => {
    const { user, device } = requireUser(req)
    const babies = db.prepare(
      `SELECT m.role, b.id, b.name, b.birth_date, b.sex, b.due_date, b.created_by,
              b.updated_at, b.deleted_at, b.server_updated_at
       FROM members m JOIN babies b ON b.id = m.baby_id
       WHERE m.user_id = ? ORDER BY b.name`).all(user.id)
    return {
      user_id: user.id,
      display_name: user.display_name,
      device_id: device.id,
      babies,
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
    db.prepare('UPDATE members SET display_name = ?, server_ms = ? WHERE user_id = ?')
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

  route('POST', '/v1/babies/:babyID/invites', async (req, res, params) => {
    const { user } = requireUser(req)
    const babyID = params.babyID.toUpperCase()
    requireOwner(babyID, user.id)
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

  route('GET', '/v1/babies/:babyID/invites', (req, res, params) => {
    const { user } = requireUser(req)
    const babyID = params.babyID.toUpperCase()
    requireOwner(babyID, user.id)
    const invites = db.prepare(
      `SELECT code, created_at, expires_at, max_uses, uses, revoked_at FROM invites
       WHERE baby_id = ? AND revoked_at IS NULL AND expires_at > ? AND uses < max_uses
       ORDER BY created_at DESC`).all(babyID, new Date().toISOString())
    return { invites }
  })

  route('DELETE', '/v1/babies/:babyID/invites/:code', (req, res, params) => {
    const { user } = requireUser(req)
    const babyID = params.babyID.toUpperCase()
    requireOwner(babyID, user.id)
    db.prepare('UPDATE invites SET revoked_at = ? WHERE baby_id = ? AND code = ?')
      .run(new Date().toISOString(), babyID, normalizeCode(params.code))
    return { revoked: normalizeCode(params.code) }
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
              rejected.push({ table, id: raw?.id ?? null, reason: error.message })
              continue
            }
            throw error
          }

          // Pushing a baby the server has never seen is how a log becomes
          // shared: the phone that does it becomes the owner. There is no
          // separate "start sharing" call to get out of step with this.
          let claimsOwnership = false
          if (table === 'babies') {
            const existing = db.prepare('SELECT id FROM babies WHERE id = ?').get(row.id)
            if (!existing) {
              claimsOwnership = true
              row.created_by = user.id
            } else if (!membership(row.id, user.id)) {
              rejected.push({ table, id: row.id, reason: 'not a caregiver on this baby' })
              continue
            }
          } else if (!membership(row.baby_id, user.id)) {
            rejected.push({ table, id: row.id, reason: 'not a caregiver on this baby' })
            continue
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
              .run(row.id, user.id, user.display_name, at.iso, at.ms)
          }
          applied.push({ table, id: row.id, ...result })
        }
      }
      db.exec('COMMIT')
    } catch (error) {
      db.exec('ROLLBACK')
      throw error
    }

    return { applied, rejected, server_time: new Date().toISOString() }
  })

  route('GET', '/v1/sync/pull', (req, res, params, ctx) => {
    const { user } = requireUser(req)
    const babyID = String(ctx.query.get('baby_id') ?? '').toUpperCase()
    if (!babyID) throw new HttpError(400, 'baby_id is required.')
    requireMember(babyID, user.id)

    const sinceRaw = ctx.query.get('since')
    const sinceMs = sinceRaw ? new Date(sinceRaw).getTime() : 0
    if (Number.isNaN(sinceMs)) throw new HttpError(400, 'since is not a date.')
    const limit = Math.min(Number(ctx.query.get('limit')) || DEFAULT_PULL_LIMIT, MAX_PULL_LIMIT)

    const payload = { baby_id: babyID }
    let hasMore = false
    for (const table of ROW_TABLES) {
      const rows = rowsSince(db, table, babyID, sinceMs, limit)
      payload[table] = rows
      if (rows.length >= limit) hasMore = true
    }
    payload.members = membersOf(babyID)
    payload.has_more = hasMore
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
    const ctx = {
      query: url.searchParams,
      // Behind Caddy every request arrives from 127.0.0.1, so the forwarded
      // address is what the rate limiter has to key on to mean anything.
      clientKey: (req.headers['x-forwarded-for'] ?? '').split(',')[0].trim()
        || req.socket.remoteAddress || 'unknown',
    }

    for (const r of routes) {
      const match = r.regex.exec(url.pathname)
      if (!match) continue
      if (r.method !== req.method) {
        throw new HttpError(405, `${req.method} isn't allowed here.`)
      }
      const params = Object.fromEntries(r.names.map((name, i) => [name, decodeURIComponent(match[i + 1])]))
      return await r.handler(req, res, params, ctx)
    }
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
