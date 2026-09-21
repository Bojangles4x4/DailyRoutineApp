# iPhone Home Screen widget

Status: the widget was signed, installed through TestFlight Build 18, and confirmed to receive its private snapshot on a physical iPhone. Build 20 physical testing confirmed widget refresh and ordinary checkbox completion. Build 21 adds a privacy-safe visible sync timestamp to the Earned Access reliability status. Build 22 keeps the widget’s aggregate earned-time figure aligned with the combined automatic allowance; locked-state redaction and midnight rollover remain focused regression checks.

## Supported sizes

The installed Xcode 26.6 / iPhoneOS 26.5 SDK and Apple WidgetKit documentation confirm that `.systemLarge` is the largest Home Screen widget family available on iPhone. The widget therefore supports:

- large: explicit Truth Before Tasks and Convictions status, progress, aggregate Earned Access time, up to three eligible routine actions, freshness time, and an app link;
- medium: foundation status, progress, and the first eligible routine action;
- small: foundation status and progress, with a link into the app.

There is no full-screen iPhone WidgetKit family in the verified SDK. `.systemExtraLarge` is for iPadOS and macOS. The large iPhone widget is the supported fallback closest to the requested full-screen command center.

## Privacy and gating

- The widget reads only `RoutineSharedSnapshot`; it never reads the full routine database.
- Prayer, Scripture, medication, Health, notes, Screen Time selections, selected-app identities, and selection tokens are excluded from the snapshot.
- The only Earned Access values included are the aggregate minutes remaining and daily ceiling. No app or website names are shared with the widget.
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

1. Verify locked-foundation behavior, privacy redaction, and the stale-snapshot fallback.
2. Earn and use selected-app time, then confirm the widget shows the latest aggregate five-minute-checkpoint balance without showing app identities.
3. Repeat around midnight or after a test time-zone change before expanding native actions.
