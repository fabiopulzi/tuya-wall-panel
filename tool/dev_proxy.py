"""Local CORS proxy for the web preview (development only).

The Tuya OpenAPI sends no CORS headers, so a browser cannot call it. This
forwards requests unchanged (the signature covers only path and body) and
adds CORS headers. It listens on 127.0.0.1 only.

    python3 tool/dev_proxy.py [us|eu|in|cn]
    flutter run -d chrome --dart-define-from-file=tuya_credentials.json \
        --dart-define=TUYA_BASE_URL=http://127.0.0.1:8787
"""
import sys
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

UPSTREAM = f"https://openapi.tuya{sys.argv[1] if len(sys.argv) > 1 else 'us'}.com"
FORWARD = ("client_id", "sign", "sign_method", "t", "nonce", "access_token", "content-type")


class Proxy(BaseHTTPRequestHandler):
    def _cors(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", ", ".join(FORWARD))
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")

    def do_OPTIONS(self):
        self.send_response(204)
        self._cors()
        self.end_headers()

    def _forward(self, method):
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length) if length else None
        headers = {k: v for k, v in self.headers.items() if k.lower() in FORWARD}
        req = urllib.request.Request(UPSTREAM + self.path, data=body, headers=headers, method=method)
        try:
            with urllib.request.urlopen(req, timeout=20) as r:
                status, payload = r.status, r.read()
        except urllib.error.HTTPError as e:
            status, payload = e.code, e.read()
        self.send_response(status)
        self._cors()
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self):
        self._forward("GET")

    def do_POST(self):
        self._forward("POST")

    def log_message(self, fmt, *args):
        sys.stderr.write("%s\n" % (fmt % args).split('?')[0])


if __name__ == "__main__":
    print(f"proxy 127.0.0.1:8787 -> {UPSTREAM}")
    ThreadingHTTPServer(("127.0.0.1", 8787), Proxy).serve_forever()
