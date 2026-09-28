# Baby Feed

An iPhone app for the first year with a newborn: **when the next feed is due, what the
last one was, how much the baby should be getting**, and the diapers, weigh-ins and worries
around it. Logged in a tap or two, one-handed at 3 a.m., and shared with whoever else is
up.

- **The next feed, not a stopwatch.** A countdown in minutes ("Next feed in 1h 20m · around
  5:10 PM"), with when the last feed was: in the app, on the Lock Screen and Home Screen
  widget, in the Dynamic Island, and via Siri ("When did the baby last eat in Baby Feed?").
  Nothing ticks by the second.
- **Two taps to log a feed, one for a diaper.** Amounts and times are pre-filled, and
  every log shows a toast with Undo and Edit.
- **Reminders** for the next feed, as a notification or a real alarm that rings through
  silent mode (iOS 26 AlarmKit), set from each feed you log
- **How much to feed**: a daily target from the baby's weight using the American Academy
  of Pediatrics rule (2½ oz per pound per day, up to 32 oz), carried forward along the
  baby's WHO growth percentile so it keeps up as they grow, with corrected age for babies
  born early
- **The first weeks**: "Getting enough?" (wet and dirty diapers against what's expected at
  that age, and back to birth weight), which side to start on, a nursing timer with its
  own Live Activity, and a screen that goes dark at night
- **One Timeline** of everything by day (feeds, diapers, food, weigh-ins, notes and
  health), searchable ("eye"), with how long ago each day was. **Charts** of the same log
  each open with a sentence stating the number, with the plain numbers underneath
- **Health**: concerns tracked as episodes ("Red left eye · day 4"), medicines and the
  doses given (the app never suggests a dose), doctor visits with the AAP checkup schedule,
  and vitamin D for breastfed babies
- **For the pediatrician**: a summary since the last visit (optionally rewritten on-device
  by Apple Intelligence) and a CSV of everything
- **Growth percentiles** from the WHO Child Growth Standards, on a weight chart with the
  percentile bands
- **Foods by age**: when solids, allergens and cow's milk can start, and what to keep
  away until when, sourced to the AAP, CDC and WHO
- **Who logged what**: every entry records the caregiver who entered it ("Logged by
  Brian"), and so does the pediatrician summary
- **Two phones, one log, no account.** Sharing runs through a small server you host
  yourself on a Mac mini at home. A second caregiver joins by scanning a QR code, and one
  recovery phrase, written down once, brings every log back to a new phone. The phone
  stays the source of truth and works with no signal
- Ounces or milliliters, pounds or kilograms, a time zone you can pin while travelling.
  No subscription, no ads, no sign-in

See [PLAN.md](PLAN.md) for the research behind the features, the guidance sources and the
iOS integration list, and [ROADMAP.md](ROADMAP.md) for what's been built, phase by phase,
and what comes next.

## Running it

Requires **Xcode 26 or newer** and **iOS 26 or newer**.

1. Open `BabyFeed.xcodeproj`.
2. For both the `BabyFeed` and `BabyFeedWidget` targets: Signing & Capabilities → choose
   your team.
3. Pick a simulator or your iPhone and press Run (`Cmd+R`).
4. `Cmd+U` runs the unit tests, and `cd server && npm test` runs the server's.

To sync, copy `Config/ServerConfig.example.plist` to `BabyFeed/ServerConfig.plist` and put
your Mac mini's address in it. Git ignores that file, so an address never lands in this
public repo. Without it the app works entirely on the phone.

## Sharing between phones

Both caregivers see the same log, through **a server you run yourself** — a Mac mini on
your home network, holding only what two phones need to agree on. No account, no company,
no third-party backend. See [server/README.md](server/README.md) to set it up; it needs
Node and nothing else.

The app stays local-first either way: each phone's own store is the source of truth, every
screen reads it, and logging never waits on the network. Syncing is what makes the
*other* phone agree, afterwards. With no server configured, or no signal, or the mini
switched off, the app works exactly as before.

Pairing is a QR code, not a sign-up:
- **The first phone** sets itself up on your home Wi‑Fi with nothing to type (the mini
  only lets a new phone in from its own network), then shows a recovery phrase to write
  down once.
- **Every phone after that** joins by pointing its Camera at the QR under Share, or by
  opening a link you send. An invite shares only the baby on screen, and is good for a
  day and ten phones.
- **A new or wiped phone** comes back with the recovery phrase: every log you were on
  returns.

For now it syncs on the home network. Away from home, entries wait on the phone and catch
up when you're back ([ROADMAP.md](ROADMAP.md), Later).

Conflicts are last-writer-wins by `updatedAt`, with an un-pushed local edit kept on a tie.
Deletes are soft, so an entry removed on one phone can't come back from the other. The rules
live in `SyncMerge` on the phone and are mirrored — and tested — on the server.

**Free personal team?** Widgets/Live Activity use an App Group and reminders use the Time
Sensitive entitlement; both need a paid developer membership. Remove those capabilities
from `BabyFeed/BabyFeed.entitlements` and `BabyFeedWidget/BabyFeedWidget.entitlements`
(or delete the widget target) and everything else works.

## Project layout

```
BabyFeed/            SwiftUI app: Models, Services (reminders, alarm, Live Activity, sync), Intents (Siri), Views
Shared/              Types compiled into both the app and the widget
BabyFeedWidget/      Lock Screen / Home Screen widget and the Live Activities
BabyFeedTests/       Unit tests (Swift Testing): guidance, growth, stats, timeline, charts, health, CSV, sync
Config/              Example config: the shape of BabyFeed/ServerConfig.plist
server/              The self-hosted sync server (Node, SQLite, launchd)
```

[CLAUDE.md](CLAUDE.md) has the conventions that keep it consistent, for anyone (or any
Claude) changing the code.

## Medical note

Feeding amounts shown by the app are published rules of thumb from the AAP, CDC and
breastfeeding research (sources in PLAN.md). They are a starting point, not a
prescription. Feed on demand and follow your pediatrician's advice. The app records the
medicine you give and never suggests a dose.
