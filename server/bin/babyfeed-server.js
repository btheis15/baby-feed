#!/usr/bin/env node
// Entry point. Configuration and data both live OUTSIDE this repo, in
// ~/baby-feed-data, so the secret and the baby's log can never be committed by
// accident and a `git clean` can't delete them.
//
//   ~/baby-feed-data/.env            settings, including the setup secret
//   ~/baby-feed-data/babyfeed.db     the database (plus -wal / -shm)
//   ~/baby-feed-data/backups/        nightly copies
//   ~/baby-feed-data/logs/           stdout and stderr from launchd

import { readFileSync } from 'node:fs'
import { homedir } from 'node:os'
import { join } from 'node:path'
import { createApp } from '../src/server.js'

const DATA_DIR = process.env.BABYFEED_DATA_DIR || join(homedir(), 'baby-feed-data')

/** A deliberately small .env reader: KEY=value, # comments, no interpolation. */
function loadEnvFile(path) {
  let text
  try {
    text = readFileSync(path, 'utf8')
  } catch {
    return {}
  }
  const values = {}
  for (const line of text.split('\n')) {
    const trimmed = line.trim()
    if (!trimmed || trimmed.startsWith('#')) continue
    const eq = trimmed.indexOf('=')
    if (eq < 1) continue
    values[trimmed.slice(0, eq).trim()] = trimmed.slice(eq + 1).trim().replace(/^["']|["']$/g, '')
  }
  return values
}

const fileEnv = loadEnvFile(join(DATA_DIR, '.env'))
const env = { ...fileEnv, ...process.env }

const port = Number(env.BABYFEED_PORT || 8791)
// Loopback by default. Anything reaching this from outside the mini comes
// through Caddy, which terminates TLS; binding 0.0.0.0 would also answer plain
// HTTP on the LAN, and a token is not something to hand out over plain HTTP.
// BABYFEED_BIND=0.0.0.0 is there for trying it on the home network first.
const host = env.BABYFEED_BIND || '127.0.0.1'
const dbPath = env.BABYFEED_DB || join(DATA_DIR, 'babyfeed.db')
const setupSecret = env.BABYFEED_SETUP_SECRET || ''
// The bundle identifier Apple issues identity tokens for. Sign in with Apple
// stays switched off until this is set, so a misconfigured server refuses
// sign-ins rather than accepting tokens minted for some other app.
const appleAudience = env.BABYFEED_APPLE_BUNDLE_ID || 'com.babyfeed.BabyFeed'

function log(...args) {
  console.log(new Date().toISOString(), ...args)
}

if (!setupSecret) {
  log('[warn] BABYFEED_SETUP_SECRET is not set — no new phone can pair as owner.')
}

const { server } = createApp({ dbPath, setupSecret, log, appleAudience })

server.listen(port, host, () => {
  log(`[babyfeed] listening on http://${host}:${port} — database ${dbPath}`)
})

for (const signal of ['SIGINT', 'SIGTERM']) {
  process.on(signal, () => {
    log(`[babyfeed] ${signal}, shutting down`)
    server.close(() => process.exit(0))
    // launchd's patience is not unlimited, and neither is a phone's.
    setTimeout(() => process.exit(0), 5000).unref()
  })
}
