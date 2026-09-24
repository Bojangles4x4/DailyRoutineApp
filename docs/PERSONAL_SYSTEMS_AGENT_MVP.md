# Personal Systems Agent MVP

Daily Routine now includes a native macOS companion target named **Daily Routine Agent**. The existing iPhone, Watch, widgets, PWA, private sync, and Earned Access code paths are unchanged.

## Why this is a companion target

The existing product is an iPhone `WKWebView` wrapper around the offline PWA, plus Watch and widget extensions. Apple Messages and Mac foreground-app activity are Mac-local sources that an iPhone target cannot read. Keeping the collector in the same Xcode project provides a clean product boundary without pretending the iPhone process can cross it.

The MVP keeps the recommendation inbox in the Mac companion, beside the data that produced it. A later bridge can publish only approved derived observations or recommendations to Daily Routine private sync. Raw Messages, calendar details, and activity events must not cross that bridge by default.

## Vertical slice

```text
Opt-in local collectors
        ↓
Normalized AgentEvent records
        ↓
Local SQLite database
        ↓ every ~3 hours
Rule-based observation pass (quiet)
        ↓ every ~72 hours
Top 1–3 structured recommendations
        ↓
Native recommendation inbox + diagnostics
```

Every event contains a timestamp, source, category, title, summary, metadata, and sensitivity level. SQLite also stores source health, observation evidence, recommendation state, and job history.

## Sources in this milestone

- **Apple Messages:** opt-in through a separate app target named **Daily Routine Messages Importer**. Only this narrowly scoped helper should receive Full Disk Access. It opens `~/Library/Messages/chat.db` with SQLite read-only mode, replaces one owner-only local snapshot, and contains no network client. The main Agent imports that snapshot without Full Disk Access. Ordinary text rows from the last 14 days are included; attachments and some newer rich/attributed bodies are skipped.
- **App activity:** opt-in, prospective foreground-application switches from `NSWorkspace`. It does not read browser URLs, browsing history, window titles, keystrokes, screen contents, or Apple's private Screen Time database.
- **Calendar:** opt-in EventKit full read access. The app fetches event titles/times for the analysis window and never writes calendar data.
- **Daily Routine:** a one-time, single-file connection from the web app writes a privacy-limited local JSON snapshot containing only routine definitions and daily completion history. The Mac agent reads that file without modifying it or uploading it. Manual backup import remains available as a fallback.
- **Test mode:** generates a small synthetic set of routine misses, follow-up messages, and repeated app revisits, then runs the full pipeline. Diagnostics can remove the synthetic events and their derived recommendations before real sources are connected.

Gmail, GitHub, Drive, Health, Finances, Teams/SharePoint, Notes, Reminders, browser URLs, and a cloud model are intentionally outside this milestone.

## Local analysis

The initial deterministic engine detects:

- repeated app/project revisits;
- repeated app-to-app workflows;
- routines missed on multiple recorded days;
- follow-up language recurring in Messages; and
- overlap between meeting-heavy days and missed routines.

The 72-hour pass selects at most three recommendations and always fills these fields:

1. Pattern noticed
2. Evidence
3. Recommended change
4. Where it belongs
5. Expected benefit

No network client is linked into the target. A future model adapter should accept only derived observations by default, enforce sensitivity policy, and require a separately enabled setting.

## Recommendation actions

`Ignore`, `Not useful`, and `Watch longer` update local recommendation state now. `Add to routine`, `Change reminder`, `Create project`, and `Create automation` are real modeled actions but are staged only. They do not mutate the PWA, send messages, edit Calendar, or create anything externally.

## Build and try it

1. Install XcodeGen if needed.
2. From `apple/`, run `xcodegen generate`.
3. Open `DailyRoutineApple.xcodeproj`.
4. Select the **DailyRoutineAgent** scheme and **My Mac**.
5. Run the app.
6. Open **Diagnostics** and choose **Load test data and run pipeline** before granting any permissions.
7. After reviewing the sample inbox, choose **Clear synthetic events** before connecting real sources.

