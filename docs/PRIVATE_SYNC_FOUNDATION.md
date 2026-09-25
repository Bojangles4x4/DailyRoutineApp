# Private sync foundation

Daily Routine remains local-first. A cloud connection must be an explicit user action, and local data remains usable when the network or provider is unavailable.

## Chosen architecture

- Authentication and private document storage: Supabase Auth + Postgres.
- Authorization: database grants plus Row Level Security on every exposed table.
- Client credential: a Supabase publishable key only. Secret or service-role keys must never be added to this repository or either app.
- Cloud records: one versioned routine document plus narrowly scoped owner-only auxiliary snapshots.
- Concurrency: optimistic revision checks followed by a three-way merge when another device changed the document first.
- Conflict recovery: local wins only for the conflicting field, and both complete versions plus the conflict paths are retained locally for recovery.
- Offline behavior: every local save is marked pending; cloud acknowledgement is the only action that clears pending changes.

## Privacy boundary

The sync document can contain routine definitions, daily entries, notes, memories, weekly reviews, and ordinary app preferences.

The following remain device-only:

- Apple Health summaries
- HealthKit authorization state
- background photos
- downloaded-backup timestamps
- local snapshots and conflict archives
- Watch reachability and delivery state

No accountability partner can read the owner document in this phase. Partner access will use separate grants and a restricted reporting surface after owner-only sync is proven.

### Personal Systems Agent snapshot

The `agent_snapshots` table contains one separate owner-only JSON row. Daily Routine derives it locally before upload and limits it to routine names/schedules plus completion and skip booleans for a rolling 90-day window. It excludes notes, memories, written responses, medication routines, check-ins, background images, and raw Apple Health values.

The Mac Agent authenticates as the same owner and may only select that owner's row under RLS. Its password is never stored; access and refresh tokens are stored in macOS Keychain. The downloaded snapshot is written mode `0600` and then imported into local SQLite. The Agent does not upload Messages, Calendar, foreground-app activity, observations, recommendations, or its SQLite database.

## Rollout sequence

1. Run the merge and privacy-boundary tests locally.
2. Create a private Supabase project and apply the migration in `supabase/migrations`.
3. Add owner authentication and the document transport. (Implemented with direct email/password sign-in for web and iPhone, plus a web magic-link fallback.)
4. Test one owner across the web app and TestFlight with deliberately conflicting offline changes.
5. Add access revocation and deletion. (Cloud-document deletion is implemented; closed owner-account deletion remains an administrative action.)
6. Only then add partner invitations and read-only reporting policies.

## Security requirements

- RLS must remain enabled for every exposed table.
- The unauthenticated role receives no grants on private routine data.
- The authenticated role can reach only the row where `owner_id = auth.uid()`.
- Every policy is tested before partner access is enabled.
- Personal Systems Agent snapshots remain owner-only and privacy-minimized before they leave the iPhone/web process.
- Health data remains excluded unless a later, separate design is explicitly approved.
- The checked-in client credential is a publishable key. Database passwords and secret/service-role keys remain outside the app and repository.
- New-user enrollment was used only to create the private owner account and is now disabled in both Supabase and the app client before release testing.
