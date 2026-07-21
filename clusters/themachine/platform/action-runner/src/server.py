import html
import json
import os
import ssl
import time
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(os.getenv("PORT", "8080"))
ADMIN_EMAILS = {email.strip().lower() for email in os.getenv("ADMIN_EMAILS", "").split(",") if email.strip()}
API = "https://kubernetes.default.svc"
TOKEN = open("/var/run/secrets/kubernetes.io/serviceaccount/token", encoding="utf-8").read().strip()
CA = "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
CTX = ssl.create_default_context(cafile=CA)
AUDIT = []

ALLOWED_DEPLOYMENTS = {
    "homepage": ("homepage", "homepage"),
    "zakharhome-site": ("zakharhome-site", "zakharhome-site"),
    "grafana": ("observability", "grafana"),
    "prometheus": ("observability", "prometheus"),
    "uptime-kuma": ("observability", "uptime-kuma"),
    "otel-collector": ("observability", "otel-collector"),
}

ALLOWED_RECONCILERS = {
    "fleet": ("kustomize.toolkit.fluxcd.io", "v1", "kustomizations", "flux-system", "flux-system"),
    "source": ("source.toolkit.fluxcd.io", "v1", "gitrepositories", "flux-system", "flux-system"),
    "gmail-frontend": ("kustomize.toolkit.fluxcd.io", "v1", "kustomizations", "flux-system", "gmail-frontend"),
    "vs-book-app": ("kustomize.toolkit.fluxcd.io", "v1", "kustomizations", "flux-system", "vs-book-app"),
    "synth": ("kustomize.toolkit.fluxcd.io", "v1", "kustomizations", "flux-system", "synth"),
}

ALLOWED_MOODE = {
    "livingroom": ("Living room", "192.168.1.46"),
    "basement": ("Basement", "192.168.1.40"),
    "console": ("Console", "192.168.1.28"),
}

def kube(method, path, body=None, content_type="application/json"):
    data = json.dumps(body).encode("utf-8") if body is not None else None
    req = urllib.request.Request(
        API + path,
        data=data,
        method=method,
        headers={
            "Authorization": f"Bearer {TOKEN}",
            "Accept": "application/json",
            "Content-Type": content_type,
        },
    )
    with urllib.request.urlopen(req, context=CTX, timeout=30) as res:
        raw = res.read().decode("utf-8", errors="replace")
        if res.headers.get("content-type", "").startswith("application/json"):
            return json.loads(raw) if raw else {}
        return raw

def page(handler, status, body):
    payload = body.encode("utf-8")
    handler.send_response(status)
    handler.send_header("content-type", "text/html; charset=utf-8")
    handler.send_header("cache-control", "no-store")
    handler.send_header("content-length", str(len(payload)))
    handler.end_headers()
    handler.wfile.write(payload)

def json_response(handler, status, body):
    payload = json.dumps(body, indent=2).encode("utf-8")
    handler.send_response(status)
    handler.send_header("content-type", "application/json")
    handler.send_header("cache-control", "no-store")
    handler.send_header("content-length", str(len(payload)))
    handler.end_headers()
    handler.wfile.write(payload)

def actor(headers):
    return (headers.get("cf-access-authenticated-user-email") or headers.get("x-authenticated-user-email") or "").lower()

