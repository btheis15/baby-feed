// Pulling a long log onto a new phone.
//
// A phone that joins after a few months has thousands of rows to catch up
// on, and a pull is paged. Two things used to lose rows there: a table that
// filled its page while another didn't let the watermark jump past everything
// still unsent, and the first backup's rows (stamped a millisecond apart, all
// in one push) couldn't be paged past at all with a one-second overlap.

import test from 'node:test'
import assert from 'node:assert/strict'
import { withServer, uuid, iso } from './support.js'

/** Pulls the way the app does now: from each page's next_since, until done. */
async function pullAll(call, token, babyID, { limit } = {}) {
  const seen = {}
  let since = null
  for (let page = 0; page < 100; page++) {
    const query = new URLSearchParams({ baby_id: babyID })
    if (since) query.set('since', since)
    if (limit) query.set('limit', String(limit))
    const result = await call('GET', `/v1/sync/pull?${query}`, { token })
    assert.equal(result.status, 200)
    for (const [table, rows] of Object.entries(result.body)) {
      if (!Array.isArray(rows) || table === 'members') continue
      for (const row of rows) (seen[table] ??= new Set()).add(row.id)
    }
    assert.ok(result.body.next_since, 'every page says where the next one starts')
    since = result.body.next_since
    if (!result.body.has_more) return seen
  }
  throw new Error('pull never finished')
}

function feed(babyID, minutesAgo) {
  return { id: uuid(), baby_id: babyID, start_time: iso(-minutesAgo * 60_000), kind: 'formula',
    amount_ml: 90, note: '', logged_by_name: 'Brian', updated_at: iso() }
}

test('a first backup bigger than a page reaches the next phone whole', async () => {
  await withServer({}, async ({ call, enrol, pushBaby, invite }) => {
    const brian = await enrol('Brian')
    const babyID = await pushBaby(brian.token, 'Nora')

    // One push, as a first backup is: every row stamped a millisecond apart.
    const feeds = Array.from({ length: 1200 }, (_, i) => feed(babyID, i * 150))
    const pushed = await call('POST', '/v1/sync/push', { token: brian.token, body: { feeds } })
    assert.equal(pushed.body.applied.length, 1200)

    // A few weigh-ins stamped after all of them: the table that doesn't fill
    // its page must not drag the cursor past the one that does.
    const weights = [0, 1, 2].map((i) => ({ id: uuid(), baby_id: babyID, date: iso(-i * 86_400_000),
      grams: 3400 + i, note: '', updated_at: iso() }))
    await call('POST', '/v1/sync/push', { token: brian.token, body: { weights } })

    const annette = await enrol('Annette')
    const code = await invite(brian.token, babyID)
    const joined = await call('POST', '/v1/pair/invite', { token: annette.token, body: { code } })
    assert.equal(joined.status, 200)

    const seen = await pullAll(call, annette.token, babyID, { limit: 500 })
    assert.equal(seen.feeds.size, 1200)
    assert.equal(seen.weights.size, 3)
    assert.equal(seen.babies.size, 1)
  })
})

test('a page is cut at the same point for every table', async () => {
  await withServer({}, async ({ call, enrol, pushBaby }) => {
    const brian = await enrol('Brian')
    const babyID = await pushBaby(brian.token, 'Nora')
    await call('POST', '/v1/sync/push', {
      token: brian.token,
      body: { feeds: Array.from({ length: 30 }, (_, i) => feed(babyID, i)) },
    })
    const diaper = { id: uuid(), baby_id: babyID, time: iso(), kind: 'wet', note: '', updated_at: iso() }
    await call('POST', '/v1/sync/push', { token: brian.token, body: { diapers: [diaper] } })

    const first = await call('GET', `/v1/sync/pull?baby_id=${babyID}&limit=10`, { token: brian.token })
    assert.equal(first.body.has_more, true)
    const cutoff = new Date(first.body.next_since).getTime()
    for (const table of ['babies', 'feeds', 'weights', 'care_notes', 'diapers', 'solid_foods']) {
      for (const row of first.body[table]) {
        assert.ok(new Date(row.server_updated_at).getTime() <= cutoff, `${table} row past the cut`)
      }
    }
    // The diaper came after the tenth row, so it waits for a later page
    // rather than moving the cursor past the feeds in between.
    assert.equal(first.body.diapers.length, 0)
  })
})

test('an empty catch-up still says where it is', async () => {
  await withServer({}, async ({ call, enrol, pushBaby }) => {
    const brian = await enrol('Brian')
    const babyID = await pushBaby(brian.token, 'Nora')
    const since = iso(60_000)
    const result = await call('GET', `/v1/sync/pull?baby_id=${babyID}&since=${encodeURIComponent(since)}`,
      { token: brian.token })
    assert.equal(result.body.has_more, false)
    assert.equal(result.body.next_since, since, 'nothing new: the cursor stays where it was')
  })
})
