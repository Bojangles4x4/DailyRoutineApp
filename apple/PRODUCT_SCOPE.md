# Apple app product scope

## Product principles carried forward

Recent Daily Routine work points to a clear native product direction:

- Keep capture fast, calm, and readable on a phone.
- Keep Save and primary actions reachable when the keyboard is visible.
- Prefer one clear resurfacing choice over overlapping scheduling controls.
- Set technical metadata such as note source automatically and keep it out of the main flow.
- Preserve Review & Reflect, Memory Bank, prayer, God Moments, medication timing, and flexible-day behavior.
- Keep the app private and local-first, with intentional backup and export.
- Treat Apple Watch as a quick-action surface, not a tiny copy of the entire phone app.

## Recommended delivery phases

### Phase 1 — Native shell and safe migration

- Make Truth Before Tasks the daily opening gate: a minimum three-minute, Scripture-centered meditation completed before the rest of the app unlocks.
- Remember completion for the local calendar day while keeping the practice rooted in grace rather than achievement.
- Bundle the current web experience inside the iPhone app for reliable offline use.
- Add an explicit import path for an existing Daily Routine JSON backup.
- Add a native bridge status screen so Health and Watch connections are understandable.
- Preserve the PWA until the native version has been tested with real data.

### Phase 2 — Read-only Health integration

- Request only the permissions the person chooses.
- Read today’s steps, recent sleep duration, and today’s workout count.
- Suggest routine updates but never silently complete or rewrite a person’s records.
- Do not write medication, mood, prayer, or inferred health claims to HealthKit.

### Phase 3 — Apple Watch quick actions

- Show today’s completion summary.
- Complete the next routine item.
- Add one water unit.
- Record a lightweight mood check-in.
- Queue actions when the phone is unavailable and reconcile them when it reconnects.

### Phase 4 — Native reminders and glanceable surfaces

- Local notifications for “Bring this back on.”
- Watch complication or Smart Stack widget for today’s progress.
- Background refresh that respects battery life and privacy.

## Decisions still needed before App Store submission

- Final app name and bundle identifier.
- Apple Developer team and App Store ownership.
- Which Health categories are truly useful after real-device testing.
- Whether cross-device sync should use CloudKit, an App Group, or remain manual backup only.
- Privacy policy and App Privacy answers.
