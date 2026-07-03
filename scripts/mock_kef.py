#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Carlos B and kefbar contributors
#
# This file is part of kefbar.
"""Mock KEF W2 speaker for dev/CI without hardware (SPEC §15).

Implements the getData/setData contract with the *real* type keys observed on a
live LSX II (i32_, string_, kefSpeakerStatus, kefPhysicalSource), plus a minimal
event-queue stub. Binds to 127.0.0.1 so it is exempt from macOS Local Network
Privacy — the compiled CLI can talk to it without a permission grant.

Usage:
    python3 mock_kef.py [port]           # POST writes (modern W2 firmware)
    KEF_MOCK_GETONLY=1 python3 mock_kef.py [port]   # simulate GET-only old firmware
"""
import json
import os
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

STATE = {
    "player:volume": 30,
    "settings:/kef/host/speakerStatus": "powerOn",
    "settings:/system/primaryMacAddress": "84:17:15:03:CD:9E",
    "settings:/deviceName": "Mock LSX II",
    "settings:/kef/host/maximumVolume": 100,
    "settings:/releasetext": "LSXII_V30137",
    "settings:/kef/play/physicalSource": "wifi",
}

# The key under which each path's value is returned (matches the live speaker).
TYPE_KEYS = {
    "player:volume": "i32_",
    "settings:/kef/host/maximumVolume": "i32_",
    "settings:/kef/host/speakerStatus": "kefSpeakerStatus",
    "settings:/kef/play/physicalSource": "kefPhysicalSource",
    "settings:/system/primaryMacAddress": "string_",
    "settings:/deviceName": "string_",
    "settings:/releasetext": "string_",
}

GETONLY = os.environ.get("KEF_MOCK_GETONLY") == "1"

# Change events queued for delivery on the next pollQueue (mirrors the speaker).
PENDING = []


def envelope(path):
    key = TYPE_KEYS.get(path, "string_")
    return [{"type": key, key: STATE.get(path)}]


def apply_volume(ival):
    if ival is None:
        return False
    try:
        v = int(ival)
    except (TypeError, ValueError):
        return False
    STATE["player:volume"] = max(0, min(v, STATE["settings:/kef/host/maximumVolume"]))
    PENDING.append({
        "path": "player:volume", "itemType": "update", "rowsEvents": [],
        "itemValue": {"type": "i32_", "i32_": STATE["player:volume"]},
    })
    return True


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        u = urlparse(self.path)
        q = parse_qs(u.query)
        if u.path == "/api/getData":
            path = q.get("path", [""])[0]
            if path in STATE:
                self._send(200, envelope(path))
            else:
                self._send(200, [{"type": "error_", "error_": "unknown path"}])
        elif u.path == "/api/setData":
            # Legacy GET-only write path (old firmware): value is JSON in a param.
            path = q.get("path", [""])[0]
            value_json = q.get("value", [None])[0]
            ival = None
            if value_json:
                try:
                    ival = json.loads(value_json).get("i32_")
                except (ValueError, AttributeError):
                    ival = None
            if path == "player:volume" and apply_volume(ival):
                self._send(200, True)
            else:
                self._send(400, False)
        elif u.path == "/api/event/pollQueue":
            global PENDING
            events, PENDING = PENDING, []
            self._send(200, events)
        else:
            self._send(404, {"error": "not found"})

    def do_POST(self):
        u = urlparse(self.path)
        if u.path == "/api/setData":
            if GETONLY:
                self._send(404, {"error": "POST not supported (use GET)"})
                return
            length = int(self.headers.get("Content-Length", 0))
            raw = self.rfile.read(length)
            try:
                payload = json.loads(raw)
            except ValueError:
                self._send(400, False)
                return
            path = payload.get("path")
            value = payload.get("value", {})
            ival = value.get("i32_") if isinstance(value, dict) else None
            if path == "player:volume" and apply_volume(ival):
                self._send(200, True)
            else:
                self._send(400, False)
        elif u.path == "/api/event/modifyQueue":
            self._send(200, "mockqueue1")  # stub
        else:
            self._send(404, {"error": "not found"})

    def log_message(self, *args):
        pass  # quiet by default


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
    server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    mode = "GET-only (legacy firmware)" if GETONLY else "POST (W2 firmware)"
    print(f"mock KEF speaker on http://127.0.0.1:{port}  (writes: {mode})", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
