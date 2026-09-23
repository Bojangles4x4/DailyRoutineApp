#!/usr/bin/python3
"""Local-only bridge from Daily Routine in Brave to the macOS Agent snapshot."""

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import json
import os
import tempfile


HOST = "127.0.0.1"
PORT = 48765
MAX_BODY_BYTES = 5 * 1024 * 1024
ALLOWED_ORIGINS = {
    "https://bojangles4x4.github.io",
    "http://127.0.0.1:9878",
}
AGENT_DIRECTORY = Path.home() / "Library" / "Application Support" / "Daily Routine Agent"
SNAPSHOT_PATH = AGENT_DIRECTORY / "daily-routine-agent-live.json"


class SnapshotHandler(BaseHTTPRequestHandler):
    server_version = "DailyRoutineAgentBridge/1"

    def log_message(self, _format, *_args):
        return

    def allowed_origin(self):
        origin = self.headers.get("Origin", "")
        return origin if origin in ALLOWED_ORIGINS else None

    def send_common_headers(self, origin):
        if origin:
            self.send_header("Access-Control-Allow-Origin", origin)
            self.send_header("Vary", "Origin")
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")

    def send_json(self, status, payload, origin=None):
        body = json.dumps(payload, separators=(",", ":")).encode("utf-8")
        self.send_response(status)
        self.send_common_headers(origin)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self):
        origin = self.allowed_origin()
        if self.path != "/v1/snapshot" or not origin:
            self.send_json(403, {"ok": False, "error": "origin_not_allowed"})
            return
        self.send_response(204)
        self.send_common_headers(origin)
        self.send_header("Access-Control-Allow-Methods", "POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.send_header("Access-Control-Allow-Private-Network", "true")
        self.send_header("Access-Control-Max-Age", "600")
        self.end_headers()

    def do_GET(self):
        origin = self.allowed_origin()
        if self.path != "/v1/status":
            self.send_json(404, {"ok": False, "error": "not_found"}, origin)
            return
        self.send_json(200, {"ok": True, "destination": SNAPSHOT_PATH.name}, origin)

    def do_POST(self):
        origin = self.allowed_origin()
        if self.path != "/v1/snapshot":
            self.send_json(404, {"ok": False, "error": "not_found"}, origin)
            return
        if not origin:
            self.send_json(403, {"ok": False, "error": "origin_not_allowed"})
            return
        if not self.headers.get("Content-Type", "").lower().startswith("application/json"):
            self.send_json(415, {"ok": False, "error": "json_required"}, origin)
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            length = 0
        if length <= 0 or length > MAX_BODY_BYTES:
            self.send_json(413, {"ok": False, "error": "invalid_size"}, origin)
            return
        try:
            payload = json.loads(self.rfile.read(length))
        except (json.JSONDecodeError, UnicodeDecodeError):
            self.send_json(400, {"ok": False, "error": "invalid_json"}, origin)
            return
        state = payload.get("state") if isinstance(payload, dict) else None
        if (
            not isinstance(state, dict)
            or not isinstance(state.get("items"), list)
            or not isinstance(state.get("days"), dict)
            or payload.get("scope") != "routine-definitions-and-daily-history"
        ):
            self.send_json(422, {"ok": False, "error": "invalid_snapshot"}, origin)
            return

        AGENT_DIRECTORY.mkdir(mode=0o700, parents=True, exist_ok=True)
        os.chmod(AGENT_DIRECTORY, 0o700)
        temporary_path = None
        try:
            with tempfile.NamedTemporaryFile(
                mode="w",
                encoding="utf-8",
                dir=AGENT_DIRECTORY,
                prefix=".daily-routine-agent-",
                suffix=".json",
                delete=False,
            ) as temporary:
                temporary_path = Path(temporary.name)
                json.dump(payload, temporary, ensure_ascii=False, separators=(",", ":"))
                temporary.flush()
                os.fsync(temporary.fileno())
            os.chmod(temporary_path, 0o600)
            os.replace(temporary_path, SNAPSHOT_PATH)
        finally:
            if temporary_path and temporary_path.exists():
                temporary_path.unlink()

        self.send_json(200, {"ok": True, "destination": SNAPSHOT_PATH.name}, origin)


if __name__ == "__main__":
    ThreadingHTTPServer((HOST, PORT), SnapshotHandler).serve_forever(poll_interval=0.5)
