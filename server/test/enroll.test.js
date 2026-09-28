// Enrolment: a new phone on the home Wi-Fi setting itself up with nothing typed.
//
// This is the only route that makes a caregiver out of nothing, so most of
// what's tested here is who it refuses: loopback (where Caddy or a tunnel
// connects from), anything with a proxy header, anything that isn't JSON, and
// everybody once it's switched off. The tests can only connect over loopback,
// so the servers that should accept them run in 'lan+loopback' mode.

import { test } from 'node:test'
import assert from 'node:assert/strict'
import { rmSync } from 'node:fs'
import { hasProxyHeaders, isLanAddress } from '../src/auth.js'
import { mintKey, startServer, withServer } from './support.js'

test('the home network is private IPv4, link-local and local IPv6 — never loopback, Tailscale or the internet', () => {
  const table = [
    ['192.168.6.164', true],
    ['::ffff:192.168.6.164', true],
    ['10.0.0.7', true],
    ['172.16.0.1', true],
    ['172.31.255.255', true],
    ['172.32.0.1', false],
    ['169.254.10.20', true],
    ['fe80::1%en0', true],
    ['fd00::1', true],
    ['127.0.0.1', false],
    ['::1', false],
    ['::ffff:127.0.0.1', false],
    ['100.64.0.1', false],
    ['8.8.8.8', false],
    ['2001:db8::1', false],
    ['192.168.1', false],
    ['192.168.1.300', false],
    ['not an address', false],
    ['', false],
    [undefined, false],
  ]
  for (const [address, expected] of table) {
    assert.equal(isLanAddress(address), expected, String(address))
  }
  assert.equal(isLanAddress('127.0.0.1', { allowLoopback: true }), true)
  assert.equal(isLanAddress('::1', { allowLoopback: true }), true)
  assert.equal(isLanAddress('8.8.8.8', { allowLoopback: true }), false, 'allowing loopback allows nothing else')
})

test('a proxy is spotted whichever header it uses', () => {
  for (const header of ['x-forwarded-for', 'forwarded', 'x-real-ip', 'cf-connecting-ip', 'true-client-ip']) {
    assert.ok(hasProxyHeaders({ [header]: '203.0.113.9' }), header)
  }
  assert.ok(!hasProxyHeaders({ 'content-type': 'application/json' }))
  assert.ok(!hasProxyHeaders(undefined))
})

test('a phone on the home network gets a token with nothing typed', async () => {
  await withServer({}, async ({ call }) => {
    const enrolled = await call('POST', '/v1/pair/enroll', {
      body: { display_name: 'Brian', device_name: 'iPhone' },
    })
    assert.equal(enrolled.status, 200)
    assert.ok(enrolled.body.token)
    assert.ok(enrolled.body.user_id)
    assert.ok(enrolled.body.server_id)

    const me = await call('GET', '/v1/me', { token: enrolled.body.token })
    assert.equal(me.status, 200)
    assert.equal(me.body.display_name, 'Brian')
    assert.deepEqual(me.body.babies, [], 'a new caregiver is on nothing until they push a baby or are invited')
    assert.equal(me.body.recovery_key.exists, false)
  })
})

test('loopback is not the home network unless the server is told otherwise', async () => {
  await withServer({ enroll: 'lan' }, async ({ call }) => {
    const refused = await call('POST', '/v1/pair/enroll', { body: { display_name: 'Via Caddy' } })
    assert.equal(refused.status, 403)
    assert.equal(refused.body.code, 'enroll_lan_only')

    const health = await call('GET', '/v1/health')
    assert.equal(health.body.enroll, 'lan')
    assert.equal(health.body.enroll_available, false)
    assert.equal(health.body.paired_devices, 0, 'a refusal creates nothing')
  })
})

test('anything that came through a proxy is refused, even from an address that would be allowed', async () => {
  await withServer({}, async ({ call }) => {
    for (const header of ['x-forwarded-for', 'forwarded', 'x-real-ip', 'cf-connecting-ip']) {
      const refused = await call('POST', '/v1/pair/enroll', {
        body: { display_name: 'Outside' },
        headers: { [header]: '203.0.113.9' },
      })
      assert.equal(refused.status, 403, header)
      assert.equal(refused.body.code, 'enroll_lan_only', header)
    }
    const health = await call('GET', '/v1/health', { headers: { 'x-forwarded-for': '203.0.113.9' } })
    assert.equal(health.body.enroll_available, false)
    assert.equal(health.body.paired_devices, 0)
  })
})

test('enrolment can be switched off', async () => {
  await withServer({ enroll: 'off' }, async ({ call }) => {
    const refused = await call('POST', '/v1/pair/enroll', { body: { display_name: 'Anyone' } })
    assert.equal(refused.status, 403)
    assert.equal(refused.body.code, 'enroll_off')
    assert.equal((await call('GET', '/v1/health')).body.enroll, 'off')
  })
})

