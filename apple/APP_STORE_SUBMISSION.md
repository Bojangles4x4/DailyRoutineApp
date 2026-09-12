# App Store submission package

This document records the planned TestFlight submission behavior for Daily Routine 1.16.0 (build 14). Family Controls distribution remains blocked until Apple assigns the required entitlement.

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
- Earned Access step rounds that count movement after a personal app limit is reached
- Manual accountability reports with exact previews and category-level privacy controls
- Local-first storage with manual backup and export

Daily Routine contains no ads, analytics, or account requirement. Your routine content remains on your devices unless you choose to export it.

Daily Routine is a personal organization tool and does not provide medical advice, diagnosis, or treatment.

### Keywords

`routine,habits,planner,journal,prayer,reflection,checklist,wellness,private,watch`

### Version 1.16.0 draft release notes

- Privately choose apps, categories, or websites through Apple's Screen Time picker and connect them to routine and step-based allowances.
- Create an on-device library of truth reminders using text or pictures, then select entries or shuffle the library on a daily schedule.
- Review Apple Health sleep suggestions before saving bedtime to the date it occurred and wake time to the following morning.
- Keep actual-time fields and their Now buttons separated on iPhone.
- Use a single compact Daily Routine header without a repeated Setup label.
- Unlock selected apps during an earned allowance and restore the shield automatically when the allowance ends.
- Navigate with a compact Daily Routine header and a focused Setup page organized by category.
- Use smaller wake, bedtime, schedule, and sleep-time controls that leave more room for the information that matters.
- Earn separate morning and later app-time allowances after completing selected routines, with an optional step-based allowance too.
- Name several apps in an Earned Access group and choose different reward minutes for each routine stage.
- See whether Apple Watch, Garmin Connect, or another source contributed recent data through Apple Health.
- Begin with a new Truth Before Tasks reminder: faithfulness rather than infallibility, trust rather than certainty, and the Lord rather than being right.
- Start an Earned Access round when a Screen Time limit is reached, then use Apple Health to count only the additional steps walked and show when extra time has been earned.
- Choose a fixed step requirement or an optional 750 → 1,000 → 1,500 escalating pattern, and customize the app label and reward minutes.
- Use more of the Apple Watch display: the progress summary now stays clear of the system clock, routine choices have larger finger-friendly targets, and the compact bottom actions sit closer to the screen edge to reveal more of the routine list.
- Choose the exact checkbox or medication routine to complete or reopen from Apple Watch instead of relying on a guessed next action. Medication entries receive the same AM/PM safeguard on Watch.
- Customize the left bottom Watch shortcut from iPhone Setup, with Water +1 as the default.
- Dictate a general note, prayer, or action item from Apple Watch and find it in Notes with Apple Watch as its source.
- Begin each day with Truth Before Tasks and, when configured, two more minutes of personal convictions with optional supporting Scripture.
- Keep primary navigation visible while scrolling.
- Keep medication and schedule time controls compact and contained on iPhone.
- Get a gentle confirmation when logging morning medicine in the evening or evening medicine in the morning.
- Use Notes & Thoughts, Review & Reflect, and Apple Watch progress from one private routine home.
- Preview and manually share a daily or weekly accountability report with sensitive categories off by default.
- Optionally add an automatic Apple Health steps goal and review sleep-derived bedtime and wake suggestions with separate calendar dates.
- Create fully open-ended Truth Before Tasks themes using only a title, body, and Scripture.
- Use owner-only Private sync while Health summaries and automatic step values remain device-only.

## App Privacy answers

Before a public App Store submission, update the App Privacy questionnaire for the optional Private sync implementation. When Private sync is enabled, the sign-in email address and synchronized user content are transmitted to the owner-only Supabase account row. Disclose the applicable contact-information and user-content categories as linked to the user, not used for tracking, and used only for app functionality.

The following remains true for the planned build 14:

- No analytics, advertising, tracking, or third-party SDKs
- Routine, reflection, medication, prayer, and note data is local-first and is transmitted only when the owner connects Private sync
- Apple Health data is read only after user authorization, summarized on device, and not transmitted off device
- Earned Access baselines, progress, and earned-time state remain on the device and are excluded from Private sync
- Family Controls authorization, opaque selection tokens, and Managed Settings shield state remain on the device and are excluded from Private sync
- Watch routine snapshots remain within the iPhone/Watch apps and their shared App Group
- Backup and export files leave the app only through an explicit user action
- Accountability reports remain on device until the user previews and explicitly copies or shares them to a chosen destination
- Truth-reminder text and pictures stay in the native app’s private local storage and are used only for local notifications

