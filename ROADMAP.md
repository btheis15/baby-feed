# Baby Feed — Roadmap

What to build next, in the order to build it. First the everyday loop a parent lives in at 3 a.m.:
a countdown to the next feed, logging that visibly lands, one timeline of everything, and the first
weeks' "is she getting enough?". Then sharing that's just "tap Share, scan the QR". Then the start
of **Baby Care**: health concerns, medicines, doctor visits and charts.

Written 2026-09-28 against branch `sync-server` (`cde902e`) after a full audit of the app and the
server. Line numbers drift; file and symbol names are what to trust.

## Who it's for

Parents of a **newborn**. Tracking matters most in the first weeks, when feeds, wet diapers and
getting back to birth weight are what the pediatrician asks about. People will use this hard
through the first months, steadily until about the first birthday, and only now and then after
that. So:

- Design every screen for **one baby, one or two caregivers, at 3 a.m., one-handed**. Twins still
  work (the app already supports more than one baby), but no screen is designed around several.
- Newborn needs come first. Older-baby features (solids, month-long charts) come second.
- When logging tapers off after the first year, the app gets **quieter, not naggier**: no
  "OVERDUE 3 days".

---

## How to use this with Claude

**In Xcode** (the Claude coding assistant):

1. Start a fresh conversation for each phase. Attach `CLAUDE.md` and `ROADMAP.md` (both at the repo
   root, next to `PLAN.md`), or ask Claude to read them first.
2. Paste the phase's **Prompt** (at the end of each phase).
3. Review the diff, run the tests (⌘U), try it on your phone, then commit.
4. Claude updates the status table at the end of each phase.

**The server** (`server/`) isn't part of the Xcode project, so Claude in Xcode may not see it. Do
server work with Claude Code in Terminal: `cd ~/Documents/baby-feed && claude`.

If a phase is too big for one sitting, do its numbered steps (1.1, 1.2…) one at a time and commit
after each.

## Status

