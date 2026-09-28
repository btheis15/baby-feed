# Baby Feed sync server

The small server the app's sharing runs through. It holds only what two phones
need to agree on, it runs on a Mac mini in the house, and it belongs to nobody
else. No account, no company, no third-party backend.

It is **self-contained**: its own directory, its own launchd jobs, its own
ports, its own database, its own Caddy config. It reads nothing and writes
nothing belonging to anything else on the machine it runs on.

- **No dependencies.** Node 22.5+ has SQLite built in (`node:sqlite`), and the
  HTTP server is Node's own. There is nothing to `npm install` and nothing to
  keep patched.
- **One file of data.** `~/baby-feed-data/babyfeed.db`. Backing it up is
  copying a file.
- **Its own everything.** Own directory, own `com.babyfeed.*` launchd jobs, own
  ports, own database, own Caddy binary and config. Nothing it does can affect
  anything else on the machine, and nothing else can affect it.

## Setting it up on the Mac mini

```sh
cd ~/baby-feed/server
./scripts/install-launchd.sh
```

That creates `~/baby-feed-data` and its settings, installs two launchd jobs
(`com.babyfeed.server`, the nightly `com.babyfeed.backup`), starts the server
and checks it answers. There is no code to write down.

The launchd jobs expect this checkout at `~/baby-feed` on the mini.

## Getting the phones on it

1. **First phone**, on the home Wi-Fi: open the app and add the baby. The
   phone sets itself up with the server (`POST /v1/pair/enroll`), backs the log
   up, and shows your **recovery phrase** to write down.
2. **Every other phone**: on a phone that has the log, tap **Share**. Point the
   other phone's Camera at the QR and tap the banner, or send the link, or read
   the six characters out. It joins on its own. Any caregiver can share, not
   only whoever started the log.
3. **A replacement phone, when every phone is gone**: *Restore with recovery
   phrase*.

**There are no user accounts.** The thing that exists on the server is a
baby's log, and the only question it ever asks is who may see it. A caregiver
is an id, a name the phone chose, and a list of babies they're on — no email,
no password. The name next to a feed is stored on the feed, written by the
phone that logged it.

A phone gets its token one of four ways:

- **Enrolling from the home network.** Nothing typed. It's refused unless the
  connection comes straight from a private address on the Wi-Fi — not through
  Caddy, not from loopback, not with a proxy header — so opening the server to
  the internet later doesn't open sign-up to it. What it creates is an empty
  caregiver who can see nothing until they push a baby of their own or are
  invited to one. `BABYFEED_ENROLL=off` turns it off.
- **An invite**, from anyone already on that baby's log. A phone that's already
  paired joins as the caregiver it already is, so joining a second child never
  costs it the first.
- **A recovery phrase.** One per person, covering every log they're on. The
  server holds only its hash. Older builds made one key per baby instead; those
  still work.
- **The setup secret**, for builds from before enrolment. Spent on first use.

## Reaching it from outside the house