test('a body that is not JSON is refused, so a web page on the same Wi-Fi cannot enrol anybody', async () => {
  await withServer({}, async ({ call }) => {
    for (const contentType of ['text/plain', 'application/x-www-form-urlencoded', 'multipart/form-data; boundary=x']) {
      const refused = await call('POST', '/v1/pair/enroll', { body: 'display_name=x', contentType })
      assert.equal(refused.status, 415, contentType)
    }
    assert.equal((await call('GET', '/v1/health')).body.paired_devices, 0)
  })
})

test('enrolment has a rate limit of its own', async () => {
  await withServer({ enrollRateLimit: { limit: 2, windowMs: 60_000 } }, async ({ call }) => {
    const statuses = []
    for (let i = 0; i < 3; i++) {
      statuses.push((await call('POST', '/v1/pair/enroll', { body: { display_name: `Phone ${i}` } })).status)
    }
    assert.deepEqual(statuses, [200, 200, 429])
  })
})

test('a phone that is already paired gets itself back, not a second identity', async () => {
  await withServer({}, async ({ call, enrol }) => {
    const first = await enrol('Brian')
    const again = await call('POST', '/v1/pair/enroll', {
      token: first.token,
      body: { display_name: 'Brian again' },
    })
    assert.equal(again.status, 200)
    assert.equal(again.body.token, null, 'the phone keeps the token it has')
    assert.equal(again.body.user_id, first.user_id)
    assert.equal((await call('GET', '/v1/health')).body.paired_devices, 1)
  })
})

test('an enrolled phone owns the baby it pushes, and can invite someone to it', async () => {
  await withServer({}, async ({ call, enrol, pushBaby }) => {
    const brian = await enrol('Brian')
    const noraID = await pushBaby(brian.token, 'Nora')

    const me = await call('GET', '/v1/me', { token: brian.token })
    assert.equal(me.body.babies.length, 1)
    assert.equal(me.body.babies[0].id, noraID)
    assert.equal(me.body.babies[0].role, 'owner')

    const invite = await call('POST', `/v1/babies/${noraID}/invites`, { token: brian.token, body: {} })
    assert.equal(invite.status, 200)
    assert.equal(invite.body.code.length, 6)
  })
})

test('a phrase can ride along with enrolment, but one already on the server is refused rather than merged', async () => {
  await withServer({}, async ({ call, enrol }) => {
    const { hash } = mintKey()
    const brian = await enrol('Brian', { key_hash: hash })
    const me = await call('GET', '/v1/me', { token: brian.token })
    assert.equal(me.body.recovery_key.exists, true)
    assert.ok(!JSON.stringify(me.body).includes(hash), 'the hash is never echoed back')

    // Knowing a hash proves nothing — the phrase itself goes to /v1/recover.
    const copycat = await call('POST', '/v1/pair/enroll', {
      body: { display_name: 'Copycat', key_hash: hash },
    })
    assert.equal(copycat.status, 409)
    assert.equal(copycat.body.code, 'key_exists')
    assert.equal((await call('GET', '/v1/health')).body.paired_devices, 1, 'and nothing was created')

    for (const bad of ['nothex', 'a'.repeat(63), 'A'.repeat(64)]) {
      const refused = await call('POST', '/v1/pair/enroll', { body: { display_name: 'X', key_hash: bad } })
      assert.equal(refused.status, 400, bad)
    }
  })
})

test('health says what this server can do', async () => {
  await withServer({}, async ({ call }) => {
    const health = await call('GET', '/v1/health')
    assert.equal(health.status, 200)
    assert.equal(health.body.ok, true)
    assert.equal(health.body.service, 'babyfeed-server')
    assert.equal(health.body.api, 2)
    for (const feature of ['enroll', 'join_as_member', 'member_invites', 'account_keys']) {
      assert.ok(health.body.features.includes(feature), feature)
    }
    assert.match(health.body.server_id, /^[0-9A-F-]{36}$/)
    assert.equal(health.body.enroll, 'lan+loopback')
    assert.equal(health.body.enroll_available, true)
  })
})

test('the server id belongs to the database: the same after a restart, different for a new database', async () => {
  const first = await startServer()
  try {
    const before = (await first.call('GET', '/v1/health')).body.server_id
    await first.close({ keep: true })

    const restarted = await startServer({ dbPath: first.dbPath })
    const after = (await restarted.call('GET', '/v1/health')).body.server_id
    await restarted.close()

    const fresh = await startServer()
    const other = (await fresh.call('GET', '/v1/health')).body.server_id
    await fresh.close()

    assert.equal(after, before)
    assert.notEqual(other, before)
  } finally {
    rmSync(first.dir, { recursive: true, force: true })
  }
})

test('an unknown enrolment mode is refused at startup rather than guessed at', async () => {
  await assert.rejects(startServer({ enroll: 'everyone' }), /enroll must be one of/)
})
