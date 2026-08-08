# Family Hub Flux Wiring

Status: registered
Last updated: 2026-07-31

- Flux source: `https://github.com/mzakhar/family-hub.git`, pinned to commit
  `ab9ea8c9b91f67971b7508faa389bd7b8b25c810`.
- Flux applies `deploy/k8s/` as `family-hub`.
- App manifests require existing `family-hub/family-hub-secrets`; values stay out
  of Git. Required keys: `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`,
  `SESSION_SECRET`, `SEED_USERS`, `SEED_JOURNAL_ACCESS`.
- Public host `hub.zakharhome.org` still needs Cloudflare Tunnel and Access
  configuration before external use.
- Kitchen wall kiosk: `kitchen-hub` (Pi 5, `192.168.1.48`, Orbi reservation) will
  display Family Hub at `https://hub.zakharhome.org`. Admin completes the
  `Family oidc access` login once on the device during setup; the app then
  registers it as a kiosk and holds its own session.
- The LAN path `http://192.168.1.3/family/` is not a fallback for pairing. It
  answers 200, but the OAuth `redirect_uri` is pinned to `PUBLIC_ORIGIN`, so a
  login started there drops its cookie on `hub.zakharhome.org` instead. Debug
  door only.
- The app's kiosk registration is independent of the Cloudflare Access session
  in front of it. The `hub` Access app is at its longest session (1 month), and
  Chromium runs on its default profile so `CF_Authorization` survives reboot —
  expect a periodic admin re-login regardless.
- The tailnet does not remove Access from this path, despite `kitchen-hub`
  being a tailnet peer since 2026-08-08. Adding
  `address=/hub.zakharhome.org/100.67.221.109` to dnsmasq is one line, but
  Traefik answers 443 on that hostname with `CN=TRAEFIK DEFAULT CERT` and
  Chromium refuses it; plain HTTP is no escape either, since `PUBLIC_ORIGIN` is
  `https://`, which makes the session cookie `Secure` and sends the OIDC
  redirect to `https://` anyway. Blocked on a real cert.
- cert-manager v1.21.1 and the `letsencrypt-prod` ClusterIssuer went in
  2026-08-08 (`#49`, ordering fixed in `#50`); the issuer is Ready with its ACME
  account registered. Two things still gate an actual certificate: the
  `cloudflare-api-token` secret has not been applied to the `cert-manager`
  namespace, and nothing requests a cert yet — the `tls:` block and
  `cert-manager.io/cluster-issuer` annotation live in `mzakhar/family-hub` at
  `deploy/k8s/app.yaml`, not in this repo.
- Kiosk autostart installed 2026-08-08 as
  `~/.config/autostart/family-hub-kiosk.desktop` on `kitchen-hub`
  (`lwrespawn` + `chromium --kiosk`). Unverified end to end: the Pi is still
  headless and the one-time admin OIDC login has not been done, so
  `~/.config/chromium` does not exist yet.
