# Daily Routine

A mobile-first private routine and mood tracker designed to run as a Progressive Web App (PWA) on GitHub Pages.

## Version 1.25.0 development features

- Build 27 restores the six-cup water goal, preserves each recorded day’s numeric targets, merges convictions individually during Private Sync, and keeps a device-only recovery copy before synced convictions change
- Build 26 makes the sharing boundary clearer, adds select-all and selection counts, and allows memory-style routines to share their name and completion while keeping remembered text private
- Build 25 lets each owner choose the exact non-sensitive routines a partner may see, adds 30-day completion history and routine trends to the privacy-filtered snapshot, and gives multi-person partners search, attention filters, sorting, and seven/30-day views
- Build 24 gives accountability partners a focused, read-only results dashboard instead of a second copy of the routine app
- Partner accounts bypass Truth Before Tasks and hide Today, Notes, Setup, personal analytics, editing tools, and the routine navigation footer
- Invitation links now land on the correct internal Progress view, and partner sign-in never creates or synchronizes a separate routine document
- Build 23 adds a privacy-filtered accountability foundation with one-to-one sharing and a many-person partner roster
- Every owner-to-partner connection has independent permissions and pending, active, paused, or revoked access
- Partners receive a small read-only progress snapshot rather than the owner’s full routine document
- Notes, prayer text, written reflections, medication names/times, and raw Apple Health data are always excluded from private accountability snapshots
- Build 22 combines new routine and walking rewards with the active automatic allowance so selected apps do not relock at an obsolete internal boundary
- Earned-app notifications now describe the shared remaining balance instead of showing cumulative use inside an internal allowance
- Build 21 refreshes visible Health and walking progress automatically when new step samples arrive while Daily Routine is open
- Walking milestones now notify in five-minute earned-time increments, while selected-app usage continues to report five-minute remaining-time checkpoints
- Adds a collapsed, privacy-safe reliability status for Health freshness, Screen Time protection, daily schedules, notifications, and widget syncing
- Replaces the ambiguous double-check section control with a compact, clearly labeled All action
- Build 20 redesigns Today around a compact foundation, focused routine rows, larger task targets, and less repeated metadata
- Removes Skip from active routine scoring and reclaims that space for the actions used every day
- Moves day type into the date toolbar, collapses completed sleep-time details, and removes the redundant Today snapshot
- Adds compact Water controls, morning check-ins, God Moment resurfacing, capture actions, and linked Bible-reading actions
- Build 19 Earned Access hardening: an independent midnight relock schedule, visible schedule health, and automatic schedule repair when the app becomes active
- Compact five-minute foreground-usage checkpoints with notifications and an exact final relock checkpoint
- Immediate Health, Earned Access, and widget snapshot refresh when returning to Daily Routine
- Newly earned minutes are safely folded into the active automatic allowance using Apple’s latest five-minute usage checkpoint
- Shorter Today checkbox rows that keep full-size completion targets on one line
- A privacy-minimized iPhone Home Screen widget in large, medium, and small sizes, with safe checkbox actions and an app-name-free aggregate Earned Access balance
- A clearer native Setup area with separate cards for widgets, Health metrics, Earned Access, and Apple Watch
- An automatic daily Earned Access bank: selected completed routines add five-minute credits without a separate claim
- A configurable daily app-time ceiling, set to 60 minutes by default
- Reliable 15-minute allowance redemptions that count only actual foreground use in selected apps
- Calendar-day Earned Access safeguards: unused minutes expire at midnight and cannot bypass the next morning’s Truth Before Tasks gate
- The governing Truth Before Tasks reminder: “Not for righteousness. Because of righteousness.”

- A development-only Family Controls prototype with Apple’s private app and website picker
- Real Managed Settings shielding connected to routine and step-based Earned Access allowances
- Automatic on-device relocking when an earned allowance ends
- On-device storage of opaque Apple selection tokens; selected app names and browsing history are not exposed to Daily Routine
- One clean Daily Routine header without a repeated screen subtitle
- A native truth-reminder library for text and pictures, with selected or shuffled notifications and a configurable daily schedule
- Reviewable Apple Health sleep suggestions that save bedtime to the date it occurred and wake time to the following morning
- Phone-safe actual-time fields that keep the time and Now button from overlapping
- A physical-device-tested reward flow that locks selected apps, grants a timed allowance, and restores the shield automatically
- A calmer Setup landing page organized into Routine, Appearance, Faith, Health, and Data sections
- Compact wake, bedtime, schedule, and sleep-time controls that preserve phone space
- Morning and later routine selections that add configurable per-task credits to one daily bank
- Named multi-app reward groups, while automatic app selection and enforcement remain pending Apple Family Controls approval
- Apple Health source labels that can surface Apple Watch, Garmin Connect, and other apps contributing Health samples
- A Truth Before Tasks reminder to choose faithfulness over infallibility, trust over certainty, and the Lord over being right
- Truth Before Tasks daily opening before the rest of the routine unlocks
- A quieter morning opening that removes repeated subtitles, step headings, and conviction-introduction copy while preserving all editable truth, prayer, theme, conviction, and Scripture content
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

Data is stored locally first. If private sync is connected, routine definitions, daily entries, notes, memories, weekly reviews, and ordinary preferences are also stored in the owner's Supabase account row. If the owner separately enables private accountability, each active partner can read only that relationship’s filtered snapshot. Apple Health summaries, automatic Health-based step values, Earned Access baselines and progress, Screen Time authorization and opaque app-selection tokens, background photos, local snapshots, downloaded backups, and conflict archives remain device-only. Sleep suggestions become ordinary routine history only after the user applies them. Clearing browser storage can erase the local copy, so use Download backup periodically.

- [Privacy Policy](privacy.html)
- [Support](support.html)

## Private sync and accountability

The current manual report intentionally shares only after the user previews and chooses a destination. Private sync uses:

- Front end: this GitHub Pages PWA and its bundled iPhone web view
- Authentication + database: Supabase Auth and Postgres
- Row-level security: each owner can access only their own routine document; an active accountability partner can read only the filtered snapshot for that specific relationship
- Local-first behavior: offline changes remain pending until the server acknowledges a matching revision
- Privacy boundary: Health summaries, background photos, local backups, and conflict archives remain device-only

Run the sync foundation tests with:

```text
node tests/sync-core.test.js
node tests/sync-cloud.test.js
```

See `docs/PRIVATE_SYNC_FOUNDATION.md`, `docs/ACCOUNTABILITY_FOUNDATION.md`, and the files under `supabase/migrations/` for the design and database policies.

Do not publish personal routine/mood data directly into the GitHub repository or a public Google Sheet.
