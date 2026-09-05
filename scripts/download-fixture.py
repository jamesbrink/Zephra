#!/usr/bin/env python3
"""Loopback Hugging Face fixture for the Debug-only native download exercise.

Run with --port 8765, then launch an isolated Debug app with
ZEPHRA_DOWNLOAD_TEST_HUB=http://127.0.0.1:8765 and a disposable models directory.
No actual model weights are served. Requests print to stdout for sharing/Range evidence.
"""
import argparse
import json
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class Fixture(BaseHTTPRequestHandler):
    def do_GET(self):
        print(json.dumps({"path": self.path, "range": self.headers.get("Range")}), flush=True)
        if "/revision/" in self.path:
            self.reply(json.dumps({"sha": "exercise-commit"}).encode())
        elif "/tree/" in self.path:
            name = ("Qwen-Image-2512-Lightning-4steps-V1.0-fp32.safetensors"
                    if "Lightning" in self.path else "model_index.json")
            self.reply(json.dumps([{"type": "file", "path": name, "size": self.server.size}]).encode())
        elif "/resolve/" in self.path:
            offset = int((self.headers.get("Range") or "bytes=0-").split("=")[1].split("-")[0])
            self.send_response(206 if offset else 200)
            self.send_header("Content-Length", str(self.server.size - offset))
            self.send_header("ETag", '"exercise-commit"')
            if offset:
                self.send_header("Content-Range", f"bytes {offset}-{self.server.size - 1}/{self.server.size}")
            self.end_headers()
            try:
                for start in range(offset, self.server.size, 32768):
                    self.wfile.write(b"x" * min(32768, self.server.size - start))
                    self.wfile.flush()
                    time.sleep(self.server.delay)
            except (BrokenPipeError, ConnectionResetError):
                pass
        else:
            self.send_error(404)

    def reply(self, body):
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_):
        pass


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--mib", type=int, default=8)
    parser.add_argument("--delay", type=float, default=0.2)
    args = parser.parse_args()
    server = ThreadingHTTPServer(("127.0.0.1", args.port), Fixture)
    server.size, server.delay = args.mib << 20, args.delay
    print(f"Serving disposable fixture at http://127.0.0.1:{args.port}", flush=True)
    server.serve_forever()
