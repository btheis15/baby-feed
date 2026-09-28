// A throwaway server for tests that need their own: a fresh database in a temp
// directory, listening on a random loopback port.
//
// api.test.js and recovery.test.js predate this and keep their own setup; the
// newer files share this one. Not a *.test.js file, so `node --test` doesn't
// run it on its own.

import { mkdtempSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { createHash, randomBytes, randomUUID } from 'node:crypto'
import { createApp } from '../src/server.js'
import { RECOVERY_KEY_LENGTH } from '../src/auth.js'

export const SECRET = 'test-setup-secret'
const ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'

export const uuid = () => randomUUID().toUpperCase()
export const iso = (offsetMs = 0) => new Date(Date.now() + offsetMs).toISOString()

/** What the phone does: make a phrase, keep it, send only its hash. */
export function mintKey() {
  const bytes = randomBytes(RECOVERY_KEY_LENGTH)
  let key = ''
  for (let i = 0; i < RECOVERY_KEY_LENGTH; i++) key += ALPHABET[bytes[i] % ALPHABET.length]
  return { key, hash: createHash('sha256').update(key).digest('hex') }
}

/**
 * Pairing limits are raised, because every request here comes from one
 * address; a test that's about the limits passes its own. Enrolment defaults
 * to 'lan+loopback' because loopback is the only way a test can connect — the
 * tests about refusing loopback pass enroll: 'lan'.
 */
export async function startServer(options = {}) {
  const dir = options.dbPath ? null : mkdtempSync(join(tmpdir(), 'babyfeed-test-'))
  const dbPath = options.dbPath ?? join(dir, 'test.db')
  let app
  try {
    app = createApp({
      setupSecret: SECRET,
      log: () => {},
      pairRateLimit: { limit: 1000, windowMs: 60_000 },
      enrollRateLimit: { limit: 1000, windowMs: 60_000 },
      enroll: 'lan+loopback',
      ...options,
      dbPath,
    })
  } catch (error) {
    if (dir) rmSync(dir, { recursive: true, force: true })
    throw error
  }
  await new Promise((resolve) => app.server.listen(0, '127.0.0.1', resolve))
  const base = `http://127.0.0.1:${app.server.address().port}`

  /** `body` is sent as JSON unless it's already a string; `contentType` overrides the header. */
  async function call(method, path, { token, body, headers = {}, contentType } = {}) {
    const response = await fetch(base + path, {
      method,
      headers: {
        ...(body !== undefined ? { 'content-type': contentType ?? 'application/json' } : {}),
        ...(token ? { authorization: `Bearer ${token}` } : {}),
        ...headers,
      },
      body: body === undefined ? undefined : typeof body === 'string' ? body : JSON.stringify(body),
    })
    const text = await response.text()
    let parsed = null
    try {
      parsed = text ? JSON.parse(text) : null
    } catch {
      parsed = text
    }
    return { status: response.status, body: parsed }
  }

  /** A caregiver, enrolled the way a phone on the home Wi-Fi would be. */
  async function enrol(displayName, extra = {}) {
    const result = await call('POST', '/v1/pair/enroll', {
      body: { display_name: displayName, device_name: `${displayName}'s iPhone`, ...extra },
    })
    if (result.status !== 200) throw new Error(`enrol ${displayName}: ${result.status} ${JSON.stringify(result.body)}`)
    return result.body
  }

  /** Pushes a baby, which is what makes the pusher its owner. */
  async function pushBaby(token, name, fields = {}) {
    const id = uuid()
    const result = await call('POST', '/v1/sync/push', {
      token,
      body: { babies: [{ id, name, updated_at: iso(), ...fields }] },
    })
    if (result.body?.applied?.length !== 1) throw new Error(`push ${name}: ${JSON.stringify(result.body)}`)
    return id
  }

  async function invite(token, babyID, options = {}) {
    const result = await call('POST', `/v1/babies/${babyID}/invites`, { token, body: options })
    if (result.status !== 200) throw new Error(`invite: ${result.status} ${JSON.stringify(result.body)}`)
    return result.body.code
  }

  async function close({ keep = false } = {}) {
    app.server.closeAllConnections?.()
    await new Promise((resolve) => app.server.close(resolve))
    if (dir && !keep) rmSync(dir, { recursive: true, force: true })
  }

  return { call, enrol, pushBaby, invite, close, dbPath, dir }
}

/** Runs a test body against its own server, and always tears it down. */
export async function withServer(options, run) {
  const server = await startServer(options)
  try {
    await run(server)
  } finally {
    await server.close()
  }
}