**Home Wi-Fi only** (this is how it's set up now). `BABYFEED_BIND=0.0.0.0` in
`~/baby-feed-data/.env`, and the app reaches the mini by its Bonjour name,
`http://<the mini's local hostname>.local:8791` (System Settings → General →
Sharing shows it). Use the `.local` name rather than an IP address: it
survives the router handing the mini a new address, and it's what App
Transport Security's local-networking exception (`NSAllowsLocalNetworking`) is
written for, whereas plain http to a bare IP isn't reliably allowed. A DHCP
reservation for the mini doesn't hurt either. The app allows plain `http` for private addresses only, so a token can
never go unencrypted across the internet. Feeds logged away from home sync
when you get back.

**Never forward a router port to 8791.** That is the plain-http server itself.
If it's ever reachable from outside, it's only through Caddy on 9444, which
terminates TLS — and enrolment refuses anything that comes through Caddy.

**Anywhere**, with HTTPS and a hostname of its own:

1. Create a DuckDNS hostname at [duckdns.org](https://www.duckdns.org) — any
   name — and copy your token.
2. Put both in `~/baby-feed-data/.env`:

   ```
   BABYFEED_HOSTNAME=yourname.duckdns.org
   BABYFEED_DUCKDNS_TOKEN=…
   ```

3. Forward a port on the router: **external 4443 → this Mac, port 9444**.
4. `./scripts/install-caddy.sh`

That starts two more jobs — `com.babyfeed.caddy` and `com.babyfeed.duckdns`,
which keeps the hostname pointed at the house as the residential IP rotates —
gets a certificate, and prints the address to type into the app
(`https://yourname.duckdns.org:4443`).

### Why a port number in the address, and why a custom Caddy

Two things about a house make this less obvious than it looks:

- **The external port isn't 443.** If anything else on the machine is already
  behind 443, two services can't share it without one fronting the other, which
  is the coupling this project avoids. So Baby Feed takes its own external port.
  It's typed into the app once and then lives in a QR code.
- **Getting a certificate needs the DNS challenge.** The HTTP challenge needs
  inbound port 80, which Comcast blocks on residential lines. The TLS-ALPN
  challenge needs inbound 443 pointed at *this* Caddy, which it isn't. That
  leaves DNS-01, and it needs a DuckDNS provider module the Homebrew Caddy does
  not ship. `scripts/fetch-caddy.sh` downloads a build that has it into this
  project's own `bin/`, where `brew upgrade caddy` can't touch it.

## Day to day

```sh
# Is it up?
curl -s http://127.0.0.1:8791/v1/health

# Logs
tail -f ~/baby-feed-data/logs/server.log
tail -f ~/baby-feed-data/logs/server.error.log

# Restart after pulling a change
launchctl kickstart -k gui/$(id -u)/com.babyfeed.server

# Back up right now
./scripts/backup.sh

# Tests
node --test test/*.test.js

# Take it all off the machine (keeps the database)
./scripts/uninstall-launchd.sh
```

Backups are nightly at 03:30 into `~/baby-feed-data/backups/`, fourteen days
kept, taken with SQLite's `.backup` so a copy is never torn mid-write.

## What it stores

Babies, feeds, weights, care notes, diapers and solid foods, and the health
records: concerns, medicines, doses given and doctor visits. They're the same
shapes the app has in `Services/Sync/SyncDTOs.swift`, which is why the JSON goes
straight into a table with no translation. Medicine amounts are whatever a
parent typed; nothing here suggests a dose. Plus caregivers, the phones they've
paired (token hashes only), invite codes, recovery phrase hashes, a random
`server_id` (so a phone can tell a reset server from a revoked token), and a
change feed recording who did what.

It does **not** store: reminder settings, units, time zone, learned bottle
amounts, or anything else that is a preference of one phone rather than a fact
about the baby.

## How syncing works

Each phone's own SwiftData store stays the source of truth. The server is a
meeting point, not an authority.

- **Push** — every row carries `updated_at`, a soft `deleted_at` and a local
  `needs_upload` flag. Rows with the flag set go up on every change and every
  foreground.
- **Pull** — the phone asks for rows the server has touched since its
  watermark, per baby, and hands each to `SyncMerge`.
- **Conflicts** — last writer wins by `updated_at`. On a tie, whoever already
  has the row keeps it: the phone keeps an un-pushed local edit, the server
  keeps what it stored. Both ends implement the same rule and both are tested.
- **Deletes** are soft, so a row deleted on one phone can't be resurrected by
  the other phone pushing its stale copy.
- **Watermarks** come from a server clock that never repeats a millisecond and
  never goes backwards, so two phones pushing at the same instant can't hide a
  row from each other's next pull.
- **Paging.** A pull returns up to 500 rows a table. If any table fills its
  page, every table is cut at the same point, and `next_since` says exactly
  where the next page starts, so a phone joining a long log gets all of it.
- **New columns.** A column added to a table phones already sync goes in
  `COLUMN_ADDITIONS` (db.js, applied on open, recorded in `PRAGMA user_version`)
  and `LATE_COLUMNS` (sync.js). A late column is written only when a row carries
  its key, so an older app that doesn't know the field can't wipe it.

## API

Everything is under `/v1`. All of it needs `Authorization: Bearer <token>`
except `/v1/health`, the three pairing routes and `/v1/recover`.

| Route | What it does |
|---|---|
| `GET /v1/health` | Liveness, row counts, `api`, `server_id`, `features`, the `tables` it stores and its `schema_version`, and whether a new phone could enrol from where you're asking (`enroll_available`). No token. |
| `POST /v1/pair/enroll` | A new phone on the home Wi-Fi, nothing typed. JSON only. Optional `key_hash` registers the person's recovery phrase in the same step. With a token, returns the same caregiver (`token: null`). |
| `POST /v1/pair/invite` | Join with an invite code. With a token, joins as the caregiver this phone already is (`token: null`); re-scanning a code for a log you're on spends nothing. |
| `POST /v1/pair/claim` | Builds from before enrolment: the first phone, with the setup secret. Single use. |
| `POST /v1/recover` | Redeem a recovery phrase (person) or an older per-baby key. Returns every log the phrase covers. |
| `GET /v1/me` | This caregiver, the babies they're on, whether they have a recovery phrase, and the `server_id`. |
| `POST /v1/me` | Change the display name (reaches the other phone). |
| `POST /v1/me/recovery` | Register this person's phrase hash. Replacing an existing one needs `replace: true`. |
| `POST /v1/me/recovery/check` | Does the phrase on this phone match the one the server knows? |
| `GET /v1/devices`, `DELETE /v1/devices/:id` | List and revoke paired phones. |
| `POST /v1/babies/:id/invites` | Any caregiver on the log creates a code. |
| `GET /v1/babies/:id/invites`, `DELETE …/:code` | List and revoke codes: all of them for the owner, your own for anyone else. |
| `POST /v1/babies/:id/recovery`, `GET …` | Older per-baby keys: the owner registers one; any member can see whether one exists. |
| `GET /v1/babies/:id/members` | Who's on this log. |
| `DELETE /v1/babies/:id/members/:userID` | Remove someone, or leave. |
| `POST /v1/sync/push` | Rows up. Per-row applied/rejected, with a `code` on each rejection (`malformed`, `not_a_member`). |
| `GET /v1/sync/pull?baby_id=&since=` | Rows down, since a watermark; `has_more` and `next_since` for the next page. |
| `GET /v1/changes?baby_id=&since_seq=` | Who changed what. |

A baby becomes shared by being pushed: the phone that first pushes it becomes
its owner. There is no separate "start sharing" call that could get out of step
with that.

## Cross-caregiver notifications

Not wired up. `/v1/changes` is the half that had to exist on the server — it
says who logged what, and whether it was you — so telling the other phone
"Annette logged a feed" is now a client change and an APNs key, not a schema
change. Baby Feed needs its own APNs auth key for its own bundle ID.
