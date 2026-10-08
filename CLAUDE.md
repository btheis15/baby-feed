# Baby Feed — notes for Claude

An iPhone app (SwiftUI, iOS 26+, SwiftData) for logging a newborn's feeds, diapers, weights, foods,
notes and health (concerns, medicines, doctor visits), plus a tiny self-hosted sync server on the
family's Mac mini. **What to build next is in
[ROADMAP.md](ROADMAP.md)**: work one phase at a time, and update its status table when a phase is done.
[PLAN.md](PLAN.md) explains the product and the sources behind the feeding guidance.

It's designed for **one baby and one or two caregivers, at 3 a.m., one-handed**, and for the first year,
with newborn needs first.

## Layout

- `BabyFeed/`: the app.
  - `Models/`: SwiftData `@Model` types, plus pure guidance and stats code.
  - `Services/`: `FeedCoordinator`, `BabyStore`, reminders, alarm, Live Activity, and `Sync/`.
  - `Views/` and `Intents/`.
- `Shared/`: compiled into both the app and the widget (`FeedSnapshot`, `FeedKind`, `ElapsedText`…).
- `BabyFeedWidget/`: the widget and the Live Activity.
- `BabyFeedTests/`: Swift Testing.
- `server/`: Node 22.5+, no dependencies, SQLite via `node:sqlite`. **Not part of the Xcode project**, so
  if you're Claude in Xcode and can't see it, say so rather than guessing.
- `BabyFeed/`, `Shared/`, `BabyFeedWidget/` and `BabyFeedTests/` are file-system-synchronized groups: any
  file added there joins the target automatically. Keep docs and example config (`Config/`) at the
  repo root. The one config file inside `BabyFeed/` on purpose is the gitignored `ServerConfig.plist`.

## Build and test

- **App:** ⌘U, or
  `xcodebuild test -project BabyFeed.xcodeproj -scheme BabyFeed -destination 'platform=iOS Simulator,name=<an installed iPhone>'`
  (`xcrun simctl list devices available`).
- **Server:** `cd server && npm test`. Run it after any server change.
- Run the tests before calling anything done. The simulator's test runner has wedged before; if tests
  couldn't run, say so plainly. Never claim they passed.

## The rules that keep it consistent

- **Local-first.** Every screen reads SwiftData, and saving never waits on the network. `SyncEngine`
  pushes and pulls afterwards. Conflicts go through `SyncMerge`: the last writer wins by `updatedAt`, and
  deletes are soft (`softDelete()`), so a delete can reach the other phone.
- **One refresh path.** After data changes, call `FeedCoordinator.feedsDidChange(in:)`, or
  `settingsDidChange`. It updates the widget snapshot, the reminder, the alarm, the Live Activity and sync
  together. Don't refresh those piecemeal.
- **Days and times** come from `@Environment(\.calendar)`, `AppSettings.calendar` or
  `AppSettings.timeZone`, because a time zone can be pinned in Settings. Don't use `Calendar.current` or a
  bare `.formatted()` for user-facing days or clock times.
- **One source of truth per number:** `FeedingGuidance.currentTarget`, `FeedSummary`, `DiaperTally`
  and `FeedCountdown`. Screens call these; they never recompute the numbers.
- **Sheets** use `Mode { case new; case edit(Model) }`. App-level sheets go through `AppRouter.sheet`,
  one at a time (commit `0802233` explains why).
- **Models are listed once**, in `AppSchema.models`. Previews use `.modelContainer(.preview)`, and
  tests use `AppSchema.inMemoryContainer()`. A new `@Model` type goes in that list and nowhere
  else.
- **Minutes, not seconds.** Nothing ticks every second. Use `TimelineView(.everyMinute)` in the app, and
  the minute-precision `Text(.currentDate, format: …)` styles in the widget and Live Activity. Where
  the next feed stands always comes from `FeedCountdown`.
- **Never nest one `TimelineView` inside another.** In a List it loops the main thread at 100% before
  the first frame. Keep one ticking view per screen, and drive slower refreshes from a `@State` clock.
  Today's hero ticks on `.periodic(from:by: 60)`, so a nursing timer's minutes turn over from its start.
- **Guidance, not orders.**
  - Every guidance number cites the AAP, CDC or WHO through `FoodGuidance.Source`; a test enforces the
    hosts.
  - The app never suggests a medicine dose.
  - A missed log is never presented as a problem with the baby.
- **Two taps to log a feed, one tap for a diaper.** Anything slower goes behind "+", not onto Today.
- **Every log lands visibly.** After saving something new, call `toasts.logged(item, context:router:)`
  (the `ToastCenter` in the environment), after `FeedCoordinator` has saved, so the entry's ID is
  permanent by the time Edit uses it. Swipe deletes go through `toasts.delete(_:context:)`, which
  gives the Undo. A Delete button inside a sheet always confirms.
