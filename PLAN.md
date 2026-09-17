# Baby Feed – Plan

An iPhone app for logging newborn feeds so a sleep-deprived parent always knows
**when the last feed was, how much it was, and what it was**.

## Guiding principles

1. **Two taps to log a feed.** Tap the kind (Formula / Breast Milk / Nursing), tap Save.
   The amount and time default to sensible values so most feeds need nothing else.
2. **The answer to "when did I last feed?" is the first thing on screen**, in huge type,
   ticking live ("1h 23m").
3. **Nothing to set up.** No account, no sync, no permissions. Data lives on the phone.
4. **Forgiving.** Every entry can be edited or deleted. Feeds can be backdated
   ("15 min ago") because you usually log after the baby is asleep.
5. **Works one-handed at 3 a.m.** Big buttons, high contrast, no tiny controls,
   supports Dynamic Type and dark mode by default.

## v1 scope

### Screen 1 – Today (home)
- **Last fed** card: elapsed time since last feed in large type, plus what it was
  ("3 oz formula · 2:14 AM"). Turns orange after 3 hours as a gentle nudge.
- **Last 24 hours** card: number of feeds, total bottle volume, nursing minutes.
  (24-hour window instead of "since midnight" so the 11 PM feed doesn't vanish at 12:01.)
- **Three big quick-log buttons**: Formula, Breast Milk (bottle), Nursing.
  Each shows the amount it will default to.
- **Recent feeds** list for the last 24 hours; tap to edit, swipe to delete.

### Log / edit sheet
- Kind switcher (segmented) in case the wrong button was tapped.
- Bottle feeds: big amount readout with − / + steppers (0.5 oz or 10 ml) and preset chips.
- Nursing: duration chips (5–45 min) with − / + and a Left / Right / Both side picker.
- Time: "Now", "15 min ago", "30 min ago", "1 hr ago" chips plus a full date/time picker.
- Optional note ("spit up", "fussy", …).
- One large Save button. Delete button when editing.
- The saved amount becomes the new default for that kind.

### Screen 2 – History
- All feeds grouped by day, newest first. Each day header shows feed count,
  total volume and nursing minutes.
- Same tap-to-edit / swipe-to-delete behaviour.

### Screen 3 – Settings
- Units: ounces or milliliters (all stored values are ml; the UI converts).
- Default amount per bottle kind.
- Export all feeds as CSV via the share sheet (handy for the pediatrician).

## Data model

One SwiftData model, `FeedEntry`:

| Field             | Type      | Notes                                   |
|-------------------|-----------|-----------------------------------------|
| `startTime`       | Date      | When the feed started                   |
| `kindRaw`         | String    | `formula`, `breastMilk`, `nursing`      |
| `amountML`        | Double?   | Bottle volume, always stored in ml      |
| `durationMinutes` | Int?      | Nursing only                            |
| `sideRaw`         | String?   | Nursing only: `left`, `right`, `both`   |
| `note`            | String    | Free text, may be empty                 |

User preferences (units, defaults) live in `@AppStorage` (UserDefaults).

## Technical decisions

- **SwiftUI + SwiftData, iOS 17+.** Least code, no third-party dependencies,
  free persistence, previews for fast iteration.
- **Local only.** SwiftData with the default store. iCloud sync can be turned on later
  by switching the container to CloudKit; the model is already CloudKit-compatible
  (all properties have defaults or are optional, no unique constraints).
- **Pure logic lives outside views** (`FeedStats`, `VolumeUnit`) so it is unit-tested
  without a simulator UI.
- **Xcode 16 project** using folder-synchronized groups, so adding a Swift file to the
  `BabyFeed/` folder adds it to the target automatically. No project surgery needed.

## Project layout

```
BabyFeed.xcodeproj/
BabyFeed/
  BabyFeedApp.swift          App entry, SwiftData container
  RootView.swift             Tab bar: Today / History / Settings
  Models/
    FeedKind.swift           Enum: formula, breastMilk, nursing (+ colour, icon)
    NursingSide.swift
    VolumeUnit.swift         oz <-> ml conversion and formatting
    FeedEntry.swift          SwiftData @Model
    FeedStats.swift          Elapsed-time text, 24h summary, day grouping, CSV
    FeedDefaults.swift       AppStorage keys and default amounts
  Views/
    HomeView.swift
    LastFedCard.swift
    SummaryCard.swift
    QuickLogButtons.swift
    LogFeedSheet.swift
    FeedRow.swift
    HistoryView.swift
    SettingsView.swift
  Assets.xcassets/
BabyFeedTests/
  VolumeUnitTests.swift
  FeedStatsTests.swift
```

## Later (not in v1)

- Home-screen / lock-screen **widget** showing time since last feed.
- **Live nursing timer** (start / stop instead of picking a duration).
- **Reminders** ("it's been 3 hours").
- **Multiple caregivers** via iCloud sync (CloudKit) so both parents see the same log.
- Diapers, sleep, pumping.
- Apple Watch quick-log.

## How to run

1. Open `BabyFeed.xcodeproj` in Xcode 16 or newer.
2. Select the `BabyFeed` target → Signing & Capabilities → pick your team.
3. Choose an iPhone simulator or your phone and press Run.
4. `Cmd+U` runs the unit tests.
