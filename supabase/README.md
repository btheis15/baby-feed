# Caregiver sync backend

Baby Feed works fully offline on one phone. To share a baby between phones
(partner, grandparents, a nanny) it syncs through a small Supabase project.
Setup is about five minutes.

## 1. Create a project

At https://supabase.com/dashboard create a new project (the free tier is plenty).

## 2. Run the schema

Dashboard → SQL Editor → paste `migrations/20260917000000_caregiver_sync.sql` → Run.
Or, with the Supabase CLI linked to the project: `supabase db push`.

This creates `babies`, `baby_members`, `baby_invites`, `feeds`, `weights`, row-level
security so caregivers only ever see the babies they belong to, the `create_invite` and
`join_baby` functions, and realtime on the synced tables.

## 3. Turn on sign-in

Dashboard → Authentication → Providers:

- **Apple** – enable it. For the native iOS sign-in flow the *Client ID* is the app's
  bundle identifier (`com.babyfeed.BabyFeed`, or whatever you changed it to). Also
  enable the **Sign in with Apple** capability on the `BabyFeed` target in Xcode
  (already in `BabyFeed.entitlements`).
- **Email** – enable it so the "email me a code" fallback works. In Authentication →
  Email Templates → *Magic Link*, make sure the body includes `{{ .Token }}` so the
  6-digit code is sent.

## 4. Point the app at the project

Dashboard → Project Settings → API. Copy the **Project URL** and the **anon /
publishable key** into `BabyFeed/Services/Sync/SupabaseConfig.swift`. The publishable
key is safe to ship in the app; row-level security does the protecting.

Until this file is filled in, the app runs local-only and the Caregivers screen says
sync isn't set up.

## How sync works

- The phone's local database stays the source of truth; every screen reads from it, so
  the app is exactly as fast offline as online.
- Each feed/weight has a client UUID, `updated_at` (client clock) and `deleted_at`
  (soft delete). Changes are flagged `needs_upload` and pushed in a batch.
- Pull asks for rows whose `server_updated_at` is newer than the last pull, then merges
  by `updated_at` (last writer wins; an un-pushed local edit is kept unless the remote
  is strictly newer).
- Realtime subscriptions on `feeds` / `weights` / `babies` trigger a pull, so the
  other phone updates within a second or two. Sync also runs on foreground and after
  every local change.
- Sharing: the owner taps *Share*, which uploads the baby and creates a 6-character
  invite code (valid 7 days, 20 uses). Others sign in and enter the code (or open the
  `babyfeed://join/CODE` link the owner sends). Any number of caregivers can join.