Revisit these answers before submission if networking, cloud sync, crash reporting, analytics, or another SDK is added.

## HealthKit disclosure

- Requested read types: step count, sleep analysis, and workouts
- Share/write types: none
- User benefit: show a small on-device daily summary, offer reviewable sleep-time suggestions, automatically update an optional step-goal routine item, and measure additional steps during a user-started Earned Access round
- Not used for advertising, marketing, profiling, or data mining
- Not stored in iCloud or included in Watch complication data
- Included in a manual accountability report only after the user enables the separate Health switch and reviews the exact text
- Automatic Health-based step values and Earned Access state are excluded from Private sync; sleep suggestions enter routine history only after the user confirms selected times and dates

## TestFlight “What to Test”

Please test the first-run flow and verify that existing routine data remains intact.

1. Complete Truth Before Tasks and a configured Convictions Before Circumstances phase, then confirm the main app and Watch quick actions unlock.
2. Create and complete routine items, notes, and a Review & Reflect session.
3. Change a medication time between AM and PM and verify the in-app warning works without a crash or overlapping fields.
4. Create, edit, and delete an open-ended Truth Before Tasks theme using a title, body, and one to three Scripture or plain-text truth lines.
5. Connect Apple Health, add an 8,000-step routine goal, refresh Health, and verify the item completes automatically at the target.
6. In Setup → Health & Watch, select morning and later routine requirements and verify each allowance becomes available only after every selected task is complete. Also start an optional movement round and confirm progress begins at zero rather than using the day's total steps.
7. Turn on Screen Time protection, choose a nonessential test app, use an earned allowance, and confirm the app unlocks only until the displayed end time and then shields itself again.
8. Review a Health sleep suggestion and confirm bedtime is saved to the date it occurred while wake time is saved to the following morning. Confirm existing entries are not selected for replacement automatically.
9. Confirm automatic Health step values and Earned Access progress do not appear on a second device through Private sync.
10. Verify iPhone/Watch progress sync and complication updates. Tap a specific routine, reopen it, change the bottom shortcut in iPhone Setup, and dictate each Capture type.
11. Download a JSON backup and restore it after making a temporary change.
12. In Setup → Faith foundation → Truth reminders, add text and a picture, choose selected entries and shuffle mode in separate tests, and verify the configured local notifications appear.
13. Create daily and weekly accountability reports, verify sensitive switches are off by default, and confirm the copied/shared text exactly matches the preview.

Do not use real sensitive notes or medication details in a public bug report.

## App Review notes

Daily Routine is local-first; its optional Private sync account is not required for the main routine experience. The main experience is bundled for offline use inside a native SwiftUI/WKWebView shell. Native functionality includes optional read-only HealthKit summaries and routine assistance, local truth reminders chosen and scheduled by the user, a user-initiated Share sheet for previewed accountability report text, Watch Connectivity quick actions, a watchOS companion, and WidgetKit complications.

Health access is requested only from Setup after the reviewer taps Connect Health. The app requests read access for steps, sleep, and workouts and does not write HealthKit data.

Earned Access uses individual Family Controls authorization, Apple's private app and website picker, Managed Settings shielding, and a Device Activity monitor extension. Daily Routine stores only Apple's opaque selection tokens and does not receive selected app names or browsing history. A person turns protection on, earns an allowance through configured routine or step requirements, and explicitly starts it; selected apps unlock until the displayed end time and shield themselves again automatically. The full cycle has passed physical-iPhone testing. Do not distribute this Family Controls build through TestFlight until Apple assigns the distribution entitlement to the app and Device Activity extension.

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
- [x] Physical iPhone Earned Access lock, allowance, and automatic re-lock test passes
- [ ] Family Controls distribution entitlement is approved for the app and Device Activity extension
- [ ] Signed archive validates without warnings
- [ ] Export-compliance questions are answered for the final binary
- [ ] TestFlight internal testing succeeds before external testing or App Review
