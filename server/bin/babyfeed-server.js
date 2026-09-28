#!/usr/bin/env node
// Entry point. Configuration and data both live OUTSIDE this repo, in
// ~/baby-feed-data, so the secret and the baby's log can never be committed by
// accident and a `git clean` can't delete them.
//
//   ~/baby-feed-data/.env            settings (address, port, who may enrol)
//   ~/baby-feed-data/babyfeed.db     the database (plus -wal / -shm)
//   ~/baby-feed-data/backups/        nightly copies
//   ~/baby-feed-data/logs/           stdout and stderr from launchd

import { readFileSync } from 'node:fs'
import { homedir } from 'node:os'
import { join } from 'node:path'
import { createApp } from '../src/server.js'
import { ENROLL_MODES } from '../src/auth.js'

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
// Loopback if nothing says otherwise, which is only right when every phone
// reaches this through Caddy. setup.sh writes BABYFEED_BIND=0.0.0.0, because
// the phones talk to it directly over the home Wi-Fi.
const host = env.BABYFEED_BIND || '127.0.0.1'
const dbPath = env.BABYFEED_DB || join(DATA_DIR, 'babyfeed.db')
// Only builds from before enrolment use this; newer ones never ask for it.
const setupSecret = env.BABYFEED_SETUP_SECRET || ''
// Who may set a brand-new phone up with nothing typed. See createApp.
const enroll = env.BABYFEED_ENROLL || 'lan'

function log(...args) {
  console.log(new Date().toISOString(), ...args)
}

if (!ENROLL_MODES.includes(enroll)) {
  log(`[error] BABYFEED_ENROLL must be one of ${ENROLL_MODES.join(', ')} — it's "${enroll}".`)
  process.exit(1)
}

const { server } = createApp({ dbPath, setupSecret, enroll, log })

const ENROLL_DESCRIPTIONS = {
  lan: 'a phone on the home Wi-Fi sets itself up with nothing typed',
  off: 'only by invite or recovery phrase',
  'lan+loopback': 'a phone on the home Wi-Fi, or anything on this Mac, sets itself up (testing only)',
}

server.listen(port, host, () => {
  log(`[babyfeed] listening on http://${host}:${port} — database ${dbPath}`)
  log(`[babyfeed] new phones: ${ENROLL_DESCRIPTIONS[enroll]} (BABYFEED_ENROLL=${enroll})`)
  if (enroll !== 'off' && (host === '127.0.0.1' || host === 'localhost' || host === '::1')) {
    log('[warn] Listening on loopback only, so phones on the Wi-Fi can\'t reach this server or set themselves up. '
      + 'Set BABYFEED_BIND=0.0.0.0 in ~/baby-feed-data/.env for home Wi-Fi.')
  }
})

for (const signal of ['SIGINT', 'SIGTERM']) {
  process.on(signal, () => {
    log(`[babyfeed] ${signal}, shutting down`)
    server.close(() => process.exit(0))
    // launchd's patience is not unlimited, and neither is a phone's.
    setTimeout(() => process.exit(0), 5000).unref()
  })
}
