# Daily Routine

A mobile-first private routine and mood tracker designed to run as a Progressive Web App (PWA) on GitHub Pages.

## Version 1.16.0 development features

- A development-only Family Controls prototype with Apple’s private app and website picker
- Real Managed Settings shielding with explicit Apply test lock and Remove test lock controls
- On-device storage of opaque Apple selection tokens; selected app names and browsing history are not exposed to Daily Routine
- One clean Daily Routine header without a repeated screen subtitle
- A native truth-reminder library for text and pictures, with selected or shuffled notifications and a configurable daily schedule
- Reviewable Apple Health sleep suggestions that save bedtime to the date it occurred and wake time to the following morning
- Phone-safe actual-time fields that keep the time and Now button from overlapping
- A separate manual reward tracker that will be connected to the native shield after the physical-device test and Apple distribution approval
- A calmer Setup landing page organized into Routine, Appearance, Faith, Health, and Data sections
- Compact wake, bedtime, schedule, and sleep-time controls that preserve phone space
- Morning and later Earned Access stages based on selected routine completion, with separate configurable rewards
- Named multi-app reward groups, while automatic app selection and enforcement remain pending Apple Family Controls approval
- Apple Health source labels that can surface Apple Watch, Garmin Connect, and other apps contributing Health samples
- A Truth Before Tasks reminder to choose faithfulness over infallibility, trust over certainty, and the Lord over being right
- Truth Before Tasks daily opening before the rest of the routine unlocks
- Optional two-minute Convictions Before Circumstances phase with editable convictions and optional Scripture for each one
- Apple Watch routine list for completing or reopening the exact checkbox or medication item you choose
- Customizable bottom Watch shortcut, with Water +1 as the default
- Apple Watch dictation capture for general notes, prayers, and action items
- Native Earned Access rounds that record the current Apple Health step count, count only additional steps, and show when extra app time has been earned
- Fixed 1,000-step rounds or an optional 750 → 1,000 → 1,500 escalating pattern, with configurable labels and reward minutes
- Open-ended Truth Before Tasks themes with a title, body, and Scripture instead of required content categories
- Fixed bottom navigation that remains visible while scrolling
- Compact, phone-safe medication and schedule time controls
- Health sleep suggestions confirmed with separate bedtime and wake dates
- Gentle confirmation for morning medication logged in the evening or evening medication logged in the morning
- Right- or left-handed routine control placement, configurable in Setup
- Larger phone tap targets for checkboxes, rating buttons, and small routine actions
- Note capture stays within the phone viewport, with stacked and fully inset date fields on iPhone
- Simplified note capture with one resurfacing date and optional source/snooze details
- Morning, Throughout the Day, and Evening routine sections
- Custom wake-up and bedtime targets
- Custom routine items with five input types:
  - checkbox
  - 0–10 rating
  - number + optional unit
  - time
  - comments
- Daily / weekday / weekend frequency
- Mood, energy, stress, and daily notes
- Daily completion percentage and 80%+ streak
- 30-day history
- CSV progress export
- Local daily or weekly accountability reports with an exact preview before sharing
- Separate privacy controls for routine, medication, rating, and Apple Health summaries
- Optional report-only reflections for wins and areas where support would help
- Native iPhone Share sheet plus copy and browser sharing fallbacks
- JSON backup / restore
- Grace-first daily foundation that keeps identity separate from completion
- Searchable Notes & Thoughts hub for routine notes, Memory Bank entries, and standalone notes
- Standalone note types for Entrust to the Lord, Review later, Action items, Prayer, God Moments, and General notes
- Optional review dates, prayer Scripture/truth, completion/reopening, and capture-source metadata
- God Moments Markdown/text import and occasional in-app resurfacing
- Migration of legacy Thought Inbox entries without deleting the old storage
- URL-prefilled quick capture for future Apple Watch, Pushcut, and Shortcuts integrations
- Guided weekly Review & Reflect dashboard for due notes, action items, active prayers, and recent God Moments
- Prayer follow-up states for still praying, answered, and archived, with answered prayers convertible to God Moments
- Pinned notes and chosen-date snoozing
- Occasional, weekly, or disabled God Moment resurfacing
- Visible backup age with a gentle monthly reminder
- Phone-sized note capture with a keyboard-safe scrolling body and always-visible Save button
- Works offline after first load
- Local-first storage that remains usable while offline
- Optional owner-only private sync with direct account sign-in and a web magic-link fallback, device-only privacy exclusions, pending-change tracking, optimistic revisions, and recoverable three-way conflict merging

## Quick capture links

The app can open directly into a prefilled note capture. Parameters are URL encoded:

```text
?capture=note&text=Remember%20this&type=entrust&source=watch
```

Supported types are `entrust`, `review`, `action`, `prayer`, `god-moment`, and `general`. Common source aliases such as `watch`, `pushcut`, and `shortcut` are normalized for display.

## GitHub Pages deployment

1. Create a new GitHub repository, for example `daily-routine-app`.
2. Upload all files from this folder to the repository root.
3. In the repository, open **Settings → Pages**.
4. Under **Build and deployment**, select **Deploy from a branch**.
5. Choose the `main` branch and `/(root)`, then save.
6. Open the GitHub Pages URL after deployment completes.

## Install on iPhone

Open the GitHub Pages URL in Safari → Share → **Add to Home Screen** → enable **Open as Web App** if offered.

## Privacy note

Data is stored locally first. If private sync is connected, routine definitions, daily entries, notes, memories, weekly reviews, and ordinary preferences are also stored in the owner's Supabase account row. Apple Health summaries, automatic Health-based step values, Earned Access baselines and progress, Screen Time authorization and opaque app-selection tokens, background photos, local snapshots, downloaded backups, and conflict archives remain device-only. Sleep suggestions become ordinary routine history only after the user applies them. Clearing browser storage can erase the local copy, so use Download backup periodically.

- [Privacy Policy](privacy.html)
- [Support](support.html)

## Owner-only private sync

The current manual report intentionally shares only after the user previews and chooses a destination. Private sync uses:

- Front end: this GitHub Pages PWA and its bundled iPhone web view
- Authentication + database: Supabase Auth and Postgres
- Row-level security: each owner can access only their own routine document
- Local-first behavior: offline changes remain pending until the server acknowledges a matching revision
- Privacy boundary: Health summaries, background photos, local backups, and conflict archives remain device-only

Run the sync foundation tests with:

```text
node tests/sync-core.test.js
node tests/sync-cloud.test.js
```

See `docs/PRIVATE_SYNC_FOUNDATION.md` and `supabase/migrations/202608250001_private_sync_foundation.sql` for the design and database policy.

Do not publish personal routine/mood data directly into the GitHub repository or a public Google Sheet.
