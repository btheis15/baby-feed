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
- History by day with a 24-hour strip of feed times, trends as plain numbers with the
  direction they moved, and a summary for the pediatrician (optionally rewritten
  on-device by Apple Intelligence)
- Weight log with the last change, the steadier whole-log rate, and gain since birth
- **Growth percentiles** from the WHO Child Growth Standards, so the daily target keeps
  up as the baby grows instead of sitting frozen at the last weigh-in — with corrected
  age for babies born early
- **Foods by age**: when solids, allergens and cow's milk can start, and what to keep
  away until when, sourced to the AAP, CDC and WHO
- **Who logged what**: every feed, weight and note records the caregiver who entered it
  ("Logged by Brian"), and that reaches the pediatrician summary too — so a shared log
  reads clearly even when whoever fed the baby wasn't whoever had a free hand to log it
- **Your data stays yours.** No account and no company holding it: the phone is the source
  of truth, and sharing goes through a server in your own house. Works with no signal.
  More than one baby per phone
- **Two phones, one log**: sharing runs through a small server you host yourself on a Mac
  mini at home — not an account with a company. A second caregiver joins by scanning a QR
  code; every feed, weight and note then appears on both phones, offline-tolerant and
  last-writer-wins
- Ounces or milliliters, CSV export, no subscription, no ads, no sign-in

See [PLAN.md](PLAN.md) for the research behind the features, the guidance sources, the
iOS integration list, and what's planned next.

## Running it

Requires **Xcode 26 or newer** and **iOS 26 or newer**.

1. Open `BabyFeed.xcodeproj`.
2. For both the `BabyFeed` and `BabyFeedWidget` targets: Signing & Capabilities → choose
   your team.
3. Pick a simulator or your iPhone and press Run (`Cmd+R`).
4. `Cmd+U` runs the unit tests.

## Sharing between phones

Both caregivers see the same log, through **a server you run yourself** — a Mac mini on
your home network, holding only what two phones need to agree on. No account, no company,
no third-party backend. See [server/README.md](server/README.md) to set it up; it needs
Node and nothing else.

The app stays local-first either way: each phone's own store is the source of truth, every
screen reads it, and logging a feed never waits on the network. Syncing is what makes the
*other* phone agree, afterwards. With no server configured — or no signal, or the mini
switched off — the app behaves exactly as it did before.

Pairing is a QR code, not a sign-up. The first phone connects with a setup code printed by
the mini; every phone after that joins by pointing its Camera at a code on the first phone.
Invites are six characters, good for an hour, and work once.

Conflicts are last-writer-wins by `updatedAt`, with an un-pushed local edit kept on a tie.
Deletes are soft, so a feed removed on one phone can't come back from the other. The rules
live in `SyncMerge` on the phone and are mirrored — and tested — on the server.

**Free personal team?** Widgets/Live Activity use an App Group and reminders use the Time
Sensitive entitlement; both need a paid developer membership. Remove those capabilities
from `BabyFeed/BabyFeed.entitlements` and `BabyFeedWidget/BabyFeedWidget.entitlements`
(or delete the widget target) and everything else works.

## Project layout

```
BabyFeed/            SwiftUI app: Models, Services (reminders, alarm, live activity, sync), Intents (Siri), Views
Shared/              Types compiled into both the app and the widget
BabyFeedWidget/      Lock Screen / Home Screen widget and the Live Activity
BabyFeedTests/       Unit tests for guidance rules, units, stats, CSV, snapshot, sync merge rules
server/              The self-hosted sync server (Node, SQLite, launchd) — `npm test` runs its own suite
```

## Medical note

Feeding amounts shown by the app are published rules of thumb from the AAP, CDC and
breastfeeding research (sources in PLAN.md). They are a starting point, not a
prescription. Feed on demand and follow your pediatrician's advice.