def record(entry):
    AUDIT.insert(0, {"ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), **entry})
    del AUDIT[100:]

def condition_status(item, condition_type="Ready"):
    for condition in item.get("status", {}).get("conditions", []):
        if condition.get("type") == condition_type:
            return {
                "status": condition.get("status"),
                "reason": condition.get("reason"),
                "message": condition.get("message"),
                "time": condition.get("lastTransitionTime"),
            }
    return {"status": "Unknown", "reason": None, "message": None, "time": None}

def short_revision(revision):
    if not revision:
        return None
    sha = revision.rsplit(":", 1)[-1] if ":" in revision else revision
    return sha[:7]

def flux_status():
    source = kube("GET", "/apis/source.toolkit.fluxcd.io/v1/namespaces/flux-system/gitrepositories/flux-system")
    fleet = kube("GET", "/apis/kustomize.toolkit.fluxcd.io/v1/namespaces/flux-system/kustomizations/flux-system")
    sources = kube("GET", "/apis/source.toolkit.fluxcd.io/v1/namespaces/flux-system/gitrepositories")
    kustomizations = kube("GET", "/apis/kustomize.toolkit.fluxcd.io/v1/namespaces/flux-system/kustomizations")

    source_revision = source.get("status", {}).get("artifact", {}).get("revision")
    applied_revision = fleet.get("status", {}).get("lastAppliedRevision")
    source_ready = condition_status(source)
    fleet_ready = condition_status(fleet)
    items = sources.get("items", []) + kustomizations.get("items", [])
    failed = []
    suspended = []
    ready_count = 0

    for item in items:
        kind = item.get("kind")
        namespace = item.get("metadata", {}).get("namespace")
        name = item.get("metadata", {}).get("name")
        label = f"{kind}/{namespace}/{name}"
        if item.get("spec", {}).get("suspend"):
            suspended.append(label)
        ready = condition_status(item)
        if ready.get("status") == "True":
            ready_count += 1
        else:
            failed.append({
                "name": label,
                "reason": ready.get("reason"),
                "message": ready.get("message"),
            })

    synced = bool(source_revision and applied_revision and source_revision == applied_revision)
    return {
        "ok": True,
        "repo": short_revision(source_revision),
        "applied": short_revision(applied_revision),
        "sync": "synced" if synced else "pending",
        "ready": "yes" if source_ready.get("status") == "True" and fleet_ready.get("status") == "True" else "no",
        "readyCount": ready_count,
        "failCount": len(failed),
        "suspendedCount": len(suspended),
        "sourceRevision": source_revision,
        "appliedRevision": applied_revision,
        "sourceReady": source_ready,
        "fleetReady": fleet_ready,
        "failed": failed,
        "suspended": suspended,
    }

def moode_status(target):
    item = ALLOWED_MOODE.get(target)
    if not item:
        return {"ok": False, "error": "target not allowed", "state": "unknown", "volume": "-", "queue": "-"}

    name, ip = item
    url = f"http://{ip}/engine-mpd.php"
    try:
        req = urllib.request.Request(url, headers={"Accept": "application/json"})
        with urllib.request.urlopen(req, timeout=2) as res:
            data = json.loads(res.read().decode("utf-8", errors="replace"))
        return {
            "ok": True,
            "name": name,
            "state": data.get("state") or "unknown",
            "volume": data.get("volume") or "0",
            "queue": data.get("playlistlength") or "0",
        }
    except Exception:
        return {
            "ok": True,
            "name": name,
            "state": "off",
            "volume": "-",
            "queue": "-",
        }

def shell_html():
    deployments = "".join(f"<option value='{html.escape(k)}'>{html.escape(k)}</option>" for k in ALLOWED_DEPLOYMENTS)
    reconcilers = "".join(f"<option value='{html.escape(k)}'>{html.escape(k)}</option>" for k in ALLOWED_RECONCILERS)
    return f"""<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>Action Runner</title>
  <style>
    body {{ background:#050b12; color:#eef7ff; font-family:system-ui,sans-serif; margin:0; padding:24px; }}
    main {{ max-width:980px; margin:auto; }}
    section {{ border:1px solid rgba(180,220,255,.18); background:rgba(12,22,34,.7); border-radius:8px; padding:16px; margin:0 0 16px; }}
    button,select {{ background:#111d2b; color:#eef7ff; border:1px solid rgba(180,220,255,.24); border-radius:6px; padding:8px 10px; }}
    button {{ cursor:pointer; }}
    pre {{ white-space:pre-wrap; background:#03070b; border:1px solid rgba(180,220,255,.14); padding:12px; border-radius:6px; min-height:160px; }}
  </style>
</head>
<body>
  <main>
    <h1>Action Runner</h1>
    <section>
      <h2>Read</h2>
      <button onclick="call('GET','/flux/status')">Flux Status</button>
      <button onclick="call('GET','/pods')">List Pods</button>
      <select id="logDeployment">{deployments}</select>
      <button onclick="call('GET','/logs?deployment='+document.getElementById('logDeployment').value)">Tail Logs</button>
      <button onclick="call('GET','/audit')">Audit</button>
    </section>
    <section>
      <h2>Actions</h2>
      <select id="restartDeployment">{deployments}</select>
      <button onclick="confirmCall('/restart?deployment='+document.getElementById('restartDeployment').value)">Restart Deployment</button>
      <select id="reconcileTarget">{reconcilers}</select>
      <button onclick="confirmCall('/reconcile?target='+document.getElementById('reconcileTarget').value)">Flux Reconcile</button>
    </section>
    <pre id="out">Ready.</pre>
  </main>
  <script>
    async function call(method, path) {{
      const res = await fetch(path, {{ method }});
      document.getElementById('out').textContent = JSON.stringify(await res.json(), null, 2);
    }}
    async function confirmCall(path) {{
      if (!confirm('Run ' + path + '?')) return;
      await call('POST', path);
    }}
  </script>
</body>
</html>"""

class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        print("%s %s" % (self.address_string(), fmt % args), flush=True)

    def admin(self):
        email = actor(self.headers)
        if not email or email not in ADMIN_EMAILS:
            json_response(self, 403, {"ok": False, "error": "admin required", "email": email or None})
            return None
        return email

    def do_GET(self):
        try:
            parsed = urllib.parse.urlparse(self.path)
            params = urllib.parse.parse_qs(parsed.query)
            if parsed.path == "/healthz":
                return json_response(self, 200, {"ok": True})
            if parsed.path == "/flux/health":
                status = flux_status()
                http_status = 200 if status["failCount"] == 0 and status["sync"] == "synced" else 503
                return json_response(self, http_status, {
                    "ok": http_status == 200,
                    "sync": status["sync"],
                    "failCount": status["failCount"],
                })
            if parsed.path == "/flux/status":
                return json_response(self, 200, flux_status())
            if parsed.path == "/moode/status":
                target = params.get("target", [""])[0]
                return json_response(self, 200, moode_status(target))
            if parsed.path == "/":
                if not self.admin():
                    return
                return page(self, 200, shell_html())
            email = self.admin()
            if not email:
                return
            if parsed.path == "/audit":
                return json_response(self, 200, {"ok": True, "audit": AUDIT})
            if parsed.path == "/pods":
                pods = kube("GET", "/api/v1/pods")
                rows = [{
                    "namespace": item["metadata"]["namespace"],
                    "name": item["metadata"]["name"],
                    "phase": item["status"].get("phase"),
                    "node": item["spec"].get("nodeName"),
                    "restarts": sum(c.get("restartCount", 0) for c in item["status"].get("containerStatuses", [])),
                } for item in pods.get("items", [])]
                return json_response(self, 200, {"ok": True, "pods": rows})
            if parsed.path == "/logs":
                key = params.get("deployment", [""])[0]
                item = ALLOWED_DEPLOYMENTS.get(key)
                if not item:
                    return json_response(self, 400, {"ok": False, "error": "deployment not allowed"})
                namespace, deployment = item
                selector = urllib.parse.quote(f"app.kubernetes.io/name={deployment}", safe="")
                pods = kube("GET", f"/api/v1/namespaces/{namespace}/pods?labelSelector={selector}")
                if not pods.get("items"):
                    return json_response(self, 404, {"ok": False, "error": "pod not found"})
                pod = pods["items"][0]["metadata"]["name"]
                logs = kube("GET", f"/api/v1/namespaces/{namespace}/pods/{pod}/log?tailLines=120")
                return json_response(self, 200, {"ok": True, "deployment": key, "logs": logs})
            return json_response(self, 404, {"ok": False, "error": "not found"})
        except Exception as error:
            return json_response(self, 500, {"ok": False, "error": str(error)})

    def do_POST(self):
        try:
            parsed = urllib.parse.urlparse(self.path)
            params = urllib.parse.parse_qs(parsed.query)
            email = self.admin()
            if not email:
                return
            if parsed.path == "/restart":
                key = params.get("deployment", [""])[0]
                item = ALLOWED_DEPLOYMENTS.get(key)
                if not item:
                    return json_response(self, 400, {"ok": False, "error": "deployment not allowed"})
                namespace, deployment = item
                patch = {"spec": {"template": {"metadata": {"annotations": {"action-runner/restarted-at": str(time.time())}}}}}
                kube("PATCH", f"/apis/apps/v1/namespaces/{namespace}/deployments/{deployment}", patch, "application/merge-patch+json")
                record({"actor": email, "action": "restart", "target": key})
                return json_response(self, 200, {"ok": True, "message": f"restarted {key}"})
            if parsed.path == "/reconcile":
                key = params.get("target", [""])[0]
                item = ALLOWED_RECONCILERS.get(key)
                if not item:
                    return json_response(self, 400, {"ok": False, "error": "target not allowed"})
                group, version, plural, namespace, name = item
                patch = {"metadata": {"annotations": {"reconcile.fluxcd.io/requestedAt": str(int(time.time()))}}}
                kube("PATCH", f"/apis/{group}/{version}/namespaces/{namespace}/{plural}/{name}", patch, "application/merge-patch+json")
                record({"actor": email, "action": "reconcile", "target": key})
                return json_response(self, 200, {"ok": True, "message": f"reconcile requested for {key}"})
            return json_response(self, 404, {"ok": False, "error": "not found"})
        except Exception as error:
            return json_response(self, 500, {"ok": False, "error": str(error)})

ThreadingHTTPServer(("", PORT), Handler).serve_forever()
