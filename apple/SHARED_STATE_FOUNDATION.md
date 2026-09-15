# Shared-state foundation

Status: first safe implementation slice complete and now used by one limited iPhone Home Screen widget prototype. The foundation does not yet add a general Shortcut, NFC automation, Siri action, or independent native routine writer.

## Authority and boundaries

The bundled web app and its existing optional Private sync document remain authoritative for routine data. The shared native store is a device-local coordination layer, not another routine database.

The App Group’s `Library/Application Support/DailyRoutineSharedState` directory contains two bounded JSON files:

- `routine-shared-snapshot-v1.json`: a privacy-minimized view of the current local day.
- `routine-command-journal-v1.json`: pending and resolved native command envelopes.

Neither file is uploaded by Private sync or included in routine backups. The existing HealthKit, Screen Time, Earned Access, and Watch privacy rules remain unchanged.

## Snapshot contract

`RoutineSharedSnapshot` is versioned and includes:

- monotonically increasing local state revision;
- local calendar date and time-zone identifier;
- Morning Foundation completion status;
- routine completion totals;
- the next eligible non-sensitive checkbox;
- at most 24 eligible non-sensitive checkboxes;
- last update time.

The snapshot excludes notes, prayers, Scripture, medications, Health labels/data, Screen Time selections, Earned Access state, and the full routine database. Prayer, Scripture, medication, and Health-labeled checkbox routines are filtered even if their underlying input type would otherwise be eligible.

Every ordinary web-state save increments the device-local shared revision and publishes a new snapshot through the narrow native bridge. Foundation lock/unlock and Watch-context changes also republish so native surfaces do not retain a stale gate state.

## Command contract

`RoutineSharedCommand` is versioned and carries:

- a stable unique command ID;
- a stable semantic action ID;
- origin, creation time, local date, and time zone;
- target ID and tightly bounded string payload;
- expected snapshot revision;
- an explicit Morning Foundation requirement.

The native journal rejects malformed commands before persisting them. Enqueuing the same command ID again returns its existing record rather than creating a duplicate. Resolution is also one-way: a resolved command cannot later be replaced with a different result.

### Currently supported action

`routine.checkbox.set` sets one eligible checkbox to the requested final state (`completed=true` or `completed=false`). It is deliberately a set operation, not a toggle, so replay cannot accidentally reverse the first result.

Before applying it, the web reconciler verifies:

1. schema and action ID;
2. today’s local date;
3. current time-zone identifier;
4. exact expected revision;
5. completion of the Morning Foundation in both stored state and the active UI gate;
6. that the target is scheduled today, is a routine checkbox, is not skipped, and is not sensitive by default.

Unsupported, stale, wrong-day, wrong-time-zone, locked, skipped, missing, and sensitive targets are rejected without changing routine data.

Medication, note capture, Health writes, foundation completion, and Earned Access changes are not supported commands.

## Reconciliation sequence

```text
future widget / App Intent / Shortcut
              |
       enqueue one command
              v
 App Group command journal (pending)
              |
   app/web bridge requests pending work
              v
 current web authority revalidates command
        |                     |
      apply                 reject
        |                     |
 save routine + revision      |
        \                     /
         persist result locally
                  |
       acknowledge native journal
                  |
       publish refreshed snapshot
```

The web app keeps a bounded device-local result ledger. If the native bridge retries a command after the routine save, the stored result is acknowledged again without applying the action again.

## Atomicity and coordination

The Swift store uses coordinated App Group file access and atomic file replacement. A process-local lock also prevents overlapping operations through the same store instance. Journal retention is bounded to 200 records while preserving pending work.

This first slice intentionally leaves routine mutation in the current web authority. A later prototype may extract one native mutation only after its conflict, migration, and rollback behavior is proven equivalent.

## Failure and fallback behavior

- If App Group storage is unavailable, the bridge reports an error and the current app continues normally.
- If a snapshot is missing or invalid, future surfaces must show “Open Daily Routine to refresh” rather than infer state.
- If a command is stale or incompatible, it is rejected; future surfaces should open the relevant app screen for review.
- If the app is terminated before reconciliation, the pending command remains in the journal.
- If acknowledgement is retried, the first resolved result wins.
- Disabling future native actions leaves the existing web app, Watch flow, and Private sync data unchanged.

No command may complete or bypass the three-minute Truth Before Tasks meditation. Watch remains locked until the phone records the full configured Morning Foundation for the current local day.

## Verification

The native unit suite covers:

- snapshot round-trip and sensitive-category absence;
- duplicate enqueue and one-way resolution;
- journal persistence across store instances;
- required revision and gate metadata;
- invalid snapshot rejection.

The browser regression suite covers:

- rejection while the Morning Foundation is locked;
- successful application after foundation completion;
- safe duplicate delivery;
- stale-revision rejection;
- wrong-local-day and changed-time-zone rejection;
- no mutation from rejected commands;
- revision increase and refreshed snapshot publication;
- medication exclusion from eligible items;
- all existing web UI regressions.

Physical-iPhone validation also passed on Taylor's iPhone:

- the privacy-minimized snapshot survived app termination and a clean relaunch;
- the App Group snapshot contained the correct local day, time zone, foundation state, and completion totals;
- the snapshot contained no prayer, Scripture, medication, or Health labels;
- a queued `routine.checkbox.set` command survived termination, was reconciled after a clean relaunch, and was acknowledged as applied;
- the physical command set an already-completed item to its existing final state, confirming the full command lifecycle without changing visible routine completion data.

## Next implementation gate

Before expanding an iPhone widget or NFC/App Intent surface beyond the first queue-and-open prototype:

1. test midnight and time-zone-change rejection on device;
2. retain queue-and-open fallback for the first user-facing prototype;
3. keep the first prototype limited to one reversible checkbox command;
4. verify stale-state messaging and privacy redaction on the physical widget.

The physical lifecycle, App Group inspection, and no-op command-path checks now permit one small interactive iPhone widget prototype to enqueue `routine.checkbox.set`. Broader routine types remain out of scope until separately designed and tested.
