# App Store submission package

This document keeps the TestFlight submission consistent with the behavior of Daily Routine 1.12.0 (build 8).

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
- Truth Before Tasks daily opening with an optional Convictions Before Circumstances phase
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

### Version 1.12.0 release notes

- Use more of the Apple Watch display: the compact progress summary now shares the open side of the clock band, leaving more room for routine choices.
- Choose the exact checkbox or medication routine to complete or reopen from Apple Watch instead of relying on a guessed next action. Medication entries receive the same AM/PM safeguard on Watch.
- Customize the left bottom Watch shortcut from iPhone Setup, with Water +1 as the default.
- Dictate a general note, prayer, or action item from Apple Watch and find it in Notes with Apple Watch as its source.
- Begin each day with Truth Before Tasks and, when configured, two more minutes of personal convictions with optional supporting Scripture.
- Keep primary navigation visible while scrolling.
- Keep medication and schedule time controls compact and contained on iPhone.
- Get a gentle confirmation when logging morning medicine in the evening or evening medicine in the morning.
- Use Notes & Thoughts, Review & Reflect, and Apple Watch progress from one private routine home.
- Preview and manually share a daily or weekly accountability report with sensitive categories off by default.
- Optionally add an automatic Apple Health steps goal and review sleep-derived bedtime/wake suggestions before applying them to the wake-up day.
- Create fully open-ended Truth Before Tasks themes using only a title, body, and Scripture.
- Use owner-only Private sync while Health summaries and automatic step values remain device-only.

## App Privacy answers

Before a public App Store submission, update the App Privacy questionnaire for the optional Private sync implementation. When Private sync is enabled, the sign-in email address and synchronized user content are transmitted to the owner-only Supabase account row. Disclose the applicable contact-information and user-content categories as linked to the user, not used for tracking, and used only for app functionality.

The following remains true for build 8:

- No analytics, advertising, tracking, or third-party SDKs
- Routine, reflection, medication, prayer, and note data is local-first and is transmitted only when the owner connects Private sync
- Apple Health data is read only after user authorization, summarized on device, and not transmitted off device
- Watch routine snapshots remain within the iPhone/Watch apps and their shared App Group
- Backup and export files leave the app only through an explicit user action
- Accountability reports remain on device until the user previews and explicitly copies or shares them to a chosen destination

Revisit these answers before submission if networking, cloud sync, crash reporting, analytics, or another SDK is added.

## HealthKit disclosure

- Requested read types: step count, sleep analysis, and workouts
- Share/write types: none
- User benefit: show a small on-device daily summary, offer reviewable sleep-time suggestions, and automatically update an optional step-goal routine item
- Not used for advertising, marketing, profiling, or data mining
- Not stored in iCloud or included in Watch complication data
- Included in a manual accountability report only after the user enables the separate Health switch and reviews the exact text
- Automatic Health-based step values are excluded from Private sync; sleep suggestions enter routine history only after the user chooses Apply times

## TestFlight “What to Test”

Please test the first-run flow and verify that existing routine data remains intact.

1. Complete Truth Before Tasks and a configured Convictions Before Circumstances phase, then confirm the main app and Watch quick actions unlock.
2. Create and complete routine items, notes, and a Review & Reflect session.
3. Change a medication time between AM and PM and verify the in-app warning works without a crash or overlapping fields.
4. Create, edit, and delete an open-ended Truth Before Tasks theme using a title, body, and one to three Scripture or plain-text truth lines.
5. Connect Apple Health, add an 8,000-step routine goal, refresh Health, and verify the item completes automatically at the target.
6. Review a Health sleep suggestion and confirm Apply times fills only empty bedtime/wake fields on the day the person woke up.
7. Confirm automatic Health step values do not appear on a second device through Private sync.
8. Verify iPhone/Watch progress sync and complication updates. Tap a specific routine, reopen it, change the bottom shortcut in iPhone Setup, and dictate each Capture type.
9. Download a JSON backup and restore it after making a temporary change.
10. Create daily and weekly accountability reports, verify sensitive switches are off by default, and confirm the copied/shared text exactly matches the preview.

Do not use real sensitive notes or medication details in a public bug report.

## App Review notes

Daily Routine is local-first; its optional Private sync account is not required for the main routine experience. The main experience is bundled for offline use inside a native SwiftUI/WKWebView shell. Native functionality includes optional read-only HealthKit summaries and routine assistance, a user-initiated Share sheet for previewed accountability report text, Watch Connectivity quick actions, a watchOS companion, and WidgetKit complications.

Health access is requested only from Setup after the reviewer taps Connect Health. The app requests read access for steps, sleep, and workouts and does not write HealthKit data.

Watch actions remain locked until the reviewer completes the Morning Foundation opening on iPhone. A medication routine tapped on Watch records the current time; tapping the completed row again reopens it.

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