| Phase | What | Touches | Status |
|---|---|---|---|
| 0 | Safety net: tests green, previews render | app | **Done** 2026-09-28: 190 tests pass; one shared model list; `removeLocally` and the debug seed cover every type |
| 1 | Today: a countdown, minutes not seconds, less battery | app, widget | Not started |
| 2 | Logging that visibly lands, and one Timeline | app | Not started |
| 3a | Sharing without credentials: server | server | **Done.** Merged to `main` in PR #2 and running on the mini since 2026-09-28 (`/v1/health` reports `"api":2`, `"enroll":"lan"`) |
| 3b | Sharing without credentials: app | app | Not started (3a is live, so nothing blocks it) |
| 4 | The first weeks: getting enough, nursing side and timer, dark at night | app, widget | Not started |
| 5 | Health for the first year: concerns, medicines, doctor visits | app, server | Not started |
| 6 | Charts, numbers first | app | Not started |
| 7 | Copy and docs refresh | app, docs | Not started |
| 8 | Rename to "Baby Care" | app | Optional (decided to keep "Baby Feed" for now) |
| Later | Sync away from home, push notifications, sleep, more | | [Later](#later-directional) |

## Decisions already made

These were settled with Brian. Don't reopen them in a phase; raise a question instead.

- **No typing to connect.** The server address comes from the build. The first phone sets itself up
  on the home Wi‑Fi, and every other phone joins by scanning a QR. Any caregiver can share.
- **One recovery phrase per parent**, shown once when you add your baby. It uses the same
  24-character format as today's recovery key.
- **The name stays "Baby Feed"** for now (Phase 8 is optional).
- **Sync is home‑Wi‑Fi only for now.** Away-from-home sync is a later phase.
- **No in-app QR scanner.** The Camera app reads the QR and opens Baby Feed, so no camera
  permission is needed.
- **Charts come back numbers-first.** Commit `ce11c14` removed Swift Charts because "charts made a
  sleep-deprived parent squint to read an amount". Every chart leads with a sentence stating the
  value.
- **The app never suggests a medicine dose.** It records what was given.

## Principles for every phase

1. **Two taps to log a feed, one tap for a diaper.** Everything else sits behind one "+".
2. **Minutes, never seconds.** Nothing in the app, widget or Live Activity ticks every second.
3. **Today stays uncluttered:** the countdown, the two things logged most (feeds and diapers), one
   "+", and a short summary.
4. **Forgiving:** undo instead of "are you sure?"; everything editable; backdating is normal.
5. **Local-first:** saving never waits on the network, and sync catches up.
6. **Guidance, not orders:** numbers cite the AAP, CDC or WHO; the pediatrician wins; a missed log
   is never treated as a sick baby.
7. **One source of truth per number** (`FeedCountdown`, `FeedingGuidance.currentTarget`,
   `DiaperTally`…), so two screens can never disagree.
8. **Every synced type follows [Appendix A](#appendix-a--adding-a-synced-type)**, and the server
   deploys before the app.

---

## Where it ends up

Tabs: **Today · Timeline · Health · {baby's name} · Settings**. Health arrives in Phase 5; until
then there are four tabs, and History becomes Timeline in Phase 2.

**Today** in the first weeks. The "Getting enough?" block shows for about 6 weeks (Phase 4), and
"Right now" arrives with Phase 5.

```
┌──────────────────────────────────────┐
│ Nora · 9 days                [Share] │
│ ┌──────────────────────────────────┐ │
│ │          NEXT FEED IN            │ │
│ │            1h 20m                │ │  ← the only thing that ticks,
│ │        around 5:10 PM            │ │    once a minute
│ │ Last fed 2:10 PM · Nursing 15 min│ │
│ │ Left · 1h 40m ago                │ │
│ └──────────────────────────────────┘ │
│ [Formula 2 oz][Breast 2 oz][Nurse ▸R]│  2 taps; nursing suggests the next side
│ [   Wet   ][  Dirty  ][   Both   ]   │  1 tap, then a toast with Undo
│ GETTING ENOUGH?        last 24 hours │
│  ✓ 7 wet   ✓ 4 dirty   ✓ 9 feeds     │
│  Weight: 7 lb 1 oz · −2% from birth  │
│  (most babies are back by day 10–14) │
│ [ +  Log something else            ] │
│ TODAY SO FAR                       › │
│  14 oz of ~18 oz ▓▓▓▓▓▓░░░ · 6 feeds │
│ RECENT                               │
│  Nursing · 15 min · Left   2:10 PM   │
│  Wet diaper                1:55 PM   │
│                  See all in Timeline │
└──────────────────────────────────────┘
 accessory: Next feed in 1h 20m · 5:10 PM   (+)
```

The hero has three other states:

```
OVERDUE (up to one interval late)       QUIET (logging has stopped or a feed was missed)
│          OVERDUE           │           │   No feed logged since 9:40 AM    │
│            25m             │  (red)    │          [ Log a feed ]           │
│     was due at 5:10 PM     │           │   (calm, and no alarm re-firing)  │

NURSING (a timer is running, Phase 4)
│   NURSING · LEFT · 12 min   │
│ [Switch to right] [Done]    │
```

**Sharing** (Phase 3):

```
Phone A: Today → [Share]          Phone B: Camera → banner → Baby Feed
┌──────────────────────────┐      ┌──────────────────────────┐
│ Share Nora's log         │      │ Joining Nora's log…      │
│   ┌──────────────┐       │      │            ↓             │
│   │   ▓▓ QR ▓▓   │       │      │ You're in.               │
│   └──────────────┘       │      │ What should we call you? │
│ On the other iPhone,     │      │ [Mom][Dad][Grandma][...] │
│ open the Camera and      │      │ [Skip]            [Done] │
│ point it here.           │      └──────────────────────────┘
│ Code D8W AQK · 24 hours  │
│ [ Send link ]            │
│ ✓ Annette's iPhone joined│
└──────────────────────────┘
```

---

## Phase 0 — Safety net

**Goal.** A green test run you can trust, and previews that render, before any behavior changes.

**Changes**

0.1 **Run the whole suite** (⌘U) and keep it green. ✅
- On 2026-09-28 all 188 existing tests passed on the iPhone 17 simulator, including
  `DiaperEntryTests` (8) and `SolidFoodTests` (9). Those had been committed without ever running
  while the simulator's test runner was wedged. With Phase 0's two new tests, the total is 190.
- If anything fails at the start of a later phase, fix it first.
- From the command line:
  `xcodebuild test -project BabyFeed.xcodeproj -scheme BabyFeed -destination 'platform=iOS Simulator,name=<an installed iPhone>'`
  (`xcrun simctl list devices available` lists them).

0.2 **One list of models.** ✅
- `AppSchema.models` (in `BabyFeed/Models/AppSchema.swift`) lists every `@Model` type, and
  `AppModelContainer.shared` builds its schema from it.
- `ModelContainer.preview` is an in-memory container with every model. Every `#Preview` now uses
  `.modelContainer(.preview)` instead of a hand-written list. Several of those lists named only
  three models while their view queried diapers, foods or notes.
- Tests call `AppSchema.inMemoryContainer()`, which returns a fresh, uniquely named in-memory
  store.

0.3 **`BabyStore.removeLocally`** also deletes the baby's diapers and solid foods, and switches away
from the baby before deleting it. ✅

0.4 **`DebugSeed`** clears diapers and solid foods like the other types. ✅
- It seeds a realistic first fortnight of diapers: 1 wet and 1 dirty on day 1, climbing to 6–8 wet
  and 3–4 dirty from day 5, with some "both".
- It seeds no solid foods, because the seeded baby is two weeks old.
- Feeds and weights are unchanged: 9 feeds a day in week one, then the day-3 weight dip and back
  to birth weight by day 11.
- Launch a Debug build with `--seed-demo-data` to use it.

**Done when:** ⌘U is green, every `#Preview` builds against the full schema, and removing a baby
leaves none of its rows. ✅ The previews compile as part of the test build; open a few in Xcode's
canvas to see them render.

**Tests:** `BabyStoreTests.removeLocallyDeletesEveryType` and
`BabyStoreTests.inMemoryContainersDoNotShareRows`. ✅

**Prompt**

> Read CLAUDE.md and ROADMAP.md. Do Phase 0 only. Start by running the full test suite and tell me
> what fails before changing anything. Then make the changes in 0.1–0.4, add the listed test, run the
> suite again, and update the Phase 0 row in the status table.

---

## Phase 1 — Today: a countdown, minutes not seconds, less battery

**Goal.** The first thing on screen is how long until the next feed. Nothing ticks in seconds, and
the app stops doing the same work two or three times.

**What's wrong today**

- **The hero.** `LastFedCard` shows a big running "SINCE LAST FEED" clock. The next-feed time only
  appears when reminders are on, and reminders are off by default.
- **Whole-list refresh.** The whole Today `List`, including the WHO growth projection, re-renders
  every 30 seconds: `TimelineView(.periodic(from: .now, by: 30))` in `HomeView`.
- **Per-second text.** The tab-bar accessory (`NextFeedBar`, on every tab) uses
  `Text(date, style: .relative)`, which ticks every second for the first hour. The Live Activity
  uses `style: .timer` (H:MM:SS); with reminders off it shows a per-second count-up in the Dynamic
  Island.
- **Duplicated work.** Launch and every foreground run two syncs at once. Each pulled page reloads
  the widget, the Live Activity and the alarm, even when nothing changed.

**Changes**

1.1 **One countdown for everything.** Add `Shared/FeedCountdown.swift`. `Shared/` compiles into both
the app and the widget.

```swift
enum FeedCountdown: Equatable {
    case noFeeds
    case upcoming(due: Date, minutesLeft: Int)   // ≥ 1, rounded UP: never "0m" before it's due
    case overdue(due: Date, minutesLate: Int)    // up to one interval late; ≥ 0, rounded down
    case quiet(lastFeed: Date)                   // later than that: a feed wasn't logged, or logging stopped

    static func nextDue(after lastFeed: Date, intervalMinutes: Int) -> Date
    static func state(lastFeed: Date?, intervalMinutes: Int, now: Date) -> FeedCountdown
}
```

- `.quiet` keeps the app honest when logging tapers off (an older baby) or a feed simply wasn't
  written down. Instead of a red timer growing for days, the hero says "No feed logged since 9:40 AM"
  with a Log button. The Live Activity ends, and nothing re-alerts.
- `AppSettings.nextDue(after:)` delegates to `FeedCountdown`. Delete the inline `startTime + interval`
  copies in `HomeView` and `NextFeedBar`. Siri's `LastFeedIntent`, `ReminderScheduler` and
  `FeedCoordinator` all go through it.
- Durations use the existing `ElapsedText.compact(minutes:)` ("1h 20m", "45m").

1.2 **The due time no longer depends on reminders.**
- `FeedCoordinator.feedsDidChange` always sets `FeedSnapshot.nextFeedDue` and the Live Activity's
  `dueTime`: drop the `AppSettings.remindersEnabled ? due : nil` gates. The reminders toggle now only
  decides whether a notification or alarm is scheduled.
- `SettingsView`: move the "Every …" interval picker (including "Typical for age · N hours") out of
  `if remindersEnabled` into its own **Feeding schedule** section above Reminders.

1.3 **The hero: `NextFeedCard` replaces `LastFedCard`.**
- **Upcoming.** A "NEXT FEED IN" caption, then the big number "1h 20m" (keep today's
  `.system(size: 64, weight: .bold, design: .rounded)`, `monospacedDigit`, `minimumScaleFactor(0.5)`,
  `.contentTransition(.numericText())`), then "around 5:10 PM". Below that, a small line: "Last fed
  2:10 PM · Formula · 3 oz · 1h 40m ago", with the kind's icon and color. For nursing, add the
  side: "Nursing 15 min · Left".
- **Overdue.** "OVERDUE", the big number "25m", then "was due at 5:10 PM", all in **red**. Not
  orange: orange is Formula's color (`FeedKind.color`), and the number sits next to a Formula icon.
- **Quiet.** "No feed logged since 9:40 AM" with a [Log a feed] button. No red, no big number.
- **Newborn line.** When the baby is under 14 days old, or not yet back to birth weight once
  Phase 4 knows it, and it has been at least `FeedingGuidance.newbornMaxGapHours` (4 h, unused
  today) since the last feed, add one calm line: "Newborns are usually woken to feed after about
  4 hours until they're back to birth weight." It reuses the AAP source `FeedingGuidance` already
  cites, and shows in the overdue and quiet states alike.
- **No feeds.** Keep today's empty state.
- **Accessibility.** Make it one combined element whose label reads the whole card: "Next feed in
  1 hour 20 minutes, around 5:10 PM. Last fed at 2:10 PM, formula, 3 ounces."
- **Time zone.** Format clock times in the log's time zone:
  `Date.FormatStyle(date: .omitted, time: .shortened, timeZone: AppSettings.timeZone)`. `.formatted()`
  uses the device zone and ignores a zone pinned in Settings.

1.4 **Only the clock ticks, once a minute.**
- `HomeView`: remove the `TimelineView(.periodic(by: 30))` around the list. Only `NextFeedCard` sits
  in `TimelineView(.everyMinute)`.
- The 24-hour sections (Last 24 hours, the daily target's "consumed", Recent) drift slowly. Drive
  them from a `now` that refreshes every 10 minutes and whenever the app becomes active. Keep
  `FeedingGuidance.currentTarget`, which runs the growth projection, out of any per-minute closure.
- `NextFeedBar`: replace `Text(last.startTime, style: .relative)` with `TimelineView(.everyMinute)`
  and `FeedCountdown` text: "Next feed in 1h 20m · 5:10 PM", or "Feed due · 25m late" in red. Compute
  its accessibility label from the same state; today it's computed once and goes stale.

1.5 **Widget and Live Activity: minutes, drawn by the system.**
- Use the self-updating formats from iOS 18 on, all confirmed in the installed iOS 27 SDK. The
  system redraws them at minute precision without waking the extension:
  - `Text(.currentDate, format: .timer(countingDownIn: now..<due, showsHours: true, maxFieldCount: 2, maxPrecision: .seconds(60)))`
  - `Text(.currentDate, format: .offset(to: due, allowedFields: [.hour, .minute], maxFieldCount: 2))`
  - `Text(.currentDate, format: .reference(to: due, allowedFields: [.hour, .minute]))`, which reads
    "in 1 hr, 20 min"

  Check each on a device and use whichever reads best in each slot.
- **`NextFeedLiveActivity`**
  - Replace every `style: .timer` and `style: .relative`.
  - Compact trailing shows the minute countdown, and must fit 56 pt.
  - Lock Screen shows "Next feed", the clock time and the countdown. "Last fed" is shown as a clock
    time.
  - `LiveActivityManager.update` sets `staleDate = dueDate` (today it's due + 2 h). The views use
    `context.isStale` to switch to the overdue style, so the Live Activity flips on time with no
    update from the app. End the activity when the countdown goes `.quiet`.
  - The system ends any Live Activity after 8 hours. So start a fresh one on each logged feed
    instead of updating one indefinitely. Ignore activities that aren't `.active`: an ended one left
    in `activities` stops the manager from ever requesting a new one.
  - Add a `widgetURL` to the Lock Screen presentation; only the Dynamic Island has one today.
- **`LastFeedWidget`**
  - Use the same formats. The circular and inline families stop showing fixed strings that are up
    to 10 minutes stale.
  - The timeline becomes one entry now plus one at the due time.
  - The header reads "Next feed" or "Feed is due", from `FeedCountdown`.
  - Description: "When the next feed is due, and when the last one was."
- **Time zone.** Add an optional `timeZoneIdentifier` to `FeedSnapshot` and to
  `NextFeedActivityAttributes.ContentState`, and apply `.environment(\.timeZone, …)` in the widget
  views so "5:10 PM" matches the app.

1.6 **Stop doing the work twice.**
- **Double sync.** `BabyFeedApp` calls `SyncEngine.requestSync()`, then
  `FeedCoordinator.settingsDidChange` calls it again. `isSyncing` is only set once the Task starts,
  so both pass. Set it synchronously in `requestSync()`.
- **Empty pages.** `SyncEngine.apply` runs `FeedCoordinator.feedsDidChange` for every pulled page,
  even an empty one. Skip empty results, and refresh at most once per sync.
- **Change detection.** `FeedCoordinator.feedsDidChange` compares the new snapshot with the saved
  one, ignoring `updatedAt` (today that's `.now`, so every snapshot looks new). It saves and calls
  `WidgetCenter.shared.reloadAllTimelines()` only when something changed. Apply the same rule to the
  Live Activity and to AlarmKit: `FeedAlarmScheduler.schedule` cancels, re-asks for authorization and
  recreates the alarm every time.
- **Typing.** `BabyView`'s baby-name field saves, syncs and refreshes on every keystroke. Debounce
  it (~1 s) or commit on submit.
- **Lost snooze.** "Remind me in 15 min" is lost as soon as the app opens. `ReminderScheduler.snooze()`
  reuses `requestID`, and the next `reschedule()` removes it without re-adding it, because the due
  time has passed. Persist `snoozedUntil`, re-add it while it's still in the future and no feed has
  been logged, and clear it when one is.

**Done when**
- `grep -rn "style: .timer\|style: .relative\|by: 30" BabyFeed BabyFeedWidget Shared` finds nothing.
- With reminders **off**, the hero, accessory, widget and Live Activity all show the countdown and
  the due time.
- The overdue state shows up on time: within a minute in the app, exactly on time in the Live
  Activity. A last feed from yesterday reads as quiet, not "OVERDUE 20h".
- A foreground runs one sync and at most one widget reload (count them with a debug log).
- On the phone, the Lock Screen and Dynamic Island show minutes ("1h 20m"), never seconds.

**Tests**
- `FeedCountdownTests`:
  - exactly at due → overdue 0;
  - 30 s before → upcoming 1;
  - 1h 19m 30s before → "1h 20m";
  - one interval late → still overdue; a minute later → quiet;
  - no feeds;
  - a feed dated slightly in the future (clock skew) → the full interval.
- `FeedSnapshotTests`: `nextFeedDue` and `timeZoneIdentifier` round-trip, and a snapshot that differs
  only in `updatedAt` counts as unchanged.
- The pure part of the snooze logic: a snooze survives a reschedule, and a new feed clears it.

**Prompt**

> Read CLAUDE.md and ROADMAP.md. Do Phase 1 only (steps 1.1–1.6). Build `FeedCountdown` first,
> with its tests, and route every screen through it before changing any UI. When done, run the
> suite, list the checks I should do on my phone (Lock Screen, Dynamic Island, widget), and update
> the status table.

---

## Phase 2 — Logging that visibly lands, and one Timeline

**Goal.** Every log visibly lands, and one place shows everything that happened (feeds, diapers,
food, weights and notes), searchable, with how long ago.

**What's wrong today**
- A diaper tap saves on the spot, but the only feedback is a 1.2-second checkmark. There's no haptic
  and no undo, and a double tap logs two diapers.
- History, Trends, CSV, the widget and Siri only know about feeds. Diapers, foods and notes each have
  their own side list, and care notes are reachable only through Baby → "Notes for the doctor".
- Weights can't be edited, and delete confirmations are inconsistent.

**Changes**

2.1 **Feedback when you log.**
- A 5-second toast at the bottom: "Wet diaper · 2:14 PM  [Undo] [Edit]".
  - It's a small overlay on `RootView`, driven by an `@Observable ToastCenter`, and appears for
    every one-tap log and every save from a sheet.
  - Undo is `softDelete()`, then save, then `requestSync()`. Edit opens that entry's editor.
- `.sensoryFeedback(.success, trigger:)` on each log.
- Ignore a second identical diaper tap within 1.5 s.

2.2 **Today, cleaned up** (see [Where it ends up](#where-it-ends-up)), in this order:

1. `NextFeedCard`.
2. The feed tiles, in a compact row of three: Formula, Breast milk and Nursing, each with its amount.
3. The diaper buttons and a line such as "Last diaper 1:55 PM · Today 5 wet · 2 dirty".
4. **Getting enough?** (Phase 4) and **Right now** (Phase 5): hidden until those phases.
5. **+ Log something else**: a sheet with Note, Weight and Food (from 4 months). Later phases add
   Medicine, Concern, Doctor visit and Pumping.
6. **Today so far**: feeds and volume against the target, with a diaper count. Tap it for the full
   `GuidanceCard`.
7. **Recent**: the last three entries of any type, then "See all in Timeline".

The Foods section moves into "+", Recent and the Timeline. Solids only start around 6 months, so
they shouldn't take a permanent spot on Today.

2.3 **History becomes Timeline.** Name it `CareTimelineView`, since SwiftUI already has a
`TimelineView`. `AppRouter.Tab.history` becomes `.timeline`.

**Model layer** (pure and tested):
- **`CareEntry`** (`BabyFeed/Models/CareEntry.swift`): a protocol with `uuid`, `babyID`, `deletedAt`,
  `loggedByName`, and `occurredAt`, which maps to each model's `startTime`, `time` or `date`. One
  generic `active(for:)` replaces the five copies. Don't rename stored properties; the SwiftData
  store, DTOs and predicates use them.
- **`TimelineItem`** (`BabyFeed/Models/Timeline.swift`): an enum with cases `.feed`, `.diaper`,
  `.food(isFirstTime:)`, `.weight` and `.note`. Later phases add concerns, doses, visits and
  pumping. Each item has a stable `id` (`"feed:<uuid>"`), `date`, `category` and `searchText`. It's
  an enum so `switch` forces every screen to handle a new type.
- **`TimelineBuilder`**: `items(_:babyID:filter:query:)` and
  `days(_:calendar:) -> [TimelineDay]`. Each day carries its `FeedSummary` and `DiaperTally`.
- **`DayGrouping.group(_:calendar:date:)`** replaces the grouping repeated inline in
  `DiaperListView`, `FoodListView` and `DaySummaryGenerator`. `FeedStats.groupByDay` wraps it.
- **`RelativeAge.ago(_:now:calendar:)`**: "Today", "Yesterday", "3 days ago" … "30 days ago", "5 weeks
  ago", "4 months ago", counted in calendar days in the log's time zone. `span(start:end:)` gives
  "lasted 4 days". The doctor asks in days.

**Screen:**

```
Timeline                               [🩺]
[ Timeline | Trends ]            ("Charts" in Phase 6)
🔍 Search: "eye", "spit up", "avocado"
(All) Feeds Diapers Food Notes Growth      ← a chip with nothing to show is hidden
TODAY · 9 feeds · 14 oz · 7 wet · 4 dirty
  ▮  ▮   ▮  ▮    ▮   ▮  ▮  ▮   ▮     feeds
   ▾    ▾ ▾   ▾   ▾    ▾  ▾          diapers
 12a    6a    12p    6p   12a
 Nursing · 15 min · Left · Logged by Annette   2:10 PM
 Wet diaper                                    1:55 PM
YESTERDAY · 10 feeds · 16 oz · 6 wet · 3 dirty
MON, SEP 15 · 13 days ago                    ›   (older days collapsed)
                Show earlier (30 days)
```

- **Rows.** `EntryRow` is pulled out of `FeedRow`, keeping its accessibility-size layout and the
  "Logged by" subtitle. Diaper rows are compact.
- **Tap** opens the right editor: `LogFeedSheet(mode: .edit)`, `EditDiaperSheet`,
  `LogFoodSheet(mode: .edit)`, `AddWeightSheet(mode: .edit)` (a new mode), or
  `LogCareNoteSheet(mode: .edit)`.
- **Swipe** soft-deletes and shows the Undo toast.
- **Queries** live in a child `TimelineQueryView(babyID:since:)`, with a `#Predicate` per model on
  babyID, deletedAt and date. The window is 30 days, then "Show earlier"; search lifts the window.
  Budget: under 16 ms to build 30 days of seeded data (measure with an `os_signpost`).
- **`FeedTimelineStrip` becomes `DayStrip`**, with a lane for feed bars and one for diaper ticks.
- **Empty states.** The empty state and the pediatrician button count any entry type; today they
  only count feeds.
- **Side lists.** "All diapers" and "All foods" open the Timeline filtered. Delete `DiaperListView`
  and `FoodListView` once the Timeline does everything they did.

2.4 **Consistency**
- Tapping a weight row opens `AddWeightSheet(mode: .edit)`.
- Deleting is swipe plus Undo everywhere. A Delete button inside a sheet always confirms.
- One `LoggedByText` helper replaces the five hand-built strings (`FoodListView` says "by X").
- `FoodLogSection` uses `\.calendar` instead of `Calendar.current`, which ignores a pinned time zone.
- Delete the unused `DiaperTally.changeCount`; it would also double-count "Both".
- **Pediatrician summary** (`SummarySheet` and `DaySummaryGenerator`):
  - add a Diapers column to the day grid;
  - give a day with diapers but no feeds its own row;
  - stop computing diaper averages only inside `if !groups.isEmpty`.
- **CSV:** "Export everything" (one file with type, time, details and logged by), next to today's
  feeds-only export.

**Done when:** a diaper tapped on Today shows the toast, then appears in Recent and in the Timeline
with that day's tally. Every row opens its editor, and searching "eye" finds a note that mentions
it.

**Tests**
- `TimelineBuilderTests`: merge order, scoping to the baby, deleted rows excluded, filter mapping,
  search (accents, all words must match), the first-time-food flag, and day totals equal to
  `FeedSummary` and `DiaperTally`.
- `DayGroupingTests`: a daylight-saving day and a pinned time zone.
- `RelativeAgeTests`: 0, 1, 2, 30, 31, 111 and 112 days, and across a DST change.
- A CSV escaping test.

**Prompt**

> Read CLAUDE.md and ROADMAP.md. Do Phase 2 only. Build the pure model layer (CareEntry,
> TimelineItem, TimelineBuilder, DayGrouping, RelativeAge) with its tests first, then the Timeline
> screen, then the Today clean-up and the toast. Keep feeds at two taps and diapers at one. Run the
> suite and update the status table.

---

## Phase 3 — Sharing without credentials

**What it will feel like**
- **First phone, at home:** open the app, tap *Add my baby*, enter a name, birthday and (optionally)
  birth weight. The next screen is *Your recovery phrase*, to write down; then Today. The log backs
  up to the Mac mini by itself.
- **Sharing:** tap **Share** and a QR appears within a second or two. The other phone points its
  Camera at it and taps the banner. Baby Feed opens, joins on its own, and asks "What should we call
  you?". The sharer sees "✓ Annette's iPhone joined". Both phones now show the same feeds and
  diapers, each with who logged it.
- **A new phone after losing yours:** *Restore with recovery phrase*, and the log comes back.
- **Away from home:** logging works as always, and the status reads "Will sync when you're home".

**Why it doesn't work today.** The first phone must type the server address, a setup code and a
name (`PairServerView`'s "First phone" mode). The server's `/v1/pair/claim` is single-use and refuses
once any user exists, and four devices are already paired, so a fresh phone dead-ends.

### 3a — Server (done: merged to `main`, running on the mini since 2026-09-28)

What changed in `server/`:
- `src/{server,auth,db}.js`, `bin/babyfeed-server.js`, `scripts/setup.sh` and `README.md`.
- New tests in `test/{enroll,invite,account-recovery}.test.js` and `test/support.js`, plus additions to
  `api.test.js` and `recovery.test.js`.

All 57 tests pass (`cd server && npm test`). Old app builds keep working: every change is additive,
and `/v1/pair/claim` and the per-baby recovery routes are unchanged.

**The contract the app relies on**

| Route | Behavior |
|---|---|
| `GET /v1/health` | Adds `api: 2`, `server_id`, `features: ["enroll","join_as_member","member_invites","account_keys"]`, `enroll` (`lan`/`off`), and `enroll_available`: whether a new phone could set itself up from where you're asking. |
| `POST /v1/pair/enroll` `{display_name, device_name, key_hash?}` | Creates a new caregiver and token with nothing typed. Allowed **only** from a private LAN address on the socket, with no proxy headers, not from loopback, and with `Content-Type: application/json` (otherwise 415). Refusals are 403 `enroll_lan_only` or `enroll_off`; a phrase hash that already exists gives 409 `key_exists`; too many attempts give 429. Sent with a valid Bearer, it returns the same caregiver with `token: null`. |
| `POST /v1/pair/invite` `{code, display_name, device_name}` | Sent **with the phone's Bearer**, it joins as the caregiver this phone already is (`token: null`). Re-scanning a code you've already used succeeds and spends nothing. Without a Bearer it works as before. Returns `token`, `user_id`, `display_name`, `baby`, `members`, `babies` and `server_id`. Errors: 400/404 `bad_code`; 410 `expired_code`, `used_code` or `baby_gone`. |
| `POST /v1/babies/:id/invites` `{expires_in_minutes, max_uses}` | **Any member** can create one. Server defaults stay 60 min / 1 use; the app asks for **1440 / 10**. |
| `POST /v1/me/recovery` `{key_hash, replace?}` | Registers this person's phrase. The same hash returns `changed: false`. A different phrase already set gives 409 `key_exists` unless `replace: true`; someone else's hash gives 409 `key_taken`. |
| `POST /v1/me/recovery/check` `{key_hash}` | Returns `{exists, matches}`: is the phrase on this phone the one the server knows? |
| `GET /v1/me` | Adds `recovery_key: {exists, created_at, last_used_at}` and `server_id`. |
| `POST /v1/recover` `{key, display_name, device_name}` | Tries personal phrases first. A phone with no token gets one. On a phone that's already paired as someone else, that identity is folded in (`merged: true`). Otherwise falls back to the older per-baby keys. Returns `babies` and `server_id`. |
| `POST /v1/sync/push` | Rejections carry a `code`: `malformed` or `not_a_member`. A baby's `created_by` no longer changes when someone else edits it. |

Deploy it before shipping 3b: [Appendix B](#appendix-b--deploying-the-server-to-the-mac-mini).

### 3b — App

**A. The server address comes from the build.**

- **`Config/Base.xcconfig`** (committed). It lives at the repo root, **outside** the synchronized
  folders `BabyFeed/`, `Shared/`, `BabyFeedWidget/` and `BabyFeedTests/`; anything inside those
  folders joins a target.

  ```
  // The sync server. Real values live in Server.local.xcconfig, which git ignores.
  BABYFEED_SERVER_SCHEME = https
  BABYFEED_SERVER_HOST =
  #include? "Server.local.xcconfig"
  ```
- **`Config/Server.local.xcconfig`** is gitignored (add it to `.gitignore`); commit a
  `Config/Server.local.xcconfig.example` alongside:

  ```
  BABYFEED_SERVER_SCHEME = http
  BABYFEED_SERVER_HOST = brians-mac-mini.local:8791
  ```

  Scheme and host are separate because `//` starts a comment anywhere in an xcconfig line.
- **Attach it.** Set `Base.xcconfig` as the **BabyFeed** target's base configuration for Debug and
  Release (Project → Info → Configurations). Keep the uncommitted `MARKETING_VERSION = 1.2`.
- **`BabyFeed/Info.plist`** gets `BabyFeedServerScheme = $(BABYFEED_SERVER_SCHEME)`,
  `BabyFeedServerHost = $(BABYFEED_SERVER_HOST)`, and
  `NSAppTransportSecurity → NSAllowsLocalNetworking = YES`. `NSLocalNetworkUsageDescription` is
  already set. Check the result with `plutil -p <built .app>/Info.plist`.
- **`BabyFeed/Services/Sync/ServerConfig.swift`**:
  `static func defaultURL(info: [String: Any]? = Bundle.main.infoDictionary) -> URL?`.
  - Returns nil when the host is empty or still reads `$(…)`.
  - Otherwise returns `SyncLink.normalizedServerURL("\(scheme)://\(host)")`, so plain http stays
    limited to private hosts.
  - Keep it out of `SyncLink`: tests run inside the app bundle and would pick up the local value.

**B. `SyncClient`**
- `Pairing.token` becomes `String?`. The server sends `null` when a phone keeps its token, and today
  that decode failure breaks restoring onto a paired phone. Add `babies`, `serverID` and `merged`.
- `Health` gains optional `api`, `serverID`, `features`, `enroll` and `enrollAvailable`, all read
  with `decodeIfPresent`.
- New `enroll(displayName:deviceName:keyHash:)`.
- `join(code:…)` sends the phone's token only if the server's `features` contains `join_as_member`.
  An old server would mint a second identity.
- `createInvite(babyID:expiresInMinutes: 1440, maxUses: 10)`.
- New `setRecoveryPhraseHash(_:replace:)` and `checkRecoveryPhrase(_:)`.
- `Account` gains `recoveryKey` and `serverID`. `PushResult.Rejected` gains `code`.
- `probe()`: a health check on its own session, with a ~4 s timeout.
- **Errors:**
  - Map `URLError` `.cannotFindHost`, `.cannotConnectToHost`, `.timedOut`, `.notConnectedToInternet`,
    `.networkConnectionLost` and `.dnsLookupFailed` to a new `SyncError.away`.
  - Map 401 to `.unpaired` only on authenticated routes. Pairing routes show the server's own
    message; today a wrong code reads "not paired".

**C. `SyncCredentials`**
- Add `serverID`.
- `clear(ifToken:)` clears only if the stored token is the one that failed. Otherwise a sync still
  running with the old token can wipe the credentials a join just saved.
- `optedOut`: set by "Stop syncing this phone". While it's set, nothing reconnects on its own; an
  explicit Share, Join, Restore or Back up clears it.
- `hasConnectedBefore`: true once credentials are saved, and for installs that are already paired.

**D. `SyncEngine`: connect lazily, one thing at a time**

**`ensureConnected(_ reason:)`**, where the reason is `.addedBaby`, `.backUp`, `.share`, `.join`,
`.restore` or `.foreground`:
- For `.foreground` it runs only if `hasConnectedBefore`, and never while `optedOut`. So the Local
  Network prompt never appears unexplained on a cold launch, and a phone that only joins never
  creates an identity of its own.
- `ensureConnected`, `join`, `recover` and `unpair` run one at a time, behind a small actor or async
  queue.
- **Steps:**
  1. `probe()` the stored URL, or else `ServerConfig.defaultURL()`.
  2. **Paired:** compare `server_id`. A new id means the server was reset: re-queue everything,
     clear the watermarks and re-register the phrase. If the stored URL fails but the default answers
     with the *same* `server_id`, switch to it.
  3. **Not paired:** `enroll(keyHash:)` with this parent's phrase hash (see F).
  4. Save the credentials and `serverID`, share real babies only (never the untouched placeholder),
     then sync.
- Away → status `.away(pending: n)`. That's a calm status, not an error.

**`sync()`**
1. `GET /v1/me` first: insert any baby this person is on that the phone lacks, for example after a
   restore.
2. **Push:** clear `needsUpload` only if the row's `updatedAt` still equals what was sent. Today an
   edit made during the round trip is silently never uploaded.
3. **Pull** each baby in its own `do/catch`.
4. **401** → `clear(ifToken:)`, then at most one self-heal attempt per hour.

**Other `SyncEngine` changes**
- `syncNow()` waits for a sync that's already running, then runs again if anything is still queued.
  Today it returns immediately, so Share can ask for an invite before the baby is on the server.
- `join(…)`:
  - sends the token, subject to the features check in B;
  - keeps the existing token when `pairing.token == nil`;
  - makes the joined baby current and deletes the untouched placeholder baby;
  - stops using `UIDevice.current.name` as a name. Since iOS 16 that's just "iPhone", hence "Logged
    by iPhone".
- `recover(…)`: use `pairing.token ?? existingToken`, and insert every baby in `pairing.babies`.
- `unpair`: set `optedOut`.

**E. `BabyStore`**
- `isPlaceholder(_:)`: no name, no birthday, no rows in any table, and not shared.
- `createBaby(name:birthDate:sex:dueDate:birthWeightGrams:)`: fills in the placeholder when that's
  the only baby. The birth weight becomes a `WeightEntry` dated at the birthday (see Phase 4.2).

**F. The recovery phrase (one per parent)**
- **Storage:** Keychain service `com.babyfeed.BabyFeed.recovery`, account `person:<userID>`,
  synchronizable like today's per-baby items. It's saved as `person:pending` until enrolment returns
  the user id. Keying by user means two parents who share an Apple ID (and so an iCloud Keychain)
  don't overwrite each other.
- **Made fresh** when this phone adds its first real baby, or on the first connect of a phone that's
  already paired and has no phrase. The hash rides in `enroll(keyHash:)` or `POST /v1/me/recovery`.
- **Never replaced silently.**
  - Before registering, call `checkRecoveryPhrase`. If it reports `exists && !matches`, say "A
    different recovery phrase was set up on another phone" and offer an explicit Replace.
  - Remove today's `SyncEngine.recoveryKey(for:)` path. It generates and uploads a new key whenever
    this phone lacks a local copy, which quietly voids the one on paper.
- **`RecoveryKeySetupView`** (new), shown right after the baby is added:
  - the grouped phrase in big type, with no Face ID this one time;
  - **Copy**, putting it on this device's clipboard only, for 2 minutes
    (`UIPasteboard.general.setItems(…, options: [.localOnly: true, .expirationDate: …])`);
  - **Save to Files / Share**;
  - "**I've written it down**", with "Remind me later" allowed;
  - wording: "If you ever lose your phone, this brings back Nora's log. Nobody can reissue it — keep
    it somewhere safe."
- **`RecoveryKeyView`** becomes "Your recovery phrase". The Face ID reveal stays, with a status line
  from `/check`. Replacing stays explicit.
- **`FamilyView`** shows the phrase row for this person. Today it shows a per-baby row even to
  non-owners, who get a 403.
- **A fresh install** that finds `person:*` in the Keychain (a reinstall, or iCloud Keychain) offers
  "Restore from iCloud Keychain" as an explicit button, never silently.

**G. Screens**

**`OnboardingView`** replaces `SharingIntroView`. It's shown through `AppRouter.sheet = .onboarding`
when there's no real baby, the phone isn't paired, and it hasn't been shown before.

```
Welcome to Baby Feed
[ Add my baby ]  → name (required) · birthday · birth weight · sex · due date (optional)
                 → "What should we call you?"  Mom · Dad · Grandma · Nanny · [type]
                 → one line before the Local Network prompt:
                   "Baby Feed backs your log up to your Mac mini at home."
                 → ensureConnected(.addedBaby) → RecoveryKeySetupView → Today
[ Join the log ] → "On the phone that has the log, tap Share.
                    Then point this phone's Camera at the code."
Restore with recovery phrase → 24 characters (dashes, spaces and case don't matter) → the log is back
```

Existing installs with a named baby or any entries skip onboarding. They get a one-time Today card
instead: **"Back up Nora to your Mac mini** · you'll also get a recovery phrase" [Back up now].

**`ShareBabySheet`** (new) replaces `InviteView`.
- **Where:** `AppRouter.sheet = .share(babyID)`, opened from a **Share** toolbar button on Today
  (`person.badge.plus`), the Baby tab and Caregivers.
- **Steps:**
  1. `ensureConnected(.share)`.
  2. Make sure the baby is on the server: share it, then a `syncNow()` that waits.
  3. `createInvite(babyID:, 1440, 10)`.
  4. Show a QR of `SyncLink.url(code:server:)`, reusing `InviteView`'s CoreImage QR (nearest-neighbour
     scaling, correction level M, on white).
- **Text on the sheet:** "On the other iPhone, open the Camera and point it here." and "They need
  Baby Feed installed first (TestFlight)." Show the code in two groups of three, for reading out,
  plus **Send link**.
- **While it's open:**
  - poll `members(babyID:)` every 3 s to show "✓ Annette's iPhone joined";
  - keep the screen awake (`isIdleTimerDisabled`), restored on dismiss;
  - reuse a cached invite that has more than an hour left.
- **Away:** "Sharing needs both phones on your home Wi‑Fi." with Retry.

**`JoinView`** replaces the auto-submitting `PairServerView` path, via `AppRouter.sheet = .join(invitation)`.
- "Joining the log…", then "You're in — Nora's log is on this phone.", then name chips if there's no
  name yet (skippable, saved with `POST /v1/me`), then Today with that baby current.
- An expired or used code: "That code has expired — ask them to tap Share again."
- Away: "Connect to the same Wi‑Fi as the other phone."
- An old server: "The server needs an update."

**Everything else**
- **`PairServerView`**: drop the "First phone" mode, and keep it as **Caregivers → Advanced** (a
  typed address, a code or a phrase) for edge cases.
- **`AppRouter.Sheet`** gains `.onboarding`, `.share(UUID)`, `.join(SyncLink.Invitation)` and
  `.recoverySetup`. `openJoin` falls back to `ServerConfig.defaultURL()` when a link carries no
  server. `FamilyView` goes through the router rather than presenting its own sheet, so the
  single-sheet design from commit `0802233` holds.
- **`FamilyView`** (Caregivers):
  - a status line: "Backed up to your Mac mini · synced 2 min ago", "Will sync when you're home" or
    "Your Mac mini needs an update";
  - the members, **Share Nora's log** and **Your recovery phrase**;
  - "Stop syncing this phone", which sets `optedOut`;
  - an **Advanced** section.
- **`SyncMerge.inviteMessage`**: "Join Nora's log in Baby Feed — open this link on your iPhone (Baby
  Feed must be installed): <the full `babyfeed://join?code=…&server=…` link>".
  - Today's text says "sign in" and uses the server-less `babyfeed://join/CODE` form, which dead-ends
    on a new phone.
  - Update `SyncMergeTests.inviteMessageCarriesCodeAndLink`.
  - Delete `SyncMerge.suggestedDisplayName`, a Sign in with Apple leftover, and its test.

**Done when** (two phones on the home Wi‑Fi, fresh installs, after 3a is deployed)
1. Phone A: Add baby → the phrase shows → Allow Local Network → Caregivers says "Backed up".
2. A: Share → the QR shows within about 2 seconds.
3. Phone B: Camera → banner → joins without typing → name chips → Today shows Nora.
4. A shows "✓ … joined". A feed or diaper logged on either phone appears on the other after a
   foreground, labelled with who logged it.
5. A on cellular shows "Will sync when you're home", and catches up back on Wi‑Fi.
6. Delete and reinstall A → Restore with the phrase → the log comes back.

**Tests**
- `ServerConfigTests`: an empty host, an unexpanded `$(`, http with a `.local` host, http with a
  public host (rejected), and https.
- `PairingDecodingTests`: `"token": null`, a missing `babies`, and the old `Health` shape.
- `SyncPlanTests`, on small pure functions pulled out of `SyncEngine`: placeholder detection, which
  babies to share, the reaction to a 401, `not_a_member` and a changed `server_id`, and error
  classification.
- Updated `SyncMergeTests`.

**Prompt**

> Read CLAUDE.md and ROADMAP.md. Do Phase 3b only. The server half (3a) is already deployed —
> check `http://brians-mac-mini.local:8791/v1/health` reports `"api":2` before starting. Work in the
> order A → G and keep the app building after each letter. Design for one baby and two parents; don't
> build anything extra for multiple children. Where this doc and the code disagree, trust the code
> and tell me. Add the tests, run the suite, give me the two-phone checklist, and update the status
> table.

---

## Phase 4 — The first weeks: getting enough, nursing, dark at night

**Goal.** Answer what the first weeks are really about, right on Today. Is she getting enough? Which
side next? Is she back to birth weight? And keep the screen dark at 3 a.m.

**4.1 "Getting enough?" on Today, for the first 6 weeks**

- **A compact block** under the diaper buttons, while the baby is under 42 days old. After that it
  lives only on the Baby tab, as today. For the last 24 hours:
  - **wet diapers** against the expected count for the baby's age: 1–2 on day 1, 2–3 until milk
    comes in, then 5–6 or more;
  - **dirty diapers** against 3–4 from day 5;
  - **feeds** against `FeedingGuidance.ageBand(forAgeDays:).feedsPerDay` (8–12 in the first weeks).

  Today those diaper numbers exist only as a sentence, in `IntakeGuidance.diaperExpectation(ageDays:)`.
  Turn them into numbers (for example `expectedWet(ageDays:) -> ClosedRange<Int>` and `expectedDirty`)
  and build the sentence from those, so the block and the sentence can't disagree.

  Show a ✓ when a count meets the expectation, and a plain number otherwise. **Never red for a low
  count**: a missed log is not a sick baby.
- **One red flag** is allowed, and `IntakeGuidance.redFlags` already has it (`no-urine`: "No wet
  diaper in more than 8 hours, or dark urine"). Show it calmly and conditionally: "No wet diaper
  logged since 6:10 AM (8 h). If that's right, call your pediatrician." Cite its existing source.
- **Tapping the block** opens `IntakeView`. Today that view shows fixed expectations only; pass in
  the logged counts so its "Today" section is real.
- **Pure logic:** `EnoughSummary(diapers:feeds:ageDays:now:)`, with tests at each day-of-life
  boundary.

**4.2 Back to birth weight, for the first 3 weeks**

- **Birth weight** is the earliest `WeightEntry` dated within a day of the birthday. Onboarding
  (Phase 3) and the Baby tab offer "Add birth weight" when there isn't one. No new stored field is
  needed.
- **One line** in the "Getting enough?" block:
  - "Birth 7 lb 3 oz → 6 lb 14 oz on day 4 (−4%) · most babies are back by day 10–14"
  - once regained: "Back to birth weight ✓ on day 11"
- **Context** comes from the expectation `IntakeGuidance.whatMatters` already states: "Losing up to
  7–10% in the first days is expected, back to birth weight by about 10–14 days".
- **One red flag**, the existing `birth-weight` one: "Not back to birth weight by about two weeks".
  Word it calmly and show its source. Don't invent new thresholds (a percentage cut-off, say)
  without an AAP, CDC or WHO source behind them.
- **Pure logic:** `BirthWeightStatus`, tested for: −7%; regained on day 11; not regained by day 15;
  no birth weight.
- **The Phase 1.3 newborn line** uses this: "until they're back to birth weight".

**4.3 Nursing: which side next, and a timer in minutes**

**Next side.** Derive it from the last nursing feed's `side`: left suggests Right, right suggests
Left, and both suggests nothing. No new data is needed.
- The Nursing tile reads "Nursing · start Right".
- `LogFeedSheet` preselects that side.
- The hero's small line shows the last side.

**A live nursing timer.** It's minutes only, like everything else.
- Starting: the Nursing tile's **Start** begins a session, remembering the side, the start time and
  any side switches. The session is persisted in UserDefaults so it survives the app being killed.
- The hero becomes "NURSING · Left · 12 min", with [Switch side], [Done] and [Cancel], inside
  `TimelineView(.everyMinute)`.
- **Done** saves a normal nursing `FeedEntry`: `startTime` is the session start, `durationMinutes`
  the total, and `side` is `.both` if the side was switched. It saves through the usual
  `FeedCoordinator` path, so the countdown restarts from that feed.
- A forgotten timer: after 60 minutes the hero asks "Still nursing?", and Done offers to trim the
  time.

**Live Activity during a session.** "Nursing · Left" with
`Text(.currentDate, format: .stopwatch(startingAt: start, maxPrecision: .seconds(60)))`, which counts
in minutes (confirmed in the SDK). Add optional `nursingStartedAt` and `nursingSideRaw` to
`NextFeedActivityAttributes.ContentState`.

**Later, optionally:** the other phone sees "Annette is nursing, started 2:10". That needs an
in-progress feed to sync.

**4.4 Dark at night**

- **Settings → "Dark at night"**, on by default, from 8 PM to 7 AM, with adjustable times.
  `RootView` applies `.preferredColorScheme(.dark)` during those hours whatever the system setting,
  so a light-mode phone doesn't flash white at the 3 a.m. feed. Re-evaluate at the boundaries (a
  timer that fires at the next boundary) and on becoming active.
- The QR in the share sheet stays white; a camera needs it.

**4.5 Optional: pumping**

If breast milk is being expressed:
- A `PumpingSession` synced type with time, left ml, right ml, duration and note, added through
  [Appendix A](#appendix-a--adding-a-synced-type) with the server part first.
- A "Pumped" tile in "+", shown only when the feeding style is breast milk or mixed.
- Sessions in the Timeline, and the amount in "Today so far".

**Done when:**
- In the seeded first week, Today shows counts with ✓ that match the Timeline's day tallies, and the
  birth-weight line moves from "−7% on day 3" to "Back to birth weight ✓".
- After a Left feed, the Nursing tile suggests Right.
- A nursing timer survives force-quitting the app and saves a correct feed.
- The app goes dark at 8 PM on a light-mode phone.

**Tests:**
- `EnoughSummaryTests`
- `BirthWeightStatusTests`
- `NextSideTests`
- `NursingSessionTests`: switch sides, Done with a switch, a forgotten timer, and relaunch
  persistence of the pure state
- a test for the night-hours window across midnight

**Prompt**

> Read CLAUDE.md and ROADMAP.md. Do Phase 4 (4.1–4.4; 4.5 only if I say so). Build the pure pieces
> (EnoughSummary, BirthWeightStatus, next side, the nursing session) with tests first. Keep every
> number sourced to the guidance files that already exist, never show a low count in red, and keep
> the timer at minute precision. Run the suite and update the status table.

---

## Phase 5 — Health for the first year: concerns, medicines, doctor visits

**Goal.** Parents can write down what's going on ("redness in her left eye") and see how long ago it
started when the doctor asks. They can track medicines without double-dosing between two phones, and
keep what the doctor said with the rest of the log.

The tabs become **Today · Timeline · Health · {baby} · Settings**. Health uses `stethoscope`, with a
badge for medicines that are due. "Notes for the doctor" moves from the Baby tab into Health.

```
Health                                       [+]
[ Summary for the pediatrician            › ]  ← defaults to "since the last visit"
NEXT CHECKUP
 2-month visit · around Nov 16 · in 7 weeks
ONGOING
 Red left eye          day 3 · since Sep 26
   "less red today" · yesterday      [Better]
MEDICINES
 Vitamin D · daily                 ✓ 8:10 AM
 Gas drops · as needed · last 2:30 AM by Annette  [Give]
DOCTOR VISITS
 Sep 22 · 1-week weight check · Dr. Patel   ›
NOTES FOR THE DOCTOR     3 since the last visit ›
PAST CONCERNS
 Stuffy nose · lasted 5 days · Sep 10–15    ›
```

Every new type goes through [Appendix A](#appendix-a--adding-a-synced-type), with the server first
(use Claude Code in Terminal for `server/`).

### 5.1 Concerns: an episode with a start and an end

**New synced type `HealthConcern`** (table `concerns`):
- `title`: "Red left eye"; required, 200 characters max, prefilled from the kind.
- `kindRaw`: a `CareNoteKind`.
- `startedAt`; `resolvedAt`, where nil means ongoing.
- `severityRaw`: 1–3, at its worst.
- `note`, and `outcome` ("cleared with drops").
- `loggedByName`, plus the sync fields.
- Server: `REQUIRED = [id, baby_id, title, kind, started_at, updated_at]`, and refuse
  `resolved_at < started_at`.

**How it relates to `CareNote`:**
- `CareNote` stays a point-in-time note. A new optional `concernID` links a note to a concern as an
  update ("less red today").
- **Existing notes never show as "ongoing."** Their `resolvedAt` is nil, but they aren't concerns.
  Fix the doc comment on `CareNote.resolvedAt` (it says the opposite), stop using the field, and
  delete the unused `CareNote.summary(calendar:now:)`.
- **"Track as a concern"** on any note creates a concern starting at the note's date and links the
  note.

**Kinds that fit the first year.** New `CareNoteKind` cases:
- `jaundice` ("Yellow skin or eyes");
- `eye` ("Eye — redness or discharge");
- `cord` ("Umbilical cord");
- `cough` ("Cough or congestion");
- `vomiting`;
- `teething`;
- `injury` ("Bump or injury").

The server stores `kind` as free text, so it needs no change, and older apps show "Something else".
Retitle `.stool` "Poop concern", since it overlaps the Dirty diaper button.

**Fever under 3 months.** Logging a temperature note for a baby under 12 weeks shows the existing
`IntakeGuidance.redFlags` entry `fever` ("Any fever under 12 weeks old – and don't give fever
medicine before they're seen"), with its source. For the threshold, the AAP's is 100.4 °F (38 °C).

**`ConcernStats`** (pure):
- `dayNumber`;
- `statusText`: "ongoing · day 3" or "lasted 4 days";
- `needsCheckIn`: ongoing with no update for 7 days, which asks "Still going on?". A concern is never
  resolved automatically.

**UI:**
- `LogConcernSheet(mode:)`.
- `ConcernDetailView`: its linked notes as a mini timeline, Add update, "It's better" (date chips
  Now, Yesterday, 2 days ago) and Reopen.
- Concerns also appear in the Timeline, where searching "eye" finds them.

**Late columns: a small migration mechanism.** `concern_id` is a column added to an existing table,
and today both ends would wipe it.
- **Server `db.js`:** add `SCHEMA_VERSION`, an append-only
  `COLUMN_ADDITIONS = [['care_notes', 'concern_id', 'TEXT']]`, and `migrate(db)`. `migrate` runs
  `PRAGMA table_info`, then `ALTER TABLE … ADD COLUMN`, then `PRAGMA user_version`, in one
  transaction.
- **Server `sync.js`:** `LATE_COLUMNS = { care_notes: ['concern_id'] }`. `normalizeRow` sets it only
  when the key is present, and `upsertRow`'s `DO UPDATE SET` skips `undefined` columns. Today every
  column is written on conflict, so an older app that doesn't know the key would null it.
- **App `CareNoteDTO`:** a custom `init(from:)` notes whether `concern_id` was sent, and
  `apply(to:)` writes `concernID` only then.
- **`/v1/health`** adds `tables` and `schema_version`. The app warns "Your Mac mini needs an update"
  when a table is missing; otherwise rows pushed to an old server stay `needsUpload` forever, without
  a word.

### 5.2 Medicines

**New synced types** `Medication` (table `medications`) and `MedicationDose` (table `medication_doses`).

**`Medication`**: the definition. The parent enters every number from the label or the doctor.
- `name`; `kind`: medicine, supplement, topical or other.
- `doseAmount?` and `doseUnit`: ml, drop, mg, IU, tablet, application or other. Millilitres, not
  teaspoons.
- `schedule`: asNeeded, daily(timesPerDay) or everyNHours(intervalHours).
- `minHoursBetween?` and `maxDosesPer24h?`.
- `startDate`, and `endDate?` for a course.
- `instructions`.

**`MedicationDose`**:
- `medicationID?`;
- `medicationName`, copied onto the dose so it still reads right after a rename;
- `time`, `amount?`, `unit?`, `note` and `loggedByName`.

**Pure logic:**
- `MedicationStats`: `lastDose`, doses in the last 24 h, `nextDue`.
- `MedicationSafety.notices(…)`: `.tooSoon`, `.dailyMaxReached`, `.alreadyGivenToday`,
  `.courseEnded` or `.recentByOtherCaregiver`.
- `possibleDuplicates`: the same medicine logged closer together than
  `minHoursBetween ?? 1 h`, typically two phones logging while offline.
- `DoseDraft.initial(for:)`: **never invents an amount**. It's the medication's `doseAmount`, or
  empty.

**`LogDoseSheet`:**
- It syncs first, then shows "Checked with the other phone just now" or "Couldn't reach the Mac mini
  — a dose logged on the other phone may not be here yet".
- Notices sit above Save, which then reads "Log anyway". It never blocks.

**Two parents, one baby, no double doses:**
- every medicine row shows "last given 2:30 AM · by Annette";
- the Today "Right now" card (5.4);
- a banner after a sync brings in a possible duplicate.

**Safety copy:**
- "Baby Feed records what was given. It never suggests a dose — that comes from your pediatrician,
  pharmacist or the label."
- Cite it through the existing `FoodGuidance.Source` mechanism. Its test fails the build for any
  source that isn't the AAP (aap.org, healthychildren.org), CDC or WHO. Verify each URL when you add
  it.

**Vitamin D:**
- Offer it when the feeding style is breast milk or mixed: "The AAP recommends 400 IU of vitamin D a
  day for babies who get breast milk. Ask your pediatrician which drops."
- It creates a daily supplement with the amount left blank, because products differ.
- It then shows as "✓ 8:10 AM · Annette" once given.

**Optional reminders.** `ReminderScheduler.registerCategories` replaces every notification category,
so a medicine category must be registered in that same call.

### 5.3 Doctor visits and the checkup schedule

**New synced type `DoctorVisit`** (table `doctor_visits`):
- `date`;
- `kind`: checkup, sick, follow-up, specialist, urgent care, emergency, telehealth or other;
- `provider` and `reason`;
- `doctorNotes` ("What the doctor said");
- `followUpDate?` and `followUpNote`;
- `vaccines`, as free text for now;
- `weightEntryID?`. A weight entered at the visit creates or updates a linked `WeightEntry`, so the
  growth maths and the birth-weight line pick it up.

**Next checkup.** Computed from the birthday using the AAP well-child schedule (first week, 1 month,
then 2, 4, 6, 9 and 12 months), shown as "2-month visit · around Nov 16". Cite the AAP schedule on
healthychildren.org and verify the URL. A logged checkup near a scheduled age counts as done.

**Pediatrician summary.**
- It gets `ReportWindow { case days(Int), since(Date) }`, defaulting to "since the last visit". Keep
  `days:` so the current tests stay green.
- New sections, in order:
  1. the last visit's follow-up;
  2. concerns: when each started, whether it's ongoing or how long it lasted, and its updates;
  3. medicines given: name, count, first and last dose.
- Windows longer than 14 days roll the day-by-day rows up into weeks.

### 5.4 Today's "Right now" card

At most three rows: medicines due or overdue [Give], concerns due a check-in, and a checkup due this
week. Hidden when empty.

**Done when:**
- A store full of existing notes shows nothing as ongoing.
- "Red left eye", started 12 days ago, reads "day 12" and "12 days ago" everywhere.
- A dose logged on one phone shows on the other before its dose sheet offers to log another.
- The summary defaults to "since the last visit".

**Tests:**
- `ConcernStatsTests`.
- `MedicationSafetyTests`: the boundary exactly at `minHoursBetween`, the 24-hour maximum, another
  caregiver's dose, and duplicates.
- `DoseDraftTests`: never invents an amount.
- `CheckupScheduleTests`.
- DTO round trips, and the "was the late field sent?" check.
- `ReportWindowTests`.
- **Server:** a round trip per new table, validation, and a new `test/migrate.test.js` covering a
  fresh DB, the old `care_notes` layout, and idempotent reopening. Late columns: an absent key keeps
  the stored value, and an explicit null clears it.

**Prompt**

> Read CLAUDE.md and ROADMAP.md. Do Phase 5, one sub-phase at a time: 5.1 concerns (with the
> late-column mechanism), 5.2 medicines, 5.3 doctor visits and the checkup schedule, 5.4. For each new
> synced type, follow Appendix A exactly and do the server part first — tell me when to switch to
> Claude Code in Terminal for `server/`. Never add anything that suggests a medicine dose. Run both
> test suites and update the status table.

---

## Phase 6 — Charts, numbers first

**The rule, from commit `ce11c14`.**
- Each chart card is a title, then **one sentence stating the value**, then the chart.
- The sentence comes from the same code as the numbers.
- Today's `TrendsView` numbers stay beneath the charts, under "The numbers".

The Timeline's segmented control becomes **Timeline | Charts**. The range is 2 weeks, 1 month,
3 months, or since the last visit (`@SceneStorage`).

**Charts, in first-year order of usefulness:**
1. **Feeds per day, and intake against the target.** Bars, plus a step line for each day's target:
   `FeedingGuidance.currentTarget(now: end of that day)`.
2. **Diapers per day:** wet and dirty, stacked, with the 6-a-day line after the first week. Share
   the number with `IntakeGuidance`'s "Fewer than 6 wet diapers a day after the first week".
3. **Weight** (on the Baby tab):
   - a birth-weight line for the first weeks;
   - the WHO 3rd–97th and 15th–85th percentile bands and the 50th percentile, from `GrowthStandard`,
     only when sex is known;
   - the weigh-ins and a dashed projection.
4. **Feed rhythm:** a dot per feed, by day and hour, with an overnight band. It answers "is she
   clustering at night?".
5. **Care overview:** lanes across the days.
   - Concerns as spans, using `BarMark(xStart:xEnd:y:)`.
   - Medicine doses as diamonds.
   - Visits as rules.
   - Feed and diaper cells.

   Selecting a day lists its entries.

**Details:**
- A day with nothing logged is a gap, never a zero bar.
- Each chart has an `accessibilityChartDescriptor`.
- Lanes differ by symbol as well as color.
- The series come from pure builders in `BabyFeed/Models/CareCharts.swift`.

**Tests:**
- Series totals equal `FeedSummary` and `DiaperTally`.
- Missing days produce no zero bars.
- Each day's target equals `currentTarget` at the end of that day.
- The percentile bands equal `GrowthStandard`.

**Prompt**

> Read CLAUDE.md and ROADMAP.md, and read commit ce11c14's message. Do Phase 6 only. Every chart
> must lead with a sentence stating the value, computed by the same code as the numbers, and keep
> the existing TrendsView numbers under "The numbers". Build the CareCharts builders with tests
> first. Update the status table.

---

## Phase 7 — Copy and docs refresh

Stale text found in the audit. Fix whatever earlier phases haven't already replaced.

**Views**
- `RecoveryKeyView`: "not the server, not me".
- `BabyView`: the comment "Don't promise sharing here: it isn't built", and the footer "…'s log stays
  on this iPhone".
- `SettingsView`: "Everyone sees the same feeds", which should become "the same log". The Live
  Activity footer still says "time since the last feed".
- `SummarySheet`: "Anything logged outside feeds".
- `IntakeView`: says it uses the logged diapers, which only becomes true in Phase 4.1.
- `LastFeedWidget`: its description.

**Docs**
- `README.md`: "in huge type, ticking live".
- `PLAN.md`:
  - the Screens section;
  - "What syncs" (add diapers and solid foods);
  - diapers are still listed under "Later";
  - the App Group is `group.com.briantheis.babyfeed`, not `group.com.babyfeed.shared`;
  - "SignIn, Join" views that don't exist;
  - "The app is local-only…".
- `server/README.md` was already refreshed in 3a.

---

## Phase 8 — Rename to "Baby Care" (optional)

The decision is to keep **Baby Feed** for now. If that changes:

**Change**
- `INFOPLIST_KEY_CFBundleDisplayName`, which appears four times in `project.pbxproj` (app and widget,
  Debug and Release). A single `APP_DISPLAY_NAME` build setting makes the next rename one line.
- User-facing strings. Find them with `grep -rn "Baby Feed" BabyFeed BabyFeedWidget Shared`:
  - Info.plist usage strings;
  - intent descriptions;
  - the Siri phrase labels in Settings;
  - the CSV subject;
  - the widget title;
  - the invite text;
  - the summary header and its rewrite prompt.
- App Shortcut phrases already use `\(.applicationName)`, so they follow automatically. Test them on
  a device.

**Never change.** Changing any of these orphans data, pairing, widgets or the TestFlight record:
- the bundle IDs `com.babyfeed.BabyFeed` and `.Widget`;
- the `babyfeed://` scheme, which every invite link and QR uses;
- the App Group `group.com.briantheis.babyfeed`;
- the Keychain services;
- the UserDefaults keys;
- the widget kind `LastFeedWidget`;
- the notification ID `babyfeed.nextFeed`;
- the SwiftData class names;
- the target and module names;
- the server's names, paths and environment variables.

**App Store Connect.** The store name is separate from the home-screen name. It must be unique and
30 characters or fewer, and "Baby Care" is almost certainly taken. Something like "Baby Care:
Feeds & Health" in the store can sit beside "Baby Care" on the home screen.

---

## Later (directional)

**Sync away from home.** The pieces exist: DuckDNS and Caddy (`server/scripts/install-caddy.sh`)
plus one router port-forward, external 4443 to the mini's 9444.
- Add `BABYFEED_PUBLIC_URL`, returned from `/v1/me`.
- The app keeps the LAN and public addresses and falls back between them, using `server_id` to know
  they're the same server.
- Enrolment stays home-only by design: Caddy's requests arrive from loopback with
  `X-Forwarded-For`.
- Never forward 8791.

**"Annette logged a feed" notifications.** An APNs key for this bundle ID, plus the existing
`/v1/changes` feed.

**More of the first year:**
- sleep sessions;
- stool color in the first week (black → green → yellow);
- measurements: temperature with fever guidance, and length and head circumference with WHO
  percentiles, like weight;
- tummy time;
- milestones (CDC);
- vaccinations;
- photos on notes. These need server blob storage: new routes, size caps, and backups that include
  the files.

**After the first year.** When feeds aren't being logged, Today leads with Recent and Health instead
of the countdown. The `.quiet` state from Phase 1 is the start of this.

**Elsewhere:**
- Apple Watch quick log.
- App Intents for diapers and medicines ("Log a wet diaper").
- A "Right now" widget.
- A recovery phrase made of words, easier to copy onto paper. The server can accept both formats.

---

## Appendix A — Adding a synced type

For a new type `Foo` in table `foos`.

**App**

1. **Model.** `BabyFeed/Models/Foo.swift`, an `@Model` with:
   - `uuid: UUID?` and `babyID: UUID?`;
   - every field defaulted or optional, so SwiftData migrates by itself;
   - `loggedByName`, `updatedAt`, `deletedAt`, and `needsUpload = true`;
   - `markChanged()` and `softDelete()`;
   - enums stored as `xxxRaw: String`, with a fallback getter;
   - conformance to `CareEntry`.
2. **Schema.** Add it to `AppSchema.models` (Phase 0).
3. **DTO.** `FooDTO` in `Services/Sync/SyncDTOs.swift`, with snake_case `CodingKeys`, an
   `init(entry:userID:)` that returns nil without a uuid or babyID, and `apply(to:)`. New fields on
   an *existing* DTO are optional and use the "was it sent?" check (Phase 5.1).
4. **`SyncEngine`.**
   - `push`: fetch, filter on `needsUpload`, add to the payload, and clear rows the server accepted,
     but only if `updatedAt` is unchanged.
   - `apply`: `merge(result.foos, …)`.
   - `queueEverything`: add a loop for the new type.
   - At the bottom of the file: `extension FooDTO: SyncRow {}` and `extension Foo: SyncableRow {}`.
5. **`SyncClient`.**
   - `PullResult`: a property, its CodingKey, `decodeIfPresent(…) ?? []` (older servers omit the
     key), and entries in `serverStamps` and `isEmpty`.
   - `SyncPushPayload`: a property, its CodingKey, and an entry in `isEmpty`.
6. **Cleanup and seed data.** Add it to `BabyStore.removeLocally` and `DebugSeed`.
7. **Where it shows up.** A `TimelineItem` case (with category and search text), its row, its
   editor, a "+" tile and an `AppRouter.Sheet` case. Add it to the pediatrician summary if a doctor
   would care, and to the export-everything CSV.
8. **Tests.** A DTO round trip; nil without a baby; `active(for:)` scoping; a soft delete queues an
   upload; the timeline includes it.

**Server**

9. **`server/src/db.js`.**
   - Append the table to `ROW_TABLES`.
   - Add `CREATE TABLE IF NOT EXISTS foos (…, logged_by, logged_by_name, updated_at, deleted_at, server_updated_at, server_ms)`,
     plus a `foos_pull ON foos(baby_id, server_ms)` index.
   - A new column on an *existing* table goes through `COLUMN_ADDITIONS` and `LATE_COLUMNS` instead
     (Phase 5.1).
10. **`server/src/sync.js`.** Add `COLUMNS.foos`, `REQUIRED.foos` and a `normalizeRow` branch.
    - Validate enum values only against a closed set that includes "other"; otherwise use free text
      with a length cap. An older server rejecting a newer app's value makes every sync throw
      `SyncError.rejected`.
    - Add number bounds and cross-field checks.
11. **`server/src/server.js`.** Nothing: push and pull loop over `ROW_TABLES`.
12. **Tests.** A round trip between two caregivers; a malformed row is refused; a delete propagates;
    a stale re-push is kept.

**Deploy the server first**, then ship the app. Mixed app versions across two phones are safe for a
few days: old apps ignore new tables and keys.

---

## Appendix B — Deploying the server to the Mac mini

The Phase 3a changes are on `main`, merged from `sync-server` in PR #2. The mini runs its own
checkout at `~/baby-feed`, which is the path the launchd jobs expect, and until now that checkout
followed `sync-server`. Moving it to `main` is what step 2 does.

The command blocks below deliberately have no `#` comments. A stock macOS zsh doesn't treat `#` as
a comment when you paste, and an apostrophe inside one opens a quote that swallows everything after
it (you're left at a `quote>` prompt; press Ctrl‑C to get out).

1. **On the MacBook:** nothing to do. The work was committed, pushed and merged on 2026-09-28, and
   the mini was updated the same day. Rerun the steps below whenever `server/` changes again.
2. **On the mini:**

   ```sh
   cd ~/baby-feed
   git fetch && git checkout main && git pull --ff-only
   node --version
   (cd server && npm test)
   sqlite3 ~/baby-feed-data/babyfeed.db ".backup '$HOME/baby-feed-data/backups/pre-enroll-$(date +%Y%m%d-%H%M).db'"
   launchctl kickstart -k gui/$(id -u)/com.babyfeed.server
   curl -s http://127.0.0.1:8791/v1/health; echo
   tail -5 ~/baby-feed-data/logs/server.log
   ```

   - Node must be 22.5 or newer.
   - The backup gets its own name because `backup.sh` names files by date only, so a second run on
     the same day would overwrite it.
   - Health should report `"api":2` and `"enroll":"lan"`, and the log should say "new phones: a phone
     on the home Wi-Fi sets itself up".
   - The `.env` needs no change: `BABYFEED_ENROLL` defaults to `lan`, and the mini already listens on
     the Wi‑Fi (`BABYFEED_BIND=0.0.0.0`).
3. **From the MacBook, on the same Wi‑Fi:** `curl -s http://brians-mac-mini.local:8791/v1/health`
   should show `"enroll_available":true`.
4. **Look at what's there** (read-only):

   ```sh
   sqlite3 -readonly ~/baby-feed-data/babyfeed.db \
     "SELECT name, created_at FROM babies; SELECT COUNT(*) FROM feeds;
      SELECT u.display_name, d.name, d.created_at, d.last_seen_at, d.revoked_at
      FROM devices d JOIN users u ON u.id = d.user_id;"
   ```

   On 2026-09-28 it held 1 baby, 2 feeds and 4 paired devices, most likely left over from testing.
5. **Optional: start clean**, if that's test data.

   ```sh
   launchctl bootout gui/$(id -u)/com.babyfeed.server
   for i in {1..30}; do launchctl print gui/$(id -u)/com.babyfeed.server >/dev/null 2>&1 || break; sleep 1; done
   ARCHIVE=~/baby-feed-data/archive/$(date +%Y%m%d-%H%M%S)
   mkdir -p "$ARCHIVE"
   find ~/baby-feed-data -maxdepth 1 -name 'babyfeed.db*' -exec mv {} "$ARCHIVE"/ \;
   launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.babyfeed.server.plist
   curl -s http://127.0.0.1:8791/v1/health; echo
   ```

   Health should then report `paired_devices` 0, `babies` 0, `feeds` 0, and a new `server_id`.
   - Use `bootout`, not `kickstart`: the job restarts itself, and would reopen the database halfway
     through the move.
   - The `for` loop is the wait. `bootout` returns before the old server has finished shutting down,
     so the loop waits (up to 30 s) until launchd has let go of the job. Without it, the old server
     can still be closing the database during the move. As it closes it deletes its `-wal` and
     `-shm` side files, so `mv` fails on them, and `bootstrap` fails with "5: Input/output error"
     because launchd is still removing the job.
   - Never start the server with a leftover `babyfeed.db-wal` or `-shm` in the folder and no matching
     `babyfeed.db`. SQLite would try to replay the old log into the new, empty database.
   - Phones paired to the old database will show "unpaired"; the new app reconnects by itself.
6. **Optional:** give the mini a DHCP reservation on the router. The app uses its `.local` name, so
   this is just belt and braces.
7. **Rollback:** check out the previous server commit and `kickstart`. The old code ignores the new
   tables (`meta` and `account_keys`).

---

## Appendix C — Bugs found in the audit

| Bug | Where | Fixed in |
|---|---|---|
| Two syncs at once on launch and on every foreground | `BabyFeedApp`, `FeedCoordinator`, `SyncEngine.requestSync` | 1 |
| Every pulled page reloads the widgets, Live Activity and alarm, with no change detection | `SyncEngine.apply`, `FeedCoordinator`, `FeedSnapshot.updatedAt` | 1 |
| Per-second text in the accessory, widget and Live Activity; after due, the Live Activity counts *up* | `NextFeedBar`, `LastFeedWidget`, `NextFeedLiveActivity` | 1 |
| An ended Live Activity left in `activities` stops new ones; the 8-hour limit isn't handled | `LiveActivityManager` | 1 |
| Snooze is lost as soon as the app opens | `ReminderScheduler.snooze`/`reschedule` | 1 |
| The accessory's overdue state and its VoiceOver label aren't live | `NextFeedBar` | 1 |
| The hero turns orange at a hard-coded 3 h when reminders are off | `HomeView` (`nudgeAfter`) | 1 |
| Typing the baby's name saves, syncs and refreshes on every keystroke | `BabyView` | 1 |
| Clock times ignore a pinned time zone, and the widget never sees it | `.formatted()` calls; `FeedSnapshot` | 1 |
| `removeLocally` leaves diapers and solid foods behind | `BabyStore.removeLocally` | 0 ✅ |
| Previews list too few models and are likely to crash | `#Preview` blocks | 0 ✅ (`.modelContainer(.preview)`) |
| `DiaperEntryTests` and `SolidFoodTests` had never run | `BabyFeedTests` | 0 ✅ (ran and passed 2026-09-28) |
| History's empty state and summary button count only feeds | `HistoryView` | 2 |
| The summary drops days with only diapers, and has no diaper column | `DaySummaryGenerator`, `SummarySheet` | 2 |
| Weights can't be edited; delete confirmations are inconsistent | `BabyView`, `DiaperSection`, `FoodLogSection` | 2 |
| `FoodLogSection` ignores a pinned time zone | `Calendar.current` | 2 |
| `DiaperTally.changeCount` is unused and double-counts "Both" | `DiaperEntry.swift` | 2 |
| First-phone setup dead-ends once any user exists; the setup code is mixed-case but the field forces capitals | server `/v1/pair/claim`, `PairServerView` | 3a ✅ / 3b |
| `Pairing.token` is non-optional but the server sends `null`, so restoring onto a paired phone always fails | `SyncClient.Pairing` | 3b |
| Opening the recovery key screen can silently replace the key written on paper | `SyncEngine.recoveryKey(for:)` | 3b |
| The recovery row is shown to non-owners, who get a 403 | `FamilyView` | 3b |
| Joining leaves an empty placeholder baby, which `claim` then shares | `SyncEngine.join`/`claim`, `BabyStore.bootstrap` | 3b |
| Edits made during a push lose `needsUpload`; one rejected row aborts the whole sync | `SyncEngine.push`/`sync` | 3b |
| `syncNow` returns at once if a sync is running, so an invite can be requested before the baby exists | `SyncEngine.syncNow` | 3b |
| A 401 clears credentials even if they were just replaced; any 401 reads as "not paired" | `SyncEngine.sync`, `SyncClient.send` | 3b |
| A join mints a new identity, and the app swaps its token for it | server `/v1/pair/invite`; `SyncEngine.join` | 3a ✅ / 3b |
| `UIDevice.current.name` is "iPhone", so rows read "Logged by iPhone" | `SyncEngine.join` | 3b |
| Server: `created_by` gets overwritten, a stored row's baby isn't checked, and `X-Forwarded-For` is trusted | `server/src/server.js` | 3a ✅ |
| `IntakeView` shows fixed expectations, not the logged diapers | `IntakeView` | 4 |
| `CareNote.resolvedAt` is never set, and its doc comment is inverted | `CareNote.swift` | 5 |
| Stale copy (see Phase 7) | various | 7 |
| The launchd plists assume `~/baby-feed`; the Caddyfile hard-codes `/Users/brian/…`; `uninstall-launchd.sh` leaves the Caddy and DuckDNS jobs | `server/launchd`, `server/caddy` | Later (noted) |

## Appendix D — Gotchas

- **The GitHub repo is public.** Never commit an internet-reachable hostname (DuckDNS), a token or a
  key. `Config/Server.local.xcconfig` is gitignored, and a `.local` name only resolves at home.
- **xcconfig.** `//` starts a comment anywhere on a line. `#include?` doesn't fail when the file is
  missing. Later lines win. Don't quote values.
- **Synchronized folders.** Any file in `BabyFeed/`, `Shared/`, `BabyFeedWidget/` or
  `BabyFeedTests/` joins that target automatically, markdown and xcconfig included. Keep docs and
  config at the repo root.
- **`MARKETING_VERSION = 1.2`** is an uncommitted change in `project.pbxproj`. Keep it.
- **The widget's `MARKETING_VERSION` is still 1.0.** The build warns that an extension's version
  must match its app's, and App Store Connect complains at upload. Bump the widget together with
  the app.
- **Keychain items survive deleting the app.** That's undocumented but consistent. It helps a
  restore, but never rely on it alone.
- **`UIDevice.current.name`** has returned "iPhone" since iOS 16 without a special entitlement.
- **Local Network privacy (Apple TN3179).**
  - The prompt appears on the first LAN connection.
  - Attempts made before it's answered, or from the background, fail silently, and nothing tells
    the app the permission status.
  - Explain the prompt just before the first connection, and treat a failure as "away".
- **ATS.** Plain http to the `.local` name needs `NSAllowsLocalNetworking`. Prefer the name to a
  bare IP address.
- **Live Activities** end after 8 hours. `staleDate` plus `context.isStale` let one change its look
  on time without an update from the app.
- **Tests run inside the app** (`TEST_HOST`), so `Bundle.main` is the app. Keep build-config reads
  out of pure helpers.
- **Server tests.** The older test files each share one rate limiter. Put new tests in their own
  files, using `server/test/support.js`.
- **Name clash.** SwiftUI already has `TimelineView`, so call the screen `CareTimelineView`.
- **Claude in Xcode may not see `server/`.** Use Claude Code in Terminal for server work.
