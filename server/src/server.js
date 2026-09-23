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
  isPlausibleRecoveryKey, normalizeRecoveryKey,
} from './auth.js'
import { normalizeRow, upsertRow, rowsSince, RowError } from './sync.js'

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

export function createApp({
  dbPath, setupSecret, log = console.log,
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
   * Adds a caregiver to the invite's baby and spends the code. Caller owns the
   * transaction, because it also creates the caregiver in the same one.
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

  // ------------------------------------------------------------- recovery

  // The last way back into a baby's log when every phone that had it is gone.
  //
  // The phone generates the key and keeps it; the server is only ever told the
  // hash. That is the whole design: this database, the nightly backups and any
  // copy of them contain nothing that opens a log. It also means the server
  // physically cannot show anyone their key again — only the phones that hold
  // it can, which is why the app can reveal it on demand and this API can't.
  //
  // One key per baby, because the log is the thing being recovered. Replacing
  // it invalidates the old one, so a key written on paper that's since been
  // lost track of can be retired.
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

  // Redeeming one. No token required — the key *is* the credential, which is
  // the point of having it. Rate limited like the other two unauthenticated
  // routes: 24 characters from a 32-letter alphabet is about 120 bits, so
  // guessing is not the threat, but there's no reason to allow the attempt.
  route('POST', '/v1/recover', async (req, res, params, ctx) => {
    if (!pairLimiter(ctx.clientKey)) throw new HttpError(429, 'Too many attempts. Wait a minute.')
    const body = await readJSON(req)
    const key = normalizeRecoveryKey(body.key)
    if (!isPlausibleRecoveryKey(key)) {
      throw new HttpError(400, "That doesn't look like a recovery key.", 'bad_key')
    }

    const row = db.prepare('SELECT * FROM recovery_keys WHERE key_hash = ?').get(hashToken(key))
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
          .run(row.baby_id, userID, caller?.user.display_name ?? displayName, now, at.ms)
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
    return {
      token,
      user_id: userID,
      display_name: user.display_name,
      baby: babyPayload(row.baby_id),
      members: membersOf(row.baby_id),
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
