# Daily Routine

A mobile-first private routine and mood tracker designed to run as a Progressive Web App (PWA) on GitHub Pages.

## Version 1.8.4 features

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
- All data remains in this browser's local storage

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

This version has no account system and does not transmit routine, mood, or note data. Data is stored locally on the device/browser. Clearing browser storage can erase it, so use Download backup periodically.

## Recommended next phase: private accountability sharing

Add authenticated cloud sync so each app user can authorize one accountability viewer. A good architecture is:

- Front end: this GitHub Pages PWA
- Authentication + database: Supabase
- Row-level security: each user's entries are readable only by that user and specifically approved viewer(s)
- Optional Google Sheets export: server-side sync to a private sheet for users who prefer spreadsheet review

Do not publish personal routine/mood data directly into the GitHub repository or a public Google Sheet.
