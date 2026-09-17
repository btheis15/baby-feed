# Baby Feed

An iPhone app for logging newborn feeds so you always know **when the last feed was, how
much it was, whether it was formula, breast milk or nursing, how much the baby should be
getting, and when the next feed is due** — even when your mind is all over the place from
lack of sleep and washing bottles.

- Time since last feed in huge type, live — in the app, on the Lock Screen widget, in the
  Dynamic Island, and via Siri ("When did the baby last eat in Baby Feed?")
- Log a feed in two taps: pick the kind, tap Save (amount and time are pre-filled)
- Automatic reminder for the next feed, as a notification or a real alarm that rings
  through silent mode (iOS 26 AlarmKit), set from the time of each feed you log
- **How much to feed**: a daily target from the baby's weight using the American Academy
  of Pediatrics rule (2½ oz per pound per day, up to 32 oz), with age-typical ranges,
  updating as you log new weights
- History by day with a 24-hour strip of feed times, trend charts, and a plain-text
  summary for the pediatrician (optionally rewritten on-device by Apple Intelligence)
- Weight log with chart and weekly gain
- Ounces or milliliters, CSV export, no account, no subscription, everything stays on
  your phone

See [PLAN.md](PLAN.md) for the research behind the features, the guidance sources, the
iOS integration list, and what's planned next.

## Running it

Requires **Xcode 26 or newer** and **iOS 26 or newer**.

1. Open `BabyFeed.xcodeproj`.
2. For both the `BabyFeed` and `BabyFeedWidget` targets: Signing & Capabilities → choose
   your team.
3. Pick a simulator or your iPhone and press Run (`Cmd+R`).
4. `Cmd+U` runs the unit tests.

**Free personal team?** Widgets/Live Activity use an App Group and reminders use the Time
Sensitive entitlement; both need a paid developer membership. Remove those capabilities
from `BabyFeed/BabyFeed.entitlements` and `BabyFeedWidget/BabyFeedWidget.entitlements`
(or delete the widget target) and everything else works.

## Project layout

```
BabyFeed/            SwiftUI app: Models, Services (reminders, alarm, live activity), Intents (Siri), Views
Shared/              Types compiled into both the app and the widget
BabyFeedWidget/      Lock Screen / Home Screen widget and the Live Activity
BabyFeedTests/       Unit tests for guidance rules, units, stats, CSV, snapshot
```

## Medical note

Feeding amounts shown by the app are published rules of thumb from the AAP, CDC and
breastfeeding research (sources in PLAN.md). They are a starting point, not a
prescription. Feed on demand and follow your pediatrician's advice.
