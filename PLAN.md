# Baby Feed – Plan

An iPhone app for logging newborn feeds so a sleep-deprived parent always knows
**when the last feed was, how much it was, what it was, how much the baby should be
getting, and when the next feed is due**, and, around the feeds, the diapers, weigh-ins
and health worries of the first year. [ROADMAP.md](ROADMAP.md) records what was built,
phase by phase.

## Guiding principles

1. **Two taps to log a feed, one for a diaper.** Tap the kind (Formula / Breast Milk /
   Nursing), tap Save. Amount and time default to sensible values so most feeds need
   nothing else.
2. **The answer to "when's the next feed?" is the first thing on screen**: a countdown
   in minutes, with when the last feed was, also on the Lock Screen, in the Dynamic
   Island, and via Siri. Nothing ticks by the second, which also saves the battery.
3. **Nothing to set up.** No account and no paywall; data lives on the phone. Sharing is
   opt-in and goes to a server you run yourself.
4. **Forgiving.** Every entry can be edited or deleted. Feeds can be backdated.
5. **Works one-handed at 3 a.m.** Big buttons, high contrast, Dynamic Type, dark mode.
6. **Guidance, not orders.** Feeding targets come from published pediatric rules of
   thumb, are labelled as such, and always defer to the pediatrician.

## What parents say they want (research, Sept 2026)

Looked at 2026 comparison round-ups (Pebbi, Tottli, Baby Daybook, Milk & Minutes,
Medium reviews), App Store listings and reviews for Huckleberry, Baby Tracker, Glow Baby,
Nara, Baby Connect, Feedr and others. Recurring themes:

