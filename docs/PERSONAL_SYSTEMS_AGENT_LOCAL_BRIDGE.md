# Personal Systems Agent local bridge

Brave intentionally disables the browser File System Access API. The local bridge gives Daily Routine a narrow alternative without reading the Brave profile or repeatedly downloading backups.

## Boundary

- Listens only on `127.0.0.1:48765`.
- Accepts snapshot writes only when the browser `Origin` is `https://bojangles4x4.github.io` (plus localhost for development).
- Requires the privacy-minimized snapshot schema: routine definitions and daily history only.
- Rejects payloads larger than 5 MB and non-JSON data.
- Atomically writes one mode-`0600` file at `~/Library/Application Support/Daily Routine Agent/daily-routine-agent-live.json`.
- Does not read browser storage, browsing history, notes, memories, backgrounds, Messages, or any unrelated file.

The launch agent source is `tools/daily-routine-agent-bridge.py`; its launchd definition is `tools/com.bojangles4x4.DailyRoutine.agent-bridge.plist`.

Daily Routine enables ongoing writes only after the user chooses **Connect Personal Systems Agent**. If the bridge is stopped, the app reports that it is unavailable and keeps normal Daily Routine saving unaffected.
