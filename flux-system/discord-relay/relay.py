"""Flux notification-controller -> Discord relay.

Flux's own discord provider can't be templated: every event becomes an embed
headed "Kind/name.namespace" with each metadata key as a field (revision,
token sha256, app-version, summary). This receives the events from a `generic`
Provider instead, batches whatever arrives within BATCH_SECONDS (one git push
fans out into several per-app events), and posts one compact embed:

  ✅ opsimath · Deployment/opsimath-web configured · 4129a52
  ✅ kube-prometheus-stack · upgraded to chart 70.10.0
  ❌ wallabag · kustomize build failed: ...

Stdlib only (runs on k8s-toolbox). Filtering (exclusionList) stays on the Alert.
"""
import json
import os
import re
import signal
import sys
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

WEBHOOK = os.environ["DISCORD_WEBHOOK"]
BATCH_SECONDS = float(os.environ.get("BATCH_SECONDS", "20"))
USERNAME = os.environ.get("DISCORD_USERNAME", "k8s homelab")
MAX_LINES = 20       # per message; the rest is summarised as "+N more"
MAX_DESC = 3800      # Discord embed description limit is 4096
MAX_ERROR = 400      # error text per event
GREEN, RED = 3066993, 15158332

pending = []
lock = threading.Lock()
timer = None


def log(msg):
    print(msg, file=sys.stderr, flush=True)


def short_rev(meta):
    for k, v in meta.items():
        if k.split("/")[-1] == "revision":
            m = re.search(r"sha1:([0-9a-f]{7})", v)
            if m:
                return m.group(1)
    return None


def change_lines(msg):
    """'Deployment/ns/name configured' lines -> 'Deployment/name configured'."""
    lines = [l.strip() for l in msg.splitlines() if l.strip()]
    if not lines or not all(re.match(r"^\S+/\S+ \w+$", l) for l in lines):
        return None
    lines = [re.sub(r"^([^/\s]+)/[^/\s]+/(\S+)", r"\1/\2", l) for l in lines]
    if len(lines) > 3:
        lines = lines[:2] + [f"+{len(lines) - 2} more"]
    return ", ".join(lines)


def format_event(ev):
    obj = ev.get("involvedObject", {})
    name = obj.get("name", "?")
    if obj.get("kind") == "GitRepository":
        name = f"git {name}"
    msg = (ev.get("message") or "").strip()
    error = ev.get("severity") == "error"

    m = re.match(r"Helm (install|upgrade|rollback|uninstall) succeeded .* with chart \S+@(\S+)", msg)
    if m:
        verb = {"install": "installed", "upgrade": "upgraded to",
                "rollback": "rolled back to", "uninstall": "uninstalled"}[m.group(1)]
        text = f"{verb} chart {m.group(2)}"
    elif not error and (c := change_lines(msg)):
        text = c
    else:
        text = re.sub(r"\s+", " ", msg)
        if len(text) > MAX_ERROR:
            text = text[:MAX_ERROR] + "…"

    line = f"{'❌' if error else '✅'} **{name}** · {text}"
    if obj.get("kind") == "Kustomization" and (rev := short_rev(ev.get("metadata") or {})):
        line += f" · `{rev}`"
    return error, line


def post(payload):
    data = json.dumps(payload).encode()
    for _ in range(4):
        req = urllib.request.Request(WEBHOOK, data=data, headers={
            "Content-Type": "application/json", "User-Agent": "flux-discord-relay"})
        try:
            urllib.request.urlopen(req, timeout=10).read()
            return True
        except urllib.error.HTTPError as e:
            if e.code == 429:
                time.sleep(float(json.loads(e.read() or b"{}").get("retry_after", 2)))
                continue
            log(f"discord post failed: HTTP {e.code} {e.read()[:200]!r}")
            return
        except Exception as e:  # network blip: retry
            log(f"discord post failed: {e}")
            time.sleep(2)
    log("discord post gave up after retries")
    return False


def flush():
    global timer
    with lock:
        events, pending[:], timer = list(pending), [], None
    if not events:
        return
    formatted = [format_event(e) for e in events]
    lines = []
    # Failures first, so they're never the part that gets cut off.
    for _, line in sorted(formatted, key=lambda f: not f[0]):
        if len(lines) >= MAX_LINES or sum(len(l) + 1 for l in lines) + len(line) > MAX_DESC:
            lines.append(f"+{len(formatted) - len(lines)} more")
            break
        lines.append(line)
    n_err = sum(err for err, _ in formatted)
    if not n_err:
        title = "Flux: deployed"
    elif n_err == len(formatted):
        title = "Flux: reconcile failed"
    else:
        title = f"Flux: {n_err} failed, {len(formatted) - n_err} ok"
    if post({"username": USERNAME, "embeds": [{
            "title": title, "description": "\n".join(lines),
            "color": RED if n_err else GREEN}]}):
        log(f"posted {len(formatted)} event(s): {title}")


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):  # readiness/liveness
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"ok")

    def do_POST(self):
        global timer
        try:
            ev = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))))
        except Exception as e:
            log(f"bad event: {e}")
            self.send_response(400)
            self.end_headers()
            return
        with lock:
            pending.append(ev)
            if timer is None:
                timer = threading.Timer(BATCH_SECONDS, flush)
                timer.daemon = True
                timer.start()
        self.send_response(202)
        self.end_headers()

    def log_message(self, *args):
        pass


def shutdown(signum, frame):
    # Rollouts (including of this relay) send events while the old pod is
    # terminating; post the pending batch rather than drop it.
    if timer is not None:
        timer.cancel()
    flush()
    sys.exit(0)


if __name__ == "__main__":
    signal.signal(signal.SIGTERM, shutdown)
    log(f"flux-discord-relay listening on :8080, batch {BATCH_SECONDS}s")
    ThreadingHTTPServer(("", 8080), Handler).serve_forever()
