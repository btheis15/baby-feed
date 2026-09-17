# Baby Feed

An iPhone app for logging newborn feeds so you always know **when the last feed was,
how much it was, and whether it was formula, breast milk, or nursing** — even when your
mind is all over the place from lack of sleep and washing bottles.

- Time since last feed in huge type, updating live
- Log a feed in two taps: pick the kind, tap Save (amount and time are pre-filled)
- Backdate feeds ("15 min ago"), edit or delete anything
- Last-24-hour totals and a day-by-day history
- Ounces or milliliters, CSV export, no account, everything stays on your phone

See [PLAN.md](PLAN.md) for the design, data model, and what's planned next.

## Running it

Requires Xcode 16 or newer and iOS 17 or newer.

1. Open `BabyFeed.xcodeproj`.
2. Select the `BabyFeed` target → Signing & Capabilities → choose your team.
3. Pick a simulator or your iPhone and press Run (`Cmd+R`).
4. `Cmd+U` runs the unit tests.

## Project layout

```
BabyFeed/            SwiftUI app (SwiftData for storage)
  Models/            FeedEntry, FeedKind, VolumeUnit, FeedStats (pure logic)
  Views/             Home, log sheet, history, settings
BabyFeedTests/       Unit tests for conversion, formatting, grouping, CSV
```