| Parents love / ask for                                  | How Baby Feed answers it                                   |
|---------------------------------------------------------|------------------------------------------------------------|
| Log in under 3 seconds, one-handed                      | Quick-log buttons pre-filled from the last feed; Siri      |
| "How long since the last feed" without opening the app  | The countdown to the next feed, with the last one, on the widgets, the Live Activity and the tab bar strip |
| A reminder for the next feed that actually wakes you    | Notification or a real AlarmKit alarm that rings through silent mode |
| Knowing whether the baby is getting enough              | Weight- and age-based daily target vs. last 24 h; in the first weeks, diapers and back to birth weight |
| Seeing patterns ("is she clustering at night?")         | Per-day 24-hour strips; charts that each lead with their number; the numbers with a day-part breakdown |
| Something to show the pediatrician                      | Summary since the last visit (optionally rewritten on-device) + CSV of everything |
| Partner / caregiver sync (the #1 complaint when broken)  | Scan a QR on the home Wi‑Fi, nothing to type; one recovery phrase; offline-first |
| No subscription, no ads, privacy                        | Free, no accounts; on the phone and your own Mac mini      |
| Apple Watch, nursing timer, diapers, sleep              | Diapers and a nursing timer are built; Watch and sleep later |

Sources: [Pebbi 2026 comparison](https://pebbi.co/blog/best-baby-tracker-apps-2026),
[Tottli 2026 comparison](https://tottli.com/blog/best-baby-tracker-apps-2026.html),
[Baby Daybook tested & compared](https://babydaybook.app/blog/best-baby-tracking-apps-tested-and-compared-2026/),
[Milk & Minutes comparison](https://milkandminutes.com/blog/baby-tracker-app-comparison),
[Huckleberry App Store reviews](https://apps.apple.com/us/app/huckleberry-baby-tracker/id1169136078?see-all=reviews),
[Baby Tracker & Newborn Log](https://apps.apple.com/us/app/baby-tracker-newborn-log/id551448817),
[Feedr / Simple Breastfeeding Tracker](https://apps.apple.com/us/app/simple-breastfeeding-tracker/id1639579308).

## Feeding guidance (what the numbers are based on)

Implemented in `FeedingGuidance.swift`, tested in `FeedingGuidanceTests.swift`.

- **Formula, by weight (AAP):** about 2½ oz (75 ml) per pound (453 g) of body weight per
  day, usually no more than about 32 oz (960 ml) in 24 hours.
  [HealthyChildren.org – Amount and Schedule of Formula Feedings](https://www.healthychildren.org/English/ages-stages/baby/formula-feeding/Pages/amount-and-schedule-of-formula-feedings.aspx),
  [How much formula does my baby need?](https://www.healthychildren.org/English/tips-tools/ask-the-pediatrician/Pages/How-much-formula-does-my-baby-need.aspx)
- **Typical amounts by age (AAP / CDC):** 1–2 oz every 2–3 h in the first days; 2–3 oz
  every 3–4 h in the first weeks; 3–4 oz by the end of month 1; roughly +1 oz a month;
  6–8 oz at 4–5 feeds by 6 months.
  [CDC – How Much and How Often to Feed Infant Formula](https://www.cdc.gov/infant-toddler-nutrition/formula-feeding/how-much-and-how-often.html)
- **Breastfeeding frequency (AAP):** at least 8–12 feeds per 24 h for newborns; wake a
  sleepy newborn who has gone more than about 3–4 hours without eating until birth weight
  is regained.
  [AAP – Breastfeeding](https://www.aap.org/en/patient-care/newborn-and-infant-nutrition/newborn-and-infant-breastfeeding/),
  [Mayo Clinic – Should I wake my baby for feedings?](https://www.mayoclinic.org/healthy-lifestyle/infant-and-toddler-health/expert-answers/newborn/faq-20057752)
- **Exclusively breastfed intake, 1–6 months:** about 25 oz (750 ml) a day, typical range
  19–30 oz (570–900 ml); it plateaus rather than growing with weight.
  [KellyMom – How much expressed milk will my baby need?](https://kellymom.com/bf/pumpingmoms/pumping/milkcalc/)
- **Weight pattern:** lose up to ~7–10% in the first days, regain birth weight by about
  10–14 days, then gain roughly 5–7 oz (150–200 g) a week.
  [American Pregnancy Association – Newborn Weight Gain](https://americanpregnancy.org/postpartum/newborn-weight-gain/)

How the app applies them:

1. **Weight and sex known** → the weigh-in is converted to a WHO weight-for-age
   percentile, carried forward to today along that percentile, and the 2½ oz/lb rule is
   applied to the estimate. The target therefore grows daily rather than sitting frozen
   at the last weigh-in, and it carries a range from the band either side of the
   percentile instead of one falsely precise number.
2. **Latest weight known, sex not set** → daily target = weight × 2½ oz/lb, capped at
   32 oz. In the first two weeks the age-typical range is shown alongside because intake
   is ramping up.
3. **"Mostly breast milk" and ≥ 4 weeks old** → 25 oz/day with the 19–30 oz range.
4. **Only the birthday known** → midpoint of the age band's typical range.
5. Per-feed amount = daily target ÷ feeds per day (caregiver setting, or age-typical).
6. Every number is labelled with its basis and a "your pediatrician wins" footnote.
   A projected weight is always labelled as an estimate, never as a measurement, and the
   projection stops after three weeks and asks for a fresh weight rather than
   extrapolating indefinitely. Every screen reads the target from one shared call
   (`FeedingGuidance.currentTarget`) so they cannot disagree.

### Growth percentiles

`GrowthStandard.swift` carries the WHO Child Growth Standards weight-for-age LMS tables,
generated from WHO's published PDFs — weekly to 13 weeks, then monthly to 24 months. The
tests recompute all 11 printed centiles at all 35 tabulated ages for both sexes, 770
values, from the LMS parameters and require them to match WHO's own printed numbers, so a
transcription slip fails the build. A baby with a due date is plotted at corrected age.
A drop of a full centile channel (0.67 SD) is stated plainly, because poor weight gain is
the main newborn red flag and a reassuring estimate must not mask it.
[WHO – Weight-for-age](https://www.who.int/tools/child-growth-standards/standards/weight-for-age)

## Reminders and alarms

- The reminder is derived from the **last logged feed + interval** (2–4 h, default 3 h,
  with a one-tap "typical for age" suggestion). Rescheduled automatically on every save,
  edit or delete – no separate alarm to manage.
- **Notification mode:** time-sensitive local notification with "Log a feed" and
  "Remind me in 15 min" actions.
- **Alarm mode (iOS 26+ AlarmKit):** a real alarm that rings through silent mode and
  Focus, shown with the system alarm UI. Alert-only alarms need no Live Activity, so
  this stays in the app target. [WWDC25 – Wake up to the AlarmKit API](https://developer.apple.com/videos/play/wwdc2025/230/)
- The tab-bar accessory, widgets and Live Activity all show the due time.

## Sharing between caregivers

**Status: built.** Sharing runs through a self-hosted server on a Mac mini —
`server/` in this repo, with its own README. Not an account with a company, and
not a hosted backend: the mini holds a copy of what two phones need to agree on
and nothing else.

The app is still local-first. Each phone's SwiftData store is the source of
truth, every screen reads it, and nothing on the path between tapping Save and
seeing the feed touches the network. With no server configured the app behaves
exactly as it did before, and says so under Caregivers. For now it syncs on the
home Wi‑Fi: away from home, entries wait on the phone and catch up when it's
back (sync from anywhere is under Later in ROADMAP.md).

- **Who logged it**: every entry carries the caregiver's display name, shown in the list as "Logged by <name>" and carried into the
  pediatrician summary. Deliberately *logged by*, not *fed by* — the person with
  a free hand to tap Save often isn't the person holding the bottle.
- **Pairing is a QR code, not a sign-up.** The first phone sets itself up with
  nothing typed, and the mini only allows that from its own home network (no
  proxy headers, not through the internet-facing port). Every phone after that
  joins from an invite for the baby on screen, good for a day and ten phones,
  delivered as a QR the stock Camera app reads or as a link you can send. The
  app needs no camera permission: the Camera app does the scanning and hands
  over the `babyfeed://join` URL. A phone that joins becomes a member of that
  log and never makes an identity of its own.
- **One recovery phrase per parent**, not per baby: 24 characters to write down
  when the first baby is backed up, kept in iCloud Keychain, and shown again under
  Caregivers after Face ID. The server only ever sees its SHA-256, and a new or wiped phone
  that types it gets back every log that parent was on. It is never replaced
  without the parent asking.
- **What syncs**: babies (including sex and due date, because the WHO
  percentiles need them), feeds, diapers, solid foods, weights, care notes,
  concerns, medicines, doses and doctor visits. Not preferences: units, reminder
  settings, time zone and learned bottle amounts belong to a phone, not to the
  baby.
- **Merge rules**: `SyncMerge`, unchanged and still transport-agnostic — last
  writer wins, an un-pushed local edit kept on a tie. The server implements the
  same rule from its side and tests it.
- **Deletes** are soft, so a feed deleted on one phone can't be resurrected by
  the other pushing its stale copy.
- **Watermarks**: `SyncEngine.watermark(for:)` per baby, never moving backwards.
  The server's timestamps never repeat a millisecond, so two phones pushing at
  the same instant can't hide a row from each other's next pull. Pushes go in
  batches of 400 rows, and a pull pages through the server's exact `next_since`
  cursor, so a phone joining a long log receives all of it.
- **An old server** says which tables it stores in `/v1/health`. Rows it can't
  store wait on the phone, and the app says "your Mac mini needs an update"
  rather than sending them into the void.
- **The token** lives in the Keychain, not UserDefaults — it's equivalent to the
  whole log and UserDefaults comes back in an unencrypted backup.

- **Why not Supabase**: it was implemented and then removed at the user's
  request — they are self-hosting. The abstractions above survived the removal
  intact, which is the point of keeping the merge rules away from the transport.
- **Why not CloudKit**: sharing would require moving from SwiftData to Core
  Data, and it ties caregivers to Apple Family Sharing.
- **Why SQLite and not Postgres**: the DTOs are snake_case because they were
  shaped for a Postgres table, and they still map straight across. But the
  workload is two phones and a few thousand rows, and a second daemon to keep
  alive across reboots buys nothing for that. One file is also the only backup
  story that can't be got wrong.

### Cross-caregiver notifications

Half-built. `GET /v1/changes` on the server says who changed what and whether it
was you, which was the part that had to exist server-side — a notification
saying "Annette logged a feed" needs a transport to reach the *other* phone, and
a local notification would only fire on the phone that just logged it.

What's left is the client half plus an APNs auth key for this app's own bundle
ID. Until then the phone learns about the other caregiver's feeds on foreground
and after every local change, which is when it syncs.

## iOS integration

| Feature                                      | Framework                        | Where                                  |
|----------------------------------------------|----------------------------------|----------------------------------------|
| Lock Screen & Home Screen widgets            | WidgetKit                        | `BabyFeedWidget/LastFeedWidget.swift`  |
| Dynamic Island / Lock Screen countdown       | ActivityKit (Live Activities)    | `NextFeedLiveActivity.swift`, `LiveActivityManager.swift` |
| Alarm for the next feed                      | AlarmKit (iOS 26)                | `FeedAlarmScheduler.swift`             |
| Time-sensitive reminder with actions         | UserNotifications                | `ReminderScheduler.swift`              |
| "Log a feed" / "When did the baby last eat"  | App Intents + App Shortcuts      | `Intents/FeedIntents.swift`            |
| Pediatrician summary rewritten on-device     | Foundation Models (iOS 26)       | `DaySummaryGenerator.swift`            |
| Persistent strip above the tab bar, glass buttons, minimizing tab bar | SwiftUI iOS 26 (`tabViewBottomAccessory`, `.glassProminent`, `tabBarMinimizeBehavior`) | `RootView.swift`, `LogFeedSheet.swift` |
| Growth percentiles and weight projection     | WHO Child Growth Standards (bundled LMS tables) | `GrowthStandard.swift`, `GrowthProjection.swift` |
| Charts that lead with their number           | Swift Charts                     | `ChartsView.swift`, `CareCharts.swift` |
| Age-based food guidance with sources          | Bundled AAP/CDC/WHO guidance     | `FoodGuidance.swift`, `FoodsView.swift` |
| Deep links from widgets & notifications      | `babyfeed://log/<kind>` URL scheme | `AppRouter.swift`                    |
| Multi-caregiver sync                         | Self-hosted server on a Mac mini | `Services/Sync/`, `server/`      |

Widgets never open the database: the app writes a small JSON `FeedSnapshot` into the
App Group after every change and calls `WidgetCenter.reloadAllTimelines()`.

### iOS 27 (Sept 2026) notes

Apple's WWDC26 iOS guide lists what's new for developers. This project adopts the
parts that are stable and verifiable now, and leaves hooks for the rest:

- **App Intents is the mandatory Siri surface in iOS 27** (SiriKit deprecated). Our
  intents are plain App Intents, so they work with the new conversational Siri as-is.
  Next step: adopt the new *intent schemas* / *entity schemas* so Siri can act without
  fixed phrases, and the *View Annotations API* so "log this again" works on what's on
  screen. [WWDC26 – Explore advanced App Intents features](https://developer.apple.com/videos/play/wwdc2026/343/)
- **WidgetKit**: iOS 27 adds customization through App Intents and dynamic styling, plus
  a `systemExtraLargePortrait` family. Our widget already uses `containerBackground` and
  `widgetAccentable` so it renders correctly in tinted / clear / Liquid Glass modes.
  [WWDC26 – WidgetKit foundations](https://developer.apple.com/videos/play/wwdc2026/277/)
- **Foundation Models** in iOS 27 brings a larger on-device model and tool calling; the
  summary feature uses the same `LanguageModelSession` API and benefits automatically.
- **Liquid Glass** was refined in iOS 27 (less default transparency, user slider). We use
  system components (`.glass`, `.glassProminent`, tab accessory) rather than custom
  materials, so the app follows the user's setting.
- Sources: [Apple Developer – WWDC26 iOS guide](https://developer.apple.com/wwdc26/guides/ios/),
  [Apple Newsroom – new intelligence frameworks and tools](https://www.apple.com/newsroom/2026/06/apple-aids-app-development-with-new-intelligence-frameworks-and-advanced-tools/).

## Screens

Tabs: Today · Timeline · Health · {the baby's name} · Settings.

### Today
The hero: **"Next feed in 1h 20m · around 5:10 PM"**, with when the last feed was, in
minutes; while nursing it becomes the running timer and the side. Then the quick-log
buttons (the next side suggested) and the diaper row, one tap each. In the first six
weeks, **"Getting enough?"**: wet and dirty diapers against what's expected at that age,
and back to birth weight. **Right now** lists a medicine due, a concern due a check-in or
a checkup this week, and is hidden when empty. Then "+ Log something else", the last 24
hours against the daily target, and the most recent entries of any kind. It goes dark at
night.

### Timeline
- **Timeline**: every entry by day, newest first: feeds, diapers, food, weigh-ins, notes,
  concerns, doses and visits. Filter chips and search ("eye"). Each day shows its tallies
  and a 24-hour strip, and older days say how long ago they were and fold into one line.
- **Charts**, over 2 weeks, a month, 3 months or since the last visit. Each chart opens
  with a sentence stating its number:
  - feeds and bottle volume a day against the target;
  - diapers, stacked, with the 6-wet line after the first week;
  - when feeds happen;
  - a care overview with concerns, doses, visits, feeds and diapers, where tapping a day
    lists what was logged on it.

  Under them, **the numbers**: today so far, the last seven complete days against the
  seven before, the average and longest gaps, the day-part breakdown, and the per-day
  totals.
- Toolbar: **For the pediatrician**, a plain-text summary (since the last visit by
  default, or the last 3, 7, 14 or 30 days) with an optional on-device rewrite and a
  share sheet.

### Health
Concerns as episodes with a start and an end ("Red left eye · day 4 · since Sep 25"),
with updates and "It's better". Medicines and the doses given: notices about "too soon"
or the day's limit never block Save, and the app never suggests a dose. Doctor visits,
with what was said, any follow-up, and the next checkup from the AAP schedule. The tab
shows a badge when a medicine is due.

### Baby
Name, birthday, sex and an optional due date (sex and due date only feed the WHO
percentiles). Weight: the latest weigh-in, a **weight chart** against the WHO percentile
bands, the last change, the whole-log rate against the typical 5–7 oz/week, and gain
since the first weigh-in. **Growth**: current percentile with its drift since the last
weigh-in, today's estimated weight with a range, a countdown to the next weigh-in, and a
plain warning if the baby has dropped a full centile band. **Foods by age**, feeding style
and feeds-per-day, the age band's typical amounts, and the caregivers.

### Foods by age
Reached from the Baby tab, and it tracks the baby's age: what to offer now, what's still
off the menu with the age each limit lifts, what they've just outgrown, and what's coming.
Age limits are the AAP/CDC ones (honey, cow's milk as a drink and juice until 12 months;
plain water until 6; added sugars and caffeine until 24; choking hazards, unpasteurized
food, high-mercury fish and non-soy plant milks at any age) and are pinned by tests. Every
rule cites a source, and a test fails the build if one cites anything but the AAP, CDC or
WHO. A separate **"Where the evidence is still moving"** section carries live professional
disagreement — the 4-vs-6-month ESPGHAN/AAP split, what LEAP and EAT actually showed about
early allergen introduction, the BLISS baby-led-weaning trial — each naming real papers,
under a disclaimer that they are not the current consensus. It carries peer-reviewed work
only: settled dangers stay in the hard avoid list, and a test stops them appearing there
as open questions.

### Settings
Caregivers and sync (share, members, your recovery phrase, and a typed address or code
under Advanced), reminders (interval, alarm vs. notification, the Lock Screen countdown),
dark at night, units (oz/ml, lb·oz/kg), time zone (automatic, following the device, or
pinned to keep the log on home time while travelling), default amounts, Siri phrases, CSV
export.

## Data model

| Model            | Fields                                                                 |
|------------------|------------------------------------------------------------------------|
| `Baby`           | `uuid`, `name`, `birthDate?`, `sexRaw`, `dueDate?`, `isShared`, `ownerUserID?` + sync fields |
| `FeedEntry`      | `startTime`, `kindRaw`, `amountML?`, `durationMinutes?`, `sideRaw?`, `note` |
| `DiaperEntry`    | `time`, `kindRaw` (wet, dirty or both), `note`                         |
| `SolidFoodEntry` | `time`, `name`, `textureRaw`, `reactionRaw`, `note`                    |
| `WeightEntry`    | `date`, `grams`, `note`                                                |
| `CareNote`       | `date`, `kindRaw`, `note`, `severityRaw?`, `resolvedAt?`, `concernID?` (an update on a concern) |
| `HealthConcern`  | `title`, `kindRaw`, `startedAt`, `resolvedAt?`, `severityRaw?`, `note`, `outcome` |
| `Medication`     | `name`, `kindRaw`, `doseAmount?`, `doseUnitRaw`, `scheduleRaw`, `timesPerDay?`, `intervalHours?`, `minHoursBetween?`, `maxDosesPer24h?`, `startDate`, `endDate?`, `instructions` |
| `MedicationDose` | `medicationID?`, `medicationName`, `time`, `amount?`, `unitRaw?`, `note` |
| `DoctorVisit`    | `date`, `kindRaw`, `provider`, `reason`, `doctorNotes`, `followUpDate?`, `followUpNote`, `vaccines`, `weightEntryID?` |

Every entry also has `uuid`, `babyID` and `loggedByName`, and every model has the sync
fields: `updatedAt`, `deletedAt` (soft delete) and `needsUpload`. The list of models lives
once, in `AppSchema.models`. The current baby's profile is mirrored into UserDefaults
(`BabyProfile`) so the rest of the app can read it synchronously; `BabyStore` keeps the two
in step. Preferences live in `AppSettings` / `FeedDefaults`.

## Project layout

```
BabyFeed.xcodeproj/
BabyFeed/                 App target (iOS 26+)
  BabyFeedApp.swift       Container, notification delegate, deep links
  AppRouter.swift         Tab, the one sheet showing, and deep links from widgets/Siri/notifications
  RootView.swift          Tabs, bottom accessory, dark at night
  Info.plist              URL scheme and AlarmKit usage string (Live Activities and the Local
                          Network prompt are build settings)
  BabyFeed.entitlements   App Group, time-sensitive notifications
  ServerConfig.plist      This build's sync server (gitignored; see Config/)
  Models/                 The @Model types (AppSchema lists them), FeedingGuidance, IntakeGuidance,
                          FirstWeeks, GrowthStandard + WHOWeightForAge + GrowthProjection,
                          FoodGuidance, HealthLogic, Timeline, CareCharts, stats, units, settings
  Services/               FeedCoordinator, BabyStore, ReminderScheduler, FeedAlarmScheduler,
                          LiveActivityManager, NursingTimer, DaySummaryGenerator, CareLogCSV, DebugSeed
  Services/Sync/          SyncEngine (connect, push, pull), SyncPlan (its decisions), SyncClient
                          (transport), SyncMerge (pure rules), SyncDTOs, SyncCredentials, SyncLink,
                          RecoveryKey, ServerConfig
  Intents/                LogFeedIntent, LastFeedIntent, App Shortcuts
  Views/                  Home and its cards, CareTimelineView, ChartsView, TrendsView, HealthView,
                          BabyView, FoodsView, SettingsView, onboarding, sharing and join, sheets
Shared/                   Compiled into app AND widget: FeedKind, FeedCountdown, FeedSnapshot,
                          activity attributes, ElapsedText, NursingSide
BabyFeedWidget/           Widget extension: Next Feed widget + the Live Activity
BabyFeedTests/            Unit tests (Swift Testing)
Config/                   ServerConfig.example.plist
server/                   The self-hosted sync server (Node, SQLite, launchd)
```

## Later

[ROADMAP.md](ROADMAP.md) keeps the list: sync from anywhere, not just the home Wi‑Fi;
a notification on the other caregiver's phone; sleep; length and head-circumference
percentiles; milestones and vaccines; pumping; photos; an Apple Watch quick-log; App
Intents for diapers and medicines, and iOS 27's intent schemas for the new Siri.

## How to run

1. Open `BabyFeed.xcodeproj` in **Xcode 26 or newer** (iOS 26 SDK; the project uses
   AlarmKit, Liquid Glass, Swift Charts and Foundation Models).
2. Select the `BabyFeed` target → Signing & Capabilities → pick your team. Do the same
   for `BabyFeedWidget`.
3. Run on an iPhone or simulator running iOS 26+. `Cmd+U` runs the tests.
4. There is nothing to sign into. Without `BabyFeed/ServerConfig.plist` the app keeps
   everything on the phone, and Caregivers says so. To sync, copy
   `Config/ServerConfig.example.plist` there and fill in the Mac mini's address.

Widgets and the Live Activity share data through an **App Group**
(`group.com.briantheis.babyfeed`), and reminders use the **Time Sensitive Notifications**
entitlement. Both need a paid Apple Developer membership. On a free personal team, remove
those two capabilities (or delete the widget target); the app itself, Siri, reminders and
AlarmKit still work.
