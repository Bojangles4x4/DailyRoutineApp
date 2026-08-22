# App Store submission package

This document keeps the first App Store and TestFlight submission consistent with the behavior of Daily Routine 1.10.0 (build 3).

## URLs

- Privacy policy: `https://bojangles4x4.github.io/DailyRoutineApp/privacy.html`
- Support: `https://bojangles4x4.github.io/DailyRoutineApp/support.html`
- Marketing site: `https://bojangles4x4.github.io/DailyRoutineApp/`

Verify all three public URLs after the release-readiness pull request is merged and GitHub Pages deploys it.

## Proposed listing

- Name: **Daily Routine** *(confirm availability in App Store Connect)*
- Subtitle: **Private routines, gently**
- Primary category: **Productivity**
- Secondary category: **Health & Fitness**

### Promotional text

Begin with truth, move through your routines, and preserve the notes and moments you want to remember.

### Description

Daily Routine is a calm, private place to begin deliberately and follow through gently.

Start with Truth Before Tasks, then organize morning, daytime, and evening routines around the life you actually live. Add check-ins, medication timing, notes, prayers, memories, and flexible-day adjustments without turning your worth into a score.

Use the Apple Watch companion for glanceable progress and a few intentional quick actions. Optionally connect Apple Health to see an on-device summary of steps, recent sleep, and today’s workouts alongside your routine.

Highlights:

- Custom routines and check-ins
- Truth Before Tasks daily opening
- Notes, prayers, action items, and God Moments
- Review & Reflect weekly dashboard
- Medication timing with morning/evening mismatch warnings
- Flexible sick, travel, vacation, and rest days
- Apple Watch progress, quick actions, and complications
- Optional, read-only Apple Health summaries
- Manual accountability reports with exact previews and category-level privacy controls
- Local-first storage with manual backup and export

Daily Routine contains no ads, analytics, or account requirement. Your routine content remains on your devices unless you choose to export it.

Daily Routine is a personal organization tool and does not provide medical advice, diagnosis, or treatment.

### Keywords

`routine,habits,planner,journal,prayer,reflection,checklist,wellness,private,watch`

### Version 1.10.0 release notes

- Begin each day with Truth Before Tasks.
- Keep primary navigation visible while scrolling.
- Get a gentle confirmation when logging morning medicine in the evening or evening medicine in the morning.
- Use Notes & Thoughts, Review & Reflect, and Apple Watch progress from one private routine home.
- Preview and manually share a daily or weekly accountability report with sensitive categories off by default.

## App Privacy answers

Select **No, we do not collect data from this app** while the implementation remains as audited for 1.10.0:

- No developer-operated server or account system
- No analytics, advertising, tracking, or third-party SDKs
- Routine, reflection, medication, prayer, and note data stays in on-device app storage
- Apple Health data is read only after user authorization, summarized on device, and not transmitted off device
- Watch routine snapshots remain within the iPhone/Watch apps and their shared App Group
- Backup and export files leave the app only through an explicit user action
- Accountability reports remain on device until the user previews and explicitly copies or shares them to a chosen destination

Revisit these answers before submission if networking, cloud sync, crash reporting, analytics, or another SDK is added.

## HealthKit disclosure

- Requested read types: step count, sleep analysis, and workouts
- Share/write types: none
- User benefit: show a small on-device daily summary alongside the user’s routine
- Not used for advertising, marketing, profiling, or data mining
- Not stored in iCloud or included in Watch complication data
- Included in a manual accountability report only after the user enables the separate Health switch and reviews the exact text

## TestFlight “What to Test”

Please test the first-run flow and verify that existing routine data remains intact.

1. Complete Truth Before Tasks and confirm the main app and Watch quick actions unlock.
2. Create and complete routine items, notes, and a Review & Reflect session.
3. Log a medication at a mismatched time of day and verify the confirmation prompt.
4. Connect Apple Health, approve selected read permissions, and refresh the summary.
5. Verify iPhone/Watch progress sync and complication updates.
6. Download a JSON backup and restore it after making a temporary change.
7. Create daily and weekly accountability reports, verify sensitive switches are off by default, and confirm the copied/shared text exactly matches the preview.

Do not use real sensitive notes or medication details in a public bug report.

## App Review notes

Daily Routine is local-first and does not require an account. The main experience is bundled for offline use inside a native SwiftUI/WKWebView shell. Native functionality includes optional read-only HealthKit summaries, a user-initiated Share sheet for previewed accountability report text, Watch Connectivity quick actions, a watchOS companion, and WidgetKit complications.

Health access is requested only from Setup after the reviewer taps Connect Health. The app requests read access for steps, sleep, and workouts and does not write HealthKit data.

Watch actions remain locked until the reviewer completes the Truth Before Tasks opening on iPhone. Medication entries cannot be completed from Watch.

## Final submission checklist

- [ ] Apple Developer membership is active in Xcode
- [ ] Final app name is available
- [ ] App record exists for `com.bojangles4x4.DailyRoutine`
- [ ] Watch and widget identifiers are registered
- [ ] App Group `group.com.bojangles4x4.DailyRoutine` is assigned to Watch and widget identifiers
- [x] Privacy and support URLs are public
- [ ] App Privacy answers match this audited build
- [x] Screenshots show real app UI with fictional, non-sensitive example data (see [AppStoreAssets](AppStoreAssets/README.md))
- [ ] Physical iPhone HealthKit authorization test passes
- [ ] Physical iPhone/Apple Watch sync and complication refresh tests pass
- [ ] Signed archive validates without warnings
- [ ] Export-compliance questions are answered for the final binary
- [ ] TestFlight internal testing succeeds before external testing or App Review
