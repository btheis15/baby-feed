# Baby Feed – Plan

An iPhone app for logging newborn feeds so a sleep-deprived parent always knows
**when the last feed was, how much it was, what it was, how much the baby should be
getting, and when the next feed is due**.

## Guiding principles

1. **Two taps to log a feed.** Tap the kind (Formula / Breast Milk / Nursing), tap Save.
   Amount and time default to sensible values so most feeds need nothing else.
2. **The answer to "when did I last feed?" is the first thing on screen**, in huge type,
   ticking live, and also on the Lock Screen, in the Dynamic Island, and via Siri.
3. **Nothing to set up.** No account, no sync, no paywall. Data lives on the phone.
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
| "How long since the last feed" without opening the app  | Lock Screen + Home Screen widgets, Live Activity, tab bar strip |
| A reminder for the next feed that actually wakes you    | Notification or a real AlarmKit alarm that rings through silent mode |
| Knowing whether the baby is getting enough              | Weight- and age-based daily target vs. last 24 h            |
| Seeing patterns ("is she clustering at night?")         | Per-day 24-hour strips; trends as numbers with a day-part breakdown |
| Something to show the pediatrician                      | Plain-text summary (optionally rewritten on-device) + CSV   |
| Partner / caregiver sync (the #1 complaint when broken)  | Shared baby with invite codes; any number of caregivers; offline-first |
| No subscription, no ads, privacy                        | Free, local-only, no accounts                               |
| Apple Watch, nursing timer, diapers, sleep              | Later                                                       |

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

**Status: not built.** The app is local-only and says so under Caregivers. There is no
account, no third-party backend, and nothing leaves the phone.

What exists today:

- **Who logged it**: every feed, weight and care note carries the caregiver's display
  name, shown in the list as "Logged by <name>" and carried into the pediatrician
  summary. Deliberately *logged by*, not *fed by* — the person with a free hand to tap
  Save often isn't the person holding the bottle.
- **Local-first storage**: the on-device SwiftData store is the source of truth and every
  screen reads it. Rows already carry a client `uuid`, `updatedAt`, a soft `deletedAt`
  and `needsUpload`, so changes can be queued and conflicts resolved.
- **Merge rules**: `SyncMerge` holds them — last writer wins, keeping an un-pushed local
  edit on ties. Transport-agnostic and unit-tested.
- **Row shapes**: `SyncDTOs`, still snake_case so a Postgres table maps straight across.
- **Watermarks**: `SyncEngine.watermark(for:)` records how far a pull got per baby, and
  never moves backwards.

What's missing is only the client: push rows where `needsUpload` is true, pull rows the
server has touched since the watermark, hand each to `SyncMerge`. No caller above
`SyncEngine` changes when that lands, because `requestSync()` is already called after
every local change and is currently a guarded no-op.

The plan is a **small server hosted on a Mac Mini on the home network** — Postgres
holding only what two phones need to agree on. Not an account with a company. Credentials
stay on-device; pairing a second caregiver should be a QR code scanned from the first
phone rather than a sign-up.

- **Why not Supabase**: it was implemented and then removed at the user's request — they
  are self-hosting. The abstractions above survived the removal intact, which is the
  point of keeping the merge rules away from the transport.
- **Why not CloudKit**: sharing would require moving from SwiftData to Core Data, and it
  ties caregivers to Apple Family Sharing. Still an option later for the single-user case.

### Cross-caregiver notifications

Requested, and blocked on the same server. A notification telling the *other* caregiver
that a feed was logged needs a transport to reach the other phone — either a push from
the server or a poll from the receiving device. A local notification would only fire on
the phone that just logged the feed, which is useless. So this waits for the Mac Mini
rather than shipping something that looks like it works.

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
| Age-based food guidance with sources          | Bundled AAP/CDC/WHO guidance     | `FoodGuidance.swift`, `FoodsView.swift` |
| Deep links from widgets & notifications      | `babyfeed://log/<kind>` URL scheme | `AppRouter.swift`                    |
| Multi-caregiver sync (not built)             | Self-hosted server, planned      | `Services/Sync/` (merge rules, DTOs, watermarks) |

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

### Today
Last-fed hero (turns orange past the reminder interval), three quick-log buttons,
**Daily target** card (consumed vs. target, per-feed amount, basis), last-24-hour totals,
recent feeds. Title is the baby's name.

### History
- **Days**: every day with a 24-hour strip of feed times, totals, and the entries.
- **Trends**: numbers rather than charts. Today so far against the target; the last
  seven *complete* days' volume and feeds per day with the direction they moved against
  the previous seven; average gap and longest stretch; a day-part breakdown
  (overnight / morning / afternoon / evening) that answers "is she clustering at night?";
  and the exact per-day totals.
- Toolbar: **For the pediatrician** – 3/7/14-day plain-text summary, optional on-device
  rewrite, share sheet.

### Baby
Name, birthday, sex and an optional due date (sex and due date only feed the WHO
percentiles). Weight log with the last change, the whole-log rate against the typical
5–7 oz/week, and gain since the first weigh-in. **Growth**: current percentile with its
drift since the last weigh-in, today's estimated weight with a range, a countdown to the
next weigh-in, and a plain warning if the baby has dropped a full centile band.
**Foods by age**, feeding style and feeds-per-day, and the age band's typical amounts.

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
Caregivers & sync (sign in, share, invite codes, members, join, switch babies), reminders
(interval, alarm vs. notification, Live Activity), units (oz/ml, lb·oz/kg), time zone
(automatic, following the device, or pinned to keep the log on home time while
travelling), default amounts, Siri phrases, CSV export.

## Data model

| Model         | Fields                                                                 |
|---------------|------------------------------------------------------------------------|
| `Baby`        | `uuid`, `name`, `birthDate?`, `isShared`, `ownerUserID?` + sync fields |
| `FeedEntry`   | `uuid`, `babyID`, `startTime`, `kindRaw`, `amountML?`, `durationMinutes?`, `sideRaw?`, `note`, `loggedByName` + sync fields |
| `WeightEntry` | `uuid`, `babyID`, `date`, `grams`, `note`, `loggedByName` + sync fields |

Sync fields on every model: `updatedAt`, `deletedAt` (soft delete), `needsUpload`.
The current baby's name and birthday are mirrored into UserDefaults (`BabyProfile`) so
the rest of the app can read them synchronously; `BabyStore` keeps the two in step.
Preferences live in `AppSettings` / `FeedDefaults`.

## Project layout

```
BabyFeed.xcodeproj/
BabyFeed/                 App target (iOS 26+)
  BabyFeedApp.swift       Container, notification delegate, deep links
  AppRouter.swift         Tab + "open the log sheet" state for widgets/Siri/notifications
  RootView.swift          Tabs, bottom accessory
  Info.plist              URL scheme, AlarmKit usage string, Live Activities
  BabyFeed.entitlements   App Group, time-sensitive notifications
  Models/                 Baby, FeedEntry, WeightEntry, FeedStats, WeightStats, FeedingGuidance,
                          GrowthStandard + WHOWeightForAge + GrowthProjection, FoodGuidance,
                          BabyProfile, units, settings
  Services/               FeedCoordinator, BabyStore, ReminderScheduler, FeedAlarmScheduler, LiveActivityManager, DaySummaryGenerator
  Services/Sync/          SyncEngine (local-only), SyncMerge (pure rules), SyncDTOs
  Intents/                LogFeedIntent, LastFeedIntent, App Shortcuts
  Views/                  Home, LogFeedSheet, History, Trends, Baby, Foods, Settings, TimeZonePicker,
                          Family (caregivers), SignIn, Join, cards
Shared/                   Compiled into app AND widget: FeedKind, FeedSnapshot, activity attributes, ElapsedText
BabyFeedWidget/           Widget extension: Last Feed widget + Live Activity
BabyFeedTests/            Unit tests (Swift Testing)
```

## Later (v3)

- **Live nursing timer** with a Live Activity, and pumping.
- **Apple Watch** quick-log and complication.
- Diapers, sleep, medication; length and head-circumference percentiles.
- iOS 27 App Intents schemas and View Annotations for the new Siri.

## How to run

1. Open `BabyFeed.xcodeproj` in **Xcode 26 or newer** (iOS 26 SDK; the project uses
   AlarmKit, Liquid Glass and Foundation Models).
2. Select the `BabyFeed` target → Signing & Capabilities → pick your team. Do the same
   for `BabyFeedWidget`.
3. Run on an iPhone or simulator running iOS 26+. `Cmd+U` runs the tests.
4. The app is local-only. There is nothing to configure and nothing to sign into; the
   Caregivers screen says so.

Widgets and the Live Activity share data through an **App Group**
(`group.com.babyfeed.shared`), and reminders use the **Time Sensitive Notifications**
entitlement. Both need a paid Apple Developer membership. On a free personal team, remove
those two capabilities (or delete the widget target); the app itself, Siri, reminders and
AlarmKit still work.
