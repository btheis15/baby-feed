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

That creates `~/baby-feed-data`, prints the **setup code** for the first
iPhone, installs two launchd jobs (`com.babyfeed.server`, the nightly
`com.babyfeed.backup`), starts the server and checks it answers.

The setup code is also in `~/baby-feed-data/.env`. You need it once.

## Getting the phones on it

1. **First phone** — Settings → Caregivers & sync → Set up sharing → *This is
   the first phone*. Enter the server address and the setup code.
2. **Second phone** — on the first phone, *Invite another caregiver*. Point the
   second phone's Camera at the QR code and tap the banner, or send the link,
   or read the six characters out. Either way it lands on the join screen with
   everything filled in.

Nothing else pairs. There is no open sign-up endpoint to defend.

## Reaching it from outside the house

**Home Wi-Fi only** (this is how it's set up now). `BABYFEED_BIND=0.0.0.0` in
`~/baby-feed-data/.env`, and the server address in the app is
`http://<the mini's LAN address>:8791`. The app allows plain `http` for private
addresses only, so a token can never go unencrypted across the internet. Feeds
logged away from home sync when you get back. Nothing else to set up.

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

Babies, feeds, weights and care notes — the same shapes the app already had in
`Services/Sync/SyncDTOs.swift`, which is why the JSON goes straight into a table
with no translation. Plus caregivers, the phones they've paired, invite codes,
and a change feed recording who did what.

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

## API

Everything is under `/v1`. All of it needs `Authorization: Bearer <token>`
except `/v1/health` and the two pairing routes.

| Route | What it does |
|---|---|
| `GET /v1/health` | Liveness, and row counts. No token. |
| `POST /v1/pair/claim` | First phone, with the setup secret. Returns a token. |
| `POST /v1/pair/invite` | Any later phone, with an invite code. |
| `GET /v1/me` | This caregiver and the babies they're on. |
| `POST /v1/me` | Change the display name (reaches the other phone). |
| `GET /v1/devices`, `DELETE /v1/devices/:id` | List and revoke paired phones. |
| `POST /v1/babies/:id/invites` | Owner creates a code. |
| `GET /v1/babies/:id/invites`, `DELETE …/:code` | List and revoke codes. |
| `GET /v1/babies/:id/members` | Who's on this log. |
| `DELETE /v1/babies/:id/members/:userID` | Remove someone, or leave. |
| `POST /v1/sync/push` | Rows up. Per-row applied/rejected. |
| `GET /v1/sync/pull?baby_id=&since=` | Rows down, since a watermark. |
| `GET /v1/changes?baby_id=&since_seq=` | Who changed what. |

A baby becomes shared by being pushed: the phone that first pushes it becomes
its owner. There is no separate "start sharing" call that could get out of step
with that.

## Cross-caregiver notifications

Not wired up. `/v1/changes` is the half that had to exist on the server — it
says who logged what, and whether it was you — so telling the other phone
"Annette logged a feed" is now a client change and an APNs key, not a schema
change. Baby Feed needs its own APNs auth key for its own bundle ID.
