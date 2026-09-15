# iPhone Home Screen widget

Status: first interactive prototype implemented for the Build 16 candidate. Simulator compilation and the native unit suite pass. Signed provisioning and physical-widget validation remain.

## Supported sizes

The installed Xcode 26.6 / iPhoneOS 26.5 SDK and Apple WidgetKit documentation confirm that `.systemLarge` is the largest Home Screen widget family available on iPhone. The widget therefore supports:

- large: foundation status, progress, up to four eligible routine actions, and an app link;
- medium: foundation status, progress, and the first eligible routine action;
- small: foundation status and progress, with a link into the app.

There is no full-screen iPhone WidgetKit family in the verified SDK. `.systemExtraLarge` is for iPadOS and macOS. The large iPhone widget is the supported fallback closest to the requested full-screen command center.

## Privacy and gating

- The widget reads only `RoutineSharedSnapshot`; it never reads the full routine database.
- Prayer, Scripture, medication, Health, notes, Screen Time selections, and Earned Access data are excluded from the snapshot.
- Routine item labels are marked privacy-sensitive so the system can redact them while locked.
- When the Morning Foundation is incomplete, the widget exposes only a link to begin on iPhone.
- Missing, wrong-day, or wrong-time-zone snapshots show “Open Daily Routine to refresh.”

## Interaction contract

The only interactive mutation is completing an eligible unchecked checkbox. A tap:

1. enqueues one versioned `routine.checkbox.set` command with the snapshot revision, local day, and time zone;
2. opens Daily Routine;
3. lets the existing web authority revalidate and apply or reject the command;
4. records the result in the bounded App Group journal;
5. publishes a refreshed snapshot.

The widget cannot complete Truth Before Tasks or Convictions, update medication, consume Earned Access, or write Health data. Repeated delivery is safe because the command sets a final value rather than toggling it.

## Remaining physical checks

1. Sign the new `com.bojangles4x4.DailyRoutine.widgets` extension with Taylor's Apple developer account.
2. Install the development build on the connected iPhone.
3. Add the large “Today’s Rhythm” widget to the Home Screen.
4. Verify locked-foundation behavior, privacy redaction, and the stale-snapshot fallback.
5. Complete one ordinary checkbox from the widget and confirm exactly one completion in the app.
6. Repeat around midnight or after a test time-zone change before expanding native actions.
