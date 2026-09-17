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
| Seeing patterns ("is she clustering at night?")         | Per-day 24-hour strips and trend charts                     |
| Something to show the pediatrician                      | Plain-text summary (optionally rewritten on-device) + CSV   |
| Partner / caregiver sync (the #1 complaint when broken)  | v3: iCloud sync (see below)                                 |
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

1. **Latest weight known** → daily target = weight × 2½ oz/lb, capped at 32 oz. In the
   first two weeks the age-typical range is shown alongside because intake is ramping up.
2. **"Mostly breast milk" and ≥ 4 weeks old** → 25 oz/day with the 19–30 oz range.
3. **Only the birthday known** → midpoint of the age band's typical range.
4. Per-feed amount = daily target ÷ feeds per day (caregiver setting, or age-typical).
5. Every number is labelled with its basis and a "your pediatrician wins" footnote.
   The target updates the moment a new weight is logged.

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
| Charts for trends and weight                 | Swift Charts                     | `TrendsView.swift`, `BabyView.swift`   |
| Deep links from widgets & notifications      | `babyfeed://log/<kind>` URL scheme | `AppRouter.swift`                    |

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
- **Trends**: bottle volume per day against the target, feeds per day, and a
  "when feeds happen" dot plot (hour of day × day) for spotting clusters.
- Toolbar: **For the pediatrician** – 3/7/14-day plain-text summary, optional on-device
  rewrite, share sheet.

### Baby
Name and birthday (drives age text and the age-based guide), weight log with chart and
weekly gain, feeding style and feeds-per-day, and the age band's typical amounts.

### Settings
Reminders (interval, alarm vs. notification, Live Activity), units (oz/ml, lb·oz/kg),
default amounts, Siri phrases, CSV export.

## Data model

| Model         | Fields                                                                 |
|---------------|------------------------------------------------------------------------|
| `FeedEntry`   | `startTime`, `kindRaw`, `amountML?`, `durationMinutes?`, `sideRaw?`, `note` |
| `WeightEntry` | `date`, `grams`, `note`                                                |

Profile and preferences live in UserDefaults (`BabyProfile`, `AppSettings`, `FeedDefaults`).
Both models are CloudKit-compatible (defaults/optionals, no unique constraints) so sync
can be turned on later without a migration.

## Project layout

```
BabyFeed.xcodeproj/
BabyFeed/                 App target (iOS 26+)
  BabyFeedApp.swift       Container, notification delegate, deep links
  AppRouter.swift         Tab + "open the log sheet" state for widgets/Siri/notifications
  RootView.swift          Tabs, bottom accessory
  Info.plist              URL scheme, AlarmKit usage string, Live Activities
  BabyFeed.entitlements   App Group, time-sensitive notifications
  Models/                 FeedEntry, WeightEntry, FeedStats, FeedingGuidance, BabyProfile, units, settings
  Services/               FeedCoordinator, ReminderScheduler, FeedAlarmScheduler, LiveActivityManager, DaySummaryGenerator
  Intents/                LogFeedIntent, LastFeedIntent, App Shortcuts
  Views/                  Home, LogFeedSheet, History, Trends, Baby, Settings, cards
Shared/                   Compiled into app AND widget: FeedKind, FeedSnapshot, activity attributes, ElapsedText
BabyFeedWidget/           Widget extension: Last Feed widget + Live Activity
BabyFeedTests/            Unit tests (Swift Testing)
```

## Later (v3)

- **Caregiver sync** via CloudKit (SwiftData `cloudKitDatabase`) so both parents see one log.
- **Live nursing timer** with a Live Activity, and pumping.
- **Apple Watch** quick-log and complication.
- Diapers, sleep, medication; growth percentiles (WHO charts).
- iOS 27 App Intents schemas and View Annotations for the new Siri.

## How to run

1. Open `BabyFeed.xcodeproj` in **Xcode 26 or newer** (iOS 26 SDK; the project uses
   AlarmKit, Liquid Glass and Foundation Models).
2. Select the `BabyFeed` target → Signing & Capabilities → pick your team. Do the same
   for `BabyFeedWidget`.
3. Run on an iPhone or simulator running iOS 26+. `Cmd+U` runs the tests.

Widgets and the Live Activity share data through an **App Group**
(`group.com.babyfeed.shared`), and reminders use the **Time Sensitive Notifications**
entitlement. Both need a paid Apple Developer membership. On a free personal team, remove
those two capabilities (or delete the widget target); the app itself, Siri, reminders and
AlarmKit still work.
