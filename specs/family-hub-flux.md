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
  registers it as a kiosk and holds its own session. LAN path
  `http://192.168.1.3/family/` remains as fallback.
- The app's kiosk registration is independent of the Cloudflare Access session
  in front of it. Set the `hub` Access app session duration to 1 month, and run
  Chromium on its default profile so `CF_Authorization` survives reboot —
  otherwise the wall display returns to a login page. Tailnet + a dnsmasq
  `address=/hub.zakharhome.org/100.67.221.109` line would remove Access from
  this device's path entirely if the re-auth cadence becomes a problem.
- Kiosk autostart installed 2026-08-08 as
  `~/.config/autostart/family-hub-kiosk.desktop` on `kitchen-hub`
  (`lwrespawn` + `chromium --kiosk`). Unverified end to end: the Pi is still
  headless and the one-time admin OIDC login has not been done, so
  `~/.config/chromium` does not exist yet.