The local database lives at:

```text
~/Library/Application Support/Daily Routine Agent/personal-systems.sqlite
```

Use **Reveal local database** in Diagnostics to open its folder.

## Permissions

### Apple Messages

1. Build and run **Daily Routine Messages Importer** once.
2. Open **System Settings → Privacy & Security → Full Disk Access**.
3. Add/enable **Daily Routine Messages Importer** only. Do not grant Full Disk Access to **Daily Routine Agent**.
4. Quit and reopen the importer, then choose **Import now**.
5. In Daily Routine Agent Diagnostics, enable Messages and run collection.

The importer and main Agent have separate bundle identifiers and signatures. The importer hard-codes one read-only source path, excludes attachments, caps contact labels at 200 characters and message bodies at 500 characters, and atomically replaces:

```text
~/Library/Application Support/Daily Routine Messages Importer/messages-import-v1.json
```

The output directory is mode `0700` and the snapshot is mode `0600`. The helper target contains no networking code or framework dependency and never sends, edits, or deletes a message. It is intentionally not App Sandbox-enabled because a sandboxed process cannot read the user-approved Messages database path; Hardened Runtime remains enabled. The main Agent no longer opens `chat.db` directly and does not need Full Disk Access.

### Calendar

Choose **Connect calendar** in Diagnostics and approve the macOS prompt. Revoke access at any time in **System Settings → Privacy & Security → Calendars**.

### App activity

No special macOS permission is needed for foreground application activation notifications. The source remains off until its toggle is enabled.

### Daily Routine history

1. In Daily Routine, open **Setup → Data → Backup & export**.
2. Choose **Connect Personal Systems Agent** and save the suggested `daily-routine-agent-live.json` file somewhere permanent on this Mac.
3. In the Mac agent, open **Diagnostics**, choose **Daily Routine snapshot**, and select that same file once.

After that, Daily Routine rewrites only that approved file whenever routine state changes, and the Mac agent rereads it during its collection pass (target: every three hours). The browser cannot browse other files through this connection. Notes, memories, backgrounds, and browser activity are excluded from the snapshot. If browser/site data is reset or the browser revokes the saved file permission, Daily Routine will show **Reconnect**; choose the same file again. A downloaded full backup remains the manual fallback.

### Background operation

The menu-bar app uses `NSBackgroundActivityScheduler` to check whether jobs are due. Enable **Launch at login** in Diagnostics to keep it available after signing in. macOS may coalesce background timing, so three hours and 72 hours are target intervals rather than exact wall-clock guarantees.

## Validation

Run:

```text
xcodebuild -project DailyRoutineApple.xcodeproj \
  -scheme DailyRoutineAgent \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO test
```

The tests cover SQLite event round-tripping and deduplication, the synthetic end-to-end event → observation → recommendation slice, the three-recommendation cap, and staged action persistence.

## Phase 2

- Define an encrypted, derived-only recommendation bridge into the iPhone/PWA inbox, with per-item approval and no raw-event sync.
- Package and notarize the Agent and Messages Importer with stable Developer ID signatures so privacy grants survive normal upgrades.
- Add an optional file watcher for faster ingestion than the scheduled three-hour reread.
- Add optional Notes/Reminders and browser-history adapters with separate permissions and clear browser-specific support.
- Improve Messages parsing for attributed bodies and attachment-only messages without weakening read-only behavior.
- Add semantic clustering/model-assisted analysis behind an explicit opt-in, redaction preview, sensitivity gate, and local-only fallback.
- Make action adapters apply approved routine/reminder/project/automation changes and record an audit trail.
- Add retention controls, source-specific deletion, database encryption/key handling, and export/redaction tools.
- Evaluate a signed launch helper or packaged installer for a polished always-on distribution.
