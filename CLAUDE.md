# Baby Feed — notes for Claude

An iPhone app (SwiftUI, iOS 26+, SwiftData) for logging a newborn's feeds, diapers, weights, foods and
notes, plus a tiny self-hosted sync server on the family's Mac mini. **What to build next is in
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
  file added there joins the target automatically. Keep docs and config (e.g. `Config/*.xcconfig`) at the
  repo root.

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
- **One source of truth per number:** `FeedingGuidance.currentTarget`, `FeedSummary` and `DiaperTally`
  (plus `FeedCountdown` once Phase 1 lands). Screens call these; they never recompute the numbers.
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
- **Guidance, not orders.**
  - Every guidance number cites the AAP, CDC or WHO through `FoodGuidance.Source`; a test enforces the
    hosts.
  - The app never suggests a medicine dose.
  - A missed log is never presented as a problem with the baby.
- **Two taps to log a feed, one tap for a diaper.** Anything slower goes behind "+", not onto Today.

## Syncing and the server

- **A new synced type** follows ROADMAP.md Appendix A. On the app side that means the model, the DTO,
  `SyncEngine`, `SyncClient`, `BabyStore.removeLocally` and `DebugSeed`. On the server side it means
  `db.js`, `sync.js` and tests.
- **Deploy order:** the server goes out before any app build that needs it (ROADMAP.md Appendix B). The
  mini runs its own checkout at `~/baby-feed`.
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
  `Config/Server.local.xcconfig` (ROADMAP Phase 3b) is gitignored for that reason.
- `project.pbxproj` has an uncommitted `MARKETING_VERSION = 1.2`. Keep it when editing the project.
  The widget target is still at 1.0, and an extension's version must match its app's, so bump both
  together.
- In an xcconfig, `//` starts a comment anywhere on a line.
- `UIDevice.current.name` returns just "iPhone" on iOS 16 and later.
- Tests run inside the app (`TEST_HOST`), so `Bundle.main` is the app bundle.
- SwiftUI already has a `TimelineView`, so our timeline screen is `CareTimelineView`.
- **Commit messages** here explain *why* in plain prose, the way `git log` shows. Match that style.