- **The Timeline is built from `TimelineItem`.** A new kind of entry adds a case there, and the
  compiler then lists every screen that has to handle it (row, editor, search, CSV).
- **A chart leads with its number.** Every chart (`ChartsView`, and the weight chart on the Baby tab)
  opens with a sentence stating the value. That sentence comes from `CareCharts`, built from the same
  series the chart draws. A day with nothing logged is a gap, never a zero bar. The plain numbers
  (`TrendsView`) stay underneath.

## Syncing and the server

- **A new synced type** follows ROADMAP.md Appendix A. On the app side that means the model, the DTO,
  `SyncEngine` (push, merge, `queueEverything`, `table(of:)`, `pendingCount`), `SealedSync` (seal and
  open), `SyncClient`,
  `BabyStore.removeLocally`/`rowCount`, `DebugSeed`, and a `TimelineItem` case. On the server side it
  means `db.js`, `sync.js` and tests.
- **A new column on an existing synced table** goes through `COLUMN_ADDITIONS` + `LATE_COLUMNS` on the
  server, and on the app a DTO that always sends the key (null included) and applies it only when it
  was received (see `CareNoteDTO.concernID`).
- **Medicines:** the app records what was given and never suggests a dose. `DoseDraft` only ever
  offers the amount a parent entered, and notices never block Save.
- **Deploy order:** the server goes out before any app build that needs it (ROADMAP.md Appendix B). The
  mini runs its own checkout at `~/baby-feed`.
- **Sealed (end-to-end encrypted) logs** are every baby created from Phase 9 on (`Baby.isSealed`).
  Their rows go up only as `SealedLog` boxes through `SealedSync`, never as readable DTOs, and never
  to a server without the `sealed` feature. Babies from before stay readable; never convert one
  without the parent asking. The baby key lives in `BabyKey` and leaves the phone only in a Share
  link or locked with the recovery phrase. A new synced type needs its case in `SealedSync` too.
- **Joining is external only.** Share links carry `SyncEngine.joinAddress` (the public address),
  never the home one, and a link naming a home-network address isn't followed.
- **Connecting** goes through `SyncEngine.ensureConnected(_:)`, one operation at a time. Nothing
  reaches for the network on a cold launch unless the parent asked for it before (so the Local
  Network prompt never appears unexplained). A phone that joined by QR never makes an identity of
  its own, and a recovery phrase is never replaced without the parent asking.
- **New server tests** go in their own files and use `server/test/support.js` (`startServer`,
  `withServer`). The older files each share one rate limiter.

## Never change these

Changing them breaks existing installs, pairing or widgets:

- the bundle IDs `com.babyfeed.BabyFeed` and `.Widget`;
- the URL scheme `babyfeed://`;
- the App Group `group.com.briantheis.babyfeed`;
- the Keychain services `com.babyfeed.BabyFeed` and `com.babyfeed.BabyFeed.recovery`;
- the UserDefaults keys;
- the widget kind `LastFeedWidget`;
- the notification ID `babyfeed.nextFeed`;
- the SwiftData model class names;
- the target and module names.

## Gotchas

- **The GitHub repo is public.** Never commit an internet-reachable hostname (DuckDNS), a token or a key.
  `BabyFeed/ServerConfig.plist`, the server this build syncs with, is gitignored for that reason
  (`Config/ServerConfig.example.plist` shows the shape).
- `project.pbxproj` has an uncommitted `MARKETING_VERSION = 1.4` on both the app and the widget. Keep
  it when editing the project. An extension's version must match its app's, so bump both together.
- In an xcconfig, `//` starts a comment anywhere on a line.
- `UIDevice.current.name` returns just "iPhone" on iOS 16 and later.
- Tests run inside the app (`TEST_HOST`), so `Bundle.main` is the app bundle.
- SwiftUI already has a `TimelineView`, so our timeline screen is `CareTimelineView`.
- In a List section header, `.foregroundStyle(.primary)` still comes out grey: it resolves against
  the header's own style. Use `Color.primary`.
- **Screenshots and sync checks from the command line:** debug builds accept `--seed-demo-data`,
  `--open-tab timeline|charts|health|baby|settings`, `--open-sheet add|share`, `--debug-nursing <minutes ago>`,
  `--debug-open-url <babyfeed://…>`,
  `--debug-connect`, `--debug-invite`, `--debug-restore <phrase>`, `--debug-name <name>` and
  `--debug-log-diaper` (`xcrun simctl launch <device> com.babyfeed.BabyFeed …`; results in
  `xcrun simctl spawn <device> log show`). Point `ServerConfig.plist` at a local server started with
  `BABYFEED_ENROLL=lan+loopback` to test sharing between two simulators.
- **Commit messages** here explain *why* in plain prose, the way `git log` shows. Match that style.
