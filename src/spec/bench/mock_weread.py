#!/usr/bin/env python3
"""Local WeRead mock for the download bench (weread mock_endpoint protocol:
GET/POST /__proxy?url=<real url>). Simulates a Kindle link: per-request
connection setup (TCP+TLS on a PW5, LuaSocket has no keep-alive), RTT, server
think time and a *shared* downlink bandwidth. Honors Accept-Encoding: gzip.
Usage: mock_weread.py PORT FIXDIR SETUP_MS RTT_MS SERVER_MS KBPS"""
import gzip, json, os, sys, threading, time, urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
PORT, FIX = int(sys.argv[1]), sys.argv[2]
SETUP, RTT, SRV, KBPS = [float(x) / 1000 if i < 3 else float(x) for i, x in enumerate(sys.argv[3:7])]
CMAP = json.load(open(FIX + "/cmap.json"))
lock = threading.Lock(); link_free = [time.time()]
def send_time(n):  # shared link: bytes queue behind each other
    with lock:
        start = max(time.time(), link_free[0]); link_free[0] = start + n / (KBPS * 1024)
        return link_free[0]
stats = {"req": 0, "bytes": 0}
class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.0"
    def log_message(self, *a): pass
    def handle_one(self, body_in):
        q = urllib.parse.urlparse(self.path)
        url = urllib.parse.parse_qs(q.query).get("url", [""])[0]
        p = urllib.parse.urlparse(url).path
        if p.startswith("/web/reader/"): data, ct = open(FIX + "/reader.html", "rb").read(), "text/html"
        elif p.endswith("/chapterInfos"): data, ct = open(FIX + "/chapterInfos.json", "rb").read(), "application/json"
        elif "/web/book/chapter/e_" in p:
            e = p.rsplit("/", 1)[1]
            c = CMAP.get(json.loads(body_in or b"{}").get("c"), 0)
            fn = FIX + "/e_2" if e == "e_2" else "%s/%s.%s" % (FIX, c, e)
            data, ct = open(fn, "rb").read(), "text/plain"
        else: data, ct = b"{}", "application/json"
        time.sleep(SETUP + RTT + SRV)  # connect+TLS, request RTT, server work
        enc = None
        if "gzip" in (self.headers.get("Accept-Encoding") or ""):
            data = gzip.compress(data, 6); enc = "gzip"
        done = send_time(len(data)); d = done - time.time()
        if d > 0: time.sleep(d)
        stats["req"] += 1; stats["bytes"] += len(data)
        self.send_response(200); self.send_header("Content-Type", ct)
        if enc: self.send_header("Content-Encoding", enc)
        self.send_header("Content-Length", str(len(data))); self.end_headers(); self.wfile.write(data)
    def do_GET(self):
        if self.path == "/__stats":
            b = json.dumps(stats).encode(); self.send_response(200); self.send_header("Content-Length", str(len(b))); self.end_headers(); self.wfile.write(b); return
        self.handle_one(None)
    def do_POST(self):
        n = int(self.headers.get("Content-Length") or 0); self.handle_one(self.rfile.read(n))
ThreadingHTTPServer(("127.0.0.1", PORT), H).serve_forever()
