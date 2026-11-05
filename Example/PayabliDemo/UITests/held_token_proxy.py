"""A token host for SheetSubmitHoldUITests: relays to the demo token server and holds every request after the first.

The first request is the screen's own token check. The second is the SDK's, made when the payer saves, so holding it
keeps the save in flight.

    python3 held_token_proxy.py 8790 http://127.0.0.1:8788
"""

import http.server
import sys
import threading
import time
import urllib.error
import urllib.request

HOLD_SECONDS = 15
UPSTREAM = sys.argv[2] if len(sys.argv) > 2 else "http://127.0.0.1:8788"
count = 0
lock = threading.Lock()


class Relay(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.relay()

    def do_POST(self):
        self.relay()

    def relay(self):
        global count
        with lock:
            count += 1
            held = count > 1
        if held:
            time.sleep(HOLD_SECONDS)
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length) if length else None
        request = urllib.request.Request(UPSTREAM + self.path, data=body, method=self.command)
        if self.headers.get("Content-Type"):
            request.add_header("Content-Type", self.headers["Content-Type"])
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                body, status, content_type = response.read(), response.status, response.headers.get("Content-Type")
        except urllib.error.HTTPError as error:
            body, status, content_type = error.read(), error.code, error.headers.get("Content-Type")
        self.send_response(status)
        self.send_header("Content-Type", content_type or "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


http.server.ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1])), Relay).serve_forever()
