# Observability Stack and Homepage Plan

Status: implementation in progress
Last updated: 2026-07-31

## Goal

Make the Grafana observability stack and Homepage observability section answer useful operational questions quickly:

- Is anything down or degraded?
- Which host or service is causing the problem?
- Did Flux apply the latest repo state?
- Are apps getting slower or erroring?
- Can a failing request be followed from metric spike to trace?
- What needs attention today?

Protected browser route rollout is tracked in
`specs/cloudflare-dashboard-services.md`.

## Current Baseline

Deployed on `themachine`:

- Prometheus with 30 day retention.
- Grafana with Prometheus and Tempo datasources.
- Tempo with 72 hour trace retention.
- OpenTelemetry Collector accepting OTLP gRPC/HTTP inside the cluster and through LAN NodePorts.
- Uptime Kuma with a `homelab` status page.
- Node exporter on `themachine` and `homeserver`.
- Alloy ships persistent host systemd-journal entries to Loki after recovery.
- Prometheus alerts when a host boot time changes.
- Homepage cards for host metrics, Uptime Kuma status, OpenTelemetry Explore, Fleet Sync, and app status checks.

Current gaps, refreshed 2026-07-30 against the live cluster. Everything listed
in the original gap list has since been closed:

- Homepage cards, OpenTelemetry icon, Kubernetes scrape discovery, alert rules
  and notification routing, the app/service RED dashboard, hosted-app
  instrumentation, and the logs backend are all done. See Phases 1 through 3c
  and the Phase 4/5/6 status notes.

What is actually still open:

- `clean-mail-backend` emits both legacy and stable HTTP conventions
  (`OTEL_SEMCONV_STABILITY_OPT_IN=http/dup`). The legacy series should be
  dropped once nothing queries them.
- Grafana and Uptime Kuma are still LAN-only; Phase 7 protected hostnames are
  not published.
- No exemplar support, so jumping from a latency spike to an individual trace
  still means a manual Tempo search.
- Alertmanager routes everything to one receiver at one repeat interval. There
  is no severity-based routing or quiet-hours handling.
- ~~Log-based alerting is unavailable.~~ Closed 2026-07-30: the Loki ruler is
  enabled and routes to Alertmanager.
- Cloudflare Access policies for `grafana.` and `uptime.` are not yet created,
  so those hostnames must not be published until they are.

## Design Principles

- Homepage is the triage surface; Grafana is the investigation surface.
- Prometheus owns metrics. Tempo owns traces. Uptime Kuma owns black-box uptime checks.
- OpenTelemetry Collector is the only ingestion path for app telemetry.
- Start with simple auto-instrumentation and RED metrics. Add sampling, views, and log signal only when there is real pressure.
- Avoid high-cardinality metric labels: no full URLs, user IDs, request IDs, raw errors, trace IDs, or free-form messages.

## Useful Homepage Shape

Replace the current generic Observability row with direct signal cards:

### Overview

- `Service Health`: Uptime Kuma `up`, `down`, `uptime`.
- `Fleet Sync`: repo revision, applied revision, last reconciliation time, sync
  state, failed object count.
- `Alerts`: active warning/critical count from Prometheus Alertmanager or a small internal status endpoint.

### Hosts

- `themachine`: CPU, RAM, root disk, pod pressure or filesystem pressure.
- `homeserver`: CPU, RAM, root disk, media disk when available.

### Apps

- `Hosted Apps RED`: request rate, 5xx/error rate, p95 latency from Prometheus.
- `Trace Intake`: collector accepted spans/sec, refused spans, Tempo ingestion errors.
- `Kuma Incidents`: count of currently down monitors and worst monitor name if exposed cleanly.

Keep raw Grafana/Prometheus/Tempo links in `Docs` or a compact `Tools` group, not as the primary Observability signal.

## Grafana Dashboards

### 1. Homelab Overview

Top-level dashboard for repeated use:

- Host CPU/RAM/disk panels for `themachine` and `homeserver`.
- Kubernetes pod restarts, pending pods, CPU and memory by namespace.
- Uptime status summary.
- Flux sync status and failure count.
- Prometheus scrape health.
- Collector and Tempo health.

### 2. Hosts

Improve existing `Linux Hosts` dashboard:

- Add filesystem table with mount, size, used %, and free bytes.
- Add load average and CPU saturation.
- Add network transmit next to receive.
- Add node exporter scrape status.
- Add variables for `instance` and `mountpoint`.

### 3. Services RED

App/service dashboard once telemetry exists:

- Request rate by service and route template.
- Error rate by service, status code, and error type.
- p50/p95/p99 latency.
- Slowest route templates.
- Link latency exemplars or trace query links into Tempo when supported.

### 4. Telemetry Pipeline

Pipeline health dashboard:

- OTLP spans/metrics received by collector.
- Collector refused/dropped telemetry.
- Collector memory limiter events.
- Tempo ingestion rate and errors.
- Prometheus target health and scrape duration.

## Implementation Phases

### Phase 1 - Fix Homepage Triage

- [x] Fix OpenTelemetry icon or replace it with `si-opentelemetry`/`mdi-vector-polyline`.
- [x] Add Prometheus-backed Homepage widgets for collector/Tempo health.
- [x] Add Homepage alert count backed by Prometheus firing alert state.
- [x] Move host, fleet sync, alert, cluster pressure, and telemetry intake cards into the main Observability row.
- [x] Verify Homepage card rendering after Flux deploy.

### Phase 2 - Add Kubernetes Metrics

- [x] Deploy kube-state-metrics.
- [x] Scrape kube-state-metrics directly.
- [x] Scrape annotated Kubernetes pods with conservative relabeling.
- [x] Add Grafana panels for pod restarts, pending pods, and deployment availability.
- [x] Add Homepage card for cluster pressure: unavailable deployments, restarting pods, pending pods.
- [x] Add service endpoint discovery only when services expose intentional Prometheus annotations.
- [x] Verify Prometheus targets after Flux deploy.

### Phase 3 - Add Alerting

- [x] Deploy Alertmanager or Grafana-managed notification routing.
- [x] Add source-controlled Prometheus rules for:
  - Node filesystem >85% used and >95% critical.
  - Prometheus target down.
  - Kubernetes deployment unavailable.
  - Pod restart spike.
  - Collector refused spans/metrics.
- [x] Add Uptime Kuma critical monitor alert integration.
- [ ] Add Cloudflare Access service-token probes for protected public routes,
  then restore those routes to paging once authenticated checks are reliable.
- [x] Route notifications to a low-noise target first.
- [x] Add Homepage alert count card.

### Phase 3b - App-Level Alerting

The Phase 3 rules covered infrastructure only. Nothing alerted on application
error conditions, so app errors stayed invisible on Homepage.

- [x] Add `apps.rules` for HTTP 5xx rate (warning 5%, critical 25%) and p95
  latency. Note: the 5xx rules as shipped here matched Clean Mail's label names
  only and never covered VS Book App. Fixed in Phase 3c.
- [x] Add `clean-mail.rules` for push send failures, Gmail watch expiry, and
  Gmail cursor lag.
- [x] Forward parsed Alertmanager notifications from action-runner to ntfy so
  alerts leave the cluster instead of dying in an in-memory list.
- [x] Split the Homepage `Alerts` card into critical/warning/app counts.
- [x] Add a Homepage `Clean Mail Health` card with 5xx rate, p95, and req/s.
- [x] Apply the `action-runner-ntfy` secret on `themachine` and subscribe the
  phone to the topic.
- [x] Verify a deliberately triggered alert reaches ntfy end to end.

### Phase 3c - Normalize Semconv And Services RED

Phase 3b shipped app rules keyed on Clean Mail's label names, which silently
excluded VS Book App. Root cause was two HTTP semantic conventions live at once.

- [x] Fix the label-name gap that left VS Book App without 5xx alerting.
- [x] Set `OTEL_SEMCONV_STABILITY_OPT_IN=http/dup` on the Clean Mail backend so
  it emits stable HTTP conventions alongside the legacy ones.
- [x] Rewrite `apps.rules` against stable conventions only, with no metric-name
  regex and no `or` branches.
- [x] Add `AppMissingStableHttpMetrics` so an app that drops off stable
  conventions is reported instead of silently losing every app rule.
- [x] Move the Homepage Clean Mail Health card onto stable metric names.
- [x] Add the `Services RED` Grafana dashboard with a `service` template
  variable covering all instrumented apps.
- [x] Verify after rollout that `clean-mail-backend` appears in the Services RED
  service picker and `AppMissingStableHttpMetrics` clears.
- [ ] Switch `http/dup` to `http` once no query references
  `http_server_duration_milliseconds_*`.

### Phase 4 - Instrument Hosted Apps

- First target pair: Clean Mail and VS Book App. Either may land first.
- [x] Wire VS Book App locally with Node.js HTTP/Express auto-instrumentation,
  OTLP trace/metric export, stable HTTP semantic conventions, and explicit
  `service.name=vs-book-app` identity.
- [x] Commit/push VS Book App changes, let its image workflow publish, update
  the pinned deployment image, and verify the Flux rollout.
- [x] Verify VS Book App traces in Tempo and RED metrics in Prometheus against
  real cluster traffic.
- [x] Finish Clean Mail instrumentation and apply the same end-to-end checks.
  Verified live 2026-07-30: FastAPI/ASGI auto-instrumentation exporting over
  OTLP/HTTP, traces in Tempo (`GET /api/triage`), RED metrics in Prometheus
  under `clean-mail-backend`, and custom `cleanmail_*` metrics for the Gmail
  watch, cursor age, and FCM send path. Stable HTTP conventions since Phase 3c.
- Add app auto-instrumentation where practical:
  - HTTP server spans and `http.server.request.duration`.
  - HTTP client spans for external calls.
  - DB spans/metrics where each app has a database.
- Set `OTEL_SERVICE_NAME`, `OTEL_RESOURCE_ATTRIBUTES`, and OTLP endpoint in app manifests.
- Add manual spans only at external service boundaries or business-critical operations.
- Keep status route labels templated and low cardinality.

### Phase 5 - Metric to Trace Investigation

Partly done ahead of this plan; status confirmed live 2026-07-30.

- [x] Tempo datasource has `tracesToMetrics` and `tracesToLogsV2` configured.
- [x] Loki datasource derives a `TraceID` field that links back into Tempo, so
  trace and log navigation is bidirectional.
- [x] Fix `tracesToMetrics.datasourceUid`, which read `prometheus` while the
  datasource uid is `Prometheus`. Grafana uids are case-sensitive, so the link
  had been resolving to nothing since it was added.
- [ ] Define actual `tracesToMetrics` queries. The block is wired but carries no
  query definitions, so it cannot yet jump from a span to its RED metrics.
- [ ] Add exemplar support if the current Prometheus/Grafana/SDK path supports
  it cleanly. Requires `--enable-feature=exemplar-storage` on Prometheus and
  exemplar export from the Collector.
- [ ] Add dashboard links from Services RED panels into Tempo searches by
  `service.name`, `http.route`, and status/error attributes.
- [ ] Consider Tempo `metrics_generator` for service graphs; it is not enabled.

### Phase 6 - Logs Later

Done ahead of this plan. Loki and Grafana Alloy are deployed and Alloy ships
pod logs cluster-wide.

- [x] Loki deployed with 168h retention and a compactor.
- [x] Alloy ships pod logs from 9 namespaces including `clean-mail`.
- [x] Clean Mail logs carry `trace_id`, so log-to-trace correlation works.
- [x] Logs stay LAN-only; Loki is a ClusterIP service.
- [ ] Enable the Loki `ruler` with an `alertmanager_url`. A `rules_directory` is
  configured but no ruler block exists, so no log-based alerting is possible.

### Phase 7 - Protected Investigation UIs

- [x] Add the `grafana.zakharhome.org` Ingress and tunnel hostname.
- [x] Add the `uptime.zakharhome.org` Ingress and tunnel hostname.
- [ ] Create the admin-only Cloudflare Access policies, then run
  `setup-tunnel.sh` to create the DNS records. Access must exist first:
  Grafana runs with anonymous Viewer enabled and Uptime Kuma serves a public
  status page, so Access is the only auth boundary in front of either.
- [ ] Publish raw Prometheus UI only if it adds value beyond Grafana.
- [x] Keep Tempo, Loki, OTel receivers, exporters, kube-state-metrics, and
  Alertmanager internal. None have an Ingress.
- [x] Change Homepage browser links to protected HTTPS hostnames while keeping
  widget/API URLs on internal Kubernetes service DNS. Six `href` values moved;
  every widget `url` still points at `*.svc.cluster.local`.
- [x] Point `GF_SERVER_ROOT_URL` at the public hostname so Grafana-generated
  absolute links resolve for off-LAN users.

## First Implementation Slice

Recommended next work:

1. Add `kube-state-metrics`.
2. Add Prometheus scrape config for kube-state-metrics and Kubernetes pods/services.
3. Add `Homelab Overview` and `Telemetry Pipeline` Grafana dashboards.
4. Replace Homepage Observability row with:
   - `Service Health`
   - `Fleet Sync`
   - `Alerts`
   - `themachine`
   - `homeserver`
   - `Telemetry Intake`
5. Fix the OpenTelemetry icon/card rendering.

This gives immediate value without waiting for every hosted app to emit traces.

Progress on 2026-07-20:

- Added kube-state-metrics with restricted resources/RBAC and image `registry.k8s.io/kube-state-metrics/kube-state-metrics:v2.19.0`.
- Added Prometheus Kubernetes pod discovery for explicit `prometheus.io/scrape: "true"` annotations.
- Added Prometheus alert rules for target, filesystem, deployment, restart, and Collector refusal signals.
- Added provisioned Grafana `Homelab Overview` and `Telemetry Pipeline` dashboards.
- Reworked Homepage Observability row into direct signal cards.
- Validated observability and Homepage kustomize overlays with `kubectl apply --dry-run=client -k`.
- `promtool` was not installed locally, so Prometheus config/rule semantic validation remains a deploy-time check.

Progress on 2026-07-21:

- Verified live Flux kustomizations, observability pods, Homepage service API, and Prometheus targets on `themachine`.
- Added Alertmanager with a conservative 12 hour repeat interval and an internal action-runner webhook receiver.
- Added Prometheus `kubernetes-service-endpoints` discovery for Services that explicitly set `prometheus.io/scrape: "true"`.
- Added action-runner `/metrics`, `/kuma/status`, `/alerts/webhook`, and `/alerts/status` endpoints.
- Exposed Uptime Kuma public status page state as Prometheus metrics through action-runner.
- Added Prometheus alerts for Uptime Kuma status page read failure and individual Kuma monitor down state.
- Verified action-runner service endpoint scrape is up, `uptime_kuma_status_page_up` is `1`, `uptime_kuma_monitors_down` is `0`, and Prometheus firing alert count returned to `0` after rollout.
- Cleaned accidental local Rancher Desktop namespaces created during a kube-context mismatch; live changes were then applied through SSH on `themachine`.
- Selected Clean Mail and VS Book App as the first hosted-app instrumentation
  pair.
- Wired VS Book App with OpenTelemetry Node.js auto-instrumentation,
  OTLP/HTTP trace and metric exporters, stable HTTP semantic conventions, and
  production collector settings in its Kubernetes Deployment.
- Verified the VS Book App build, rendered Kubernetes manifests, and ran a
  local OTLP smoke test proving `vs-book-app` HTTP traces and
  `http.server.request.duration` metrics export.
- Merged VS Book App instrumentation PR #45 and image-pin PR #46, published
  image digest
  `sha256:8abfd888d8e9c4cace95efaae940878c098cb43c1d9357efc716584059d1074f`,
  reconciled Flux, and verified the live workload health.
- Added a selective Collector metric transform for `service.name`,
  `service.namespace`, and `deployment.environment.name`. This enables
  per-service Prometheus queries without promoting high-cardinality process or
  instance resource attributes into labels.
- Verified live Tempo traces named `GET /api/health` under `vs-book-app` and
  Prometheus `http_server_request_duration_seconds_count` series labeled by
  service, route, method, status, namespace, and environment.

Progress on 2026-07-29:

- Diagnosed why Clean Mail error conditions produced no Homepage signal: Clean
  Mail metrics were arriving correctly, but every Prometheus rule was
  infrastructure-scoped, so `ALERTS` stayed empty.
- Found two semantic conventions live at once. Clean Mail (Python) exports
  `http_server_duration_milliseconds_*`; VS Book App (Node) exports
  `http_server_request_duration_seconds_*`. App rules match both by regex.
- Clean Mail exposes no `http_route` label, so app rules key on
  `service_name` and `http_status_code` only.
- Corrected two draft rules against live data before shipping:
  `cleanmail_gmail_watch_expiration_seconds` is seconds remaining, not an epoch
  timestamp (live value 536400), and cursor-age buckets place all normal traffic
  in the 750-1000s bucket, making any quantile threshold near 900 pure
  interpolation noise. The cursor rule now counts observations above the 2500s
  boundary instead.
- Verified every new expression against live Prometheus on `themachine`. All
  new rules evaluate empty on the current healthy fleet.
- Added ntfy delivery inside the existing action-runner alert webhook handler
  rather than a second Alertmanager receiver, because Alertmanager cannot
  template a webhook body and ntfy would otherwise publish raw JSON.
- Verified the ntfy formatter with an offline check covering severity mapping,
  resolved notifications, missing labels, and the unset-URL no-op.
- Applied the `action-runner-ntfy` secret on `themachine` and confirmed alert
  delivery end to end: a synthetic critical payload posted to
  `/alerts/webhook` returned `ok`, stored with no `ntfyError`, and arrived as a
  phone push.
- Noted an unrelated pre-existing trust-boundary detail while verifying:
  `actor()` accepts `x-authenticated-user-email` as a fallback to the
  Cloudflare Access header, so any in-cluster caller can self-assert admin on
  action-runner. Cloudflare Access gates the public hostname (unauthenticated
  POST returns 302), so this is not remotely exploitable. Tracked as optional
  hardening, not part of this work.

Progress on 2026-07-30:

- Found that the Phase 3b 5xx rules could only ever match `clean-mail-backend`.
  Clean Mail labels status as `http_status_code`; VS Book App uses
  `http_response_status_code`. Confirmed with
  `count by (service_name) ({...,http_status_code!=""})` returning only Clean
  Mail and the `http_response_status_code` variant returning only VS Book App.
  The rules never fired for VS Book App and never would have.
- Corrected an earlier claim: Clean Mail does expose a route label. It is
  `http_target`, not `http_route`, and the values are already templated
  (`/api/gmail/threads/{thread_id}`, `/api/senders/{sender}/route`), 12 series
  total, so per-route panels are safe.
- Confirmed `opentelemetry-instrumentation-{asgi,fastapi} 0.65b0` in the live
  Clean Mail image supports `OTEL_SEMCONV_STABILITY_OPT_IN` including
  `http/dup`, by reading `_semconv.py` in the running pod.
- Chose `http/dup` over `http` so no signal goes blind between the rule change
  and the pod restart. Costs a doubling of HTTP server metric series, 12 to 24.
- Verified Clean Mail traces are live in Tempo (`GET /api/triage` at 75ms), so
  Phase 4's Clean Mail instrumentation is further along than its checkbox shows.
- Validated every new rule and dashboard query against live Prometheus.
  `AppMissingStableHttpMetrics` currently returns one series,
  `clean-mail-backend`, which is the expected pre-rollout state and should clear
  once the backend restarts with the new env var.

Rollout verified on 2026-07-30 after merging PR #25:

- Self-review before merge caught two changes that rendered correctly and would
  then have silently not deployed. Prometheus rule files only reload on restart,
  and the live API confirmed the running instance still served the pre-3c
  `apps.rules` after the ConfigMap changed. Grafana dashboards mount with
  `subPath`, and `subPath` mounts never receive ConfigMap updates at all, so the
  new dashboard would never have appeared. Both deployments now carry a
  provisioning-version annotation that must be bumped on every change.
- Confirmed live: `apps.rules` includes `AppMissingStableHttpMetrics`, Grafana
  serves `services-red`, and the Clean Mail backend runs with
  `OTEL_SEMCONV_STABILITY_OPT_IN=http/dup`.
- Clean Mail stable metrics appeared within 30 seconds of the rollout with the
  same label shape as VS Book App: `http_route`, `http_response_status_code`,
  `http_request_method`. `http_route` values stay templated.
- `AppMissingStableHttpMetrics` cleared. Both services now appear in the Services
  RED picker. No alerts firing.
- The Homepage p95 card briefly read `NaN` right after the restart, because the
  5 minute rate window was younger than the metric series and bucket rates were
  non-monotonic. It settled to 72.5ms on its own. Left unguarded on purpose: a
  `>= 0` filter would hide a genuinely broken histogram behind a reassuring zero,
  and `or vector(0)` does not catch NaN since NaN is a value.

Doc refresh on 2026-07-30:

- Audited the whole plan against the live cluster rather than trusting the
  checkboxes. Every item in the original "Current gaps" list had been closed by
  Phases 1 through 3c, and Phases 5 and 6 were substantially done ahead of the
  plan without being recorded.
- Loki and Alloy are live, shipping pod logs from 9 namespaces, and Clean Mail
  log lines carry `trace_id`, so Phase 6 was effectively complete.
- Found `tracesToMetrics.datasourceUid: prometheus` against a datasource whose
  uid is `Prometheus`. Grafana uids are case-sensitive, so that link had been
  dead since it was written. Fixed, with the Grafana provisioning-version
  annotation bumped so the running pod actually picks it up.
- Rewrote "Current gaps" to list what is genuinely open instead of what was open
  when the plan was first written.

Progress on 2026-08-09:

- Reviewed the 24h feed after a ~22h Gmail push outage. Detection worked and
  notification worked; only the diagnosis was wrong for two days.
  `CleanMailGmailWatchExpiring` fired critical for 45.5h and pushed to ntfy four
  times, all with `ntfyError=None`.
- Root cause was not a stalled renewal job. The hourly job ran every tick and
  failed on a dead persistent OAuth grant for one of two Gmail accounts.
  `cleanmail_oauth_refresh_total{outcome="invalid_grant",purpose="background"}`
  reached 183 and `cleanmail_gmail_watch_renewals_total{outcome="failure"}`
  reached 11 while the completion log line read `outcome: success, renewed: 0`
  every hour. The expiry gauge is `min()` across accounts, so one dead account
  drove it to -21.9h while the other account stayed healthy.
- Added `CleanMailGmailWatchRenewalFailing` on the already-exported failure
  counter. Backtested over the incident: it would have fired from the start of
  the retained window through 08-08 23:43, roughly 12 hours before the watch
  gauge went negative, and cleared on its own when the grant was restored.
- Found Alertmanager was never a scrape target.
  `alertmanager_notifications_failed_total` existed on the pod and had no series
  in Prometheus, so no rule could watch the alert path. Annotated the Service
  for the existing `kubernetes-service-endpoints` job.
- Found ntfy delivery had failed silently on 08-06 between 08:51 and 10:51 with
  `<urlopen error [Errno -3] Try again>`, dropping nine notifications covering
  `KubernetesDeploymentUnavailable` and `KubernetesPodRestartSpike`. The failure
  was recorded only as an `ntfyError` string on an in-memory list. Added
  `action_runner_ntfy_publish_total` and an alert on it.
- Validated all three new expressions against live Prometheus before shipping.
  All evaluate empty on the current healthy fleet.

## Decisions

- 2026-08-09: Alert on the delivery path, not only on the things it carries.
  Both new pipeline rules describe a hop they cannot themselves page through —
  a dead ntfy hop cannot deliver news that ntfy is dead. They are still worth
  having: they surface on the Homepage alert count and in Grafana, where a
  silent delivery failure previously left no trace outside an in-memory field.
- 2026-08-09: Prefer alerting on an app's own failure counter over the gauge it
  eventually moves. `cleanmail_gmail_watch_renewals_total{outcome="failure"}`
  was already exported and unread; watching it buys ~2 days of lead time over
  the expiry gauge, and a gauge aggregated with `min()` across accounts hides
  which account is broken.

- 2026-07-31: Ship persistent host journals through the existing Alloy DaemonSet
  and alert on `node_boot_time_seconds` changes. This records hard-loss evidence
  after recovery without adding another host agent. The stack cannot alert while
  `themachine` itself is down; UPS telemetry remains a separate future addition.

- 2026-07-30: Audit specs against the live cluster before trusting their
  checkboxes. Three phases in this plan were materially out of date, in both
  directions: work marked open was done, and a broken datasource link sat behind
  a section that read as complete.
- 2026-07-30: Bump a pod-template provisioning-version annotation on every
  Prometheus rule and Grafana dashboard change. Prometheus does not re-read rule
  files without a restart, and Grafana's `subPath` dashboard mounts never see
  ConfigMap updates, so both fail silently and look deployed.
- 2026-07-30: Standardize on stable HTTP semantic conventions for all app
  metrics. Rules and dashboards target `http_server_request_duration_seconds`
  with `http_route` and `http_response_status_code` only. Supporting two
  conventions in every query is what hid the VS Book App alerting gap.
- 2026-07-30: Build one `Services RED` dashboard with a `service` template
  variable rather than a dashboard per app. Clean Mail's custom Gmail pipeline
  metrics get a single clearly labelled panel on it.
- 2026-07-30: Alert on the absence of stable HTTP metrics. A rule that matches
  nothing is indistinguishable from a healthy service, which is exactly how the
  Phase 3b gap stayed invisible.
- 2026-07-29: Route ntfy pushes through action-runner's existing
  `/alerts/webhook` handler instead of adding an Alertmanager receiver.
  Alertmanager has no body templating for webhooks, so a direct receiver would
  push unreadable JSON to the phone.
- 2026-07-29: Treat the ntfy.sh topic name as a credential. It lives in a
  manually applied `action-runner-ntfy` secret, never in git, and the
  `secretKeyRef` is optional so alert push degrades to a no-op when absent.
- 2026-07-29: Keep app alert rules generic on `service_name` rather than
  per-app, so newly instrumented apps inherit error and latency alerting with
  no rule changes.
- 2026-07-20: Keep Homepage as triage and Grafana as investigation.
- 2026-07-20: Prioritize Kubernetes metrics and alert visibility before deeper app instrumentation.
- 2026-07-20: Defer logs until there is a backend and a concrete use case.
- 2026-07-20: Use kube-state-metrics for Kubernetes health instead of broad pod scraping. Pod scraping is opt-in through annotations.
- 2026-07-21: Use Alertmanager to route first-pass notifications to action-runner as a low-noise internal receiver before adding push/email targets.
- 2026-07-21: Bridge Uptime Kuma monitor state into Prometheus through action-runner metrics instead of depending on hand-managed Uptime Kuma notification settings.
- 2026-07-21: Use Clean Mail and VS Book App as the first application
  observability targets. Start with HTTP traces and RED metrics; defer logs,
  sampling, and custom business metrics.
- 2026-07-21: Copy only stable, low-cardinality app identity resource
  attributes into metric datapoints before Prometheus export. Do not enable
  blanket resource-to-telemetry conversion because it can promote PID, host,
  process, and instance values into labels.
- 2026-07-21: Use Access-protected published hostnames for Grafana and Uptime
  Kuma browser access. Keep telemetry ingestion and storage internals private;
  make raw Prometheus UI exposure optional.
- 2026-07-21: Show root Flux Kustomization `lastReconciled` time on Homepage
  Fleet Sync card so routine scheduled runs remain visible even without a state
  transition or new Git revision.
- 2026-07-30: Exclude Cloudflare Access-protected dashboard and Clean Mail
  browser routes from Uptime Kuma until authenticated service-token probes exist.
- 2026-07-30: Keep Cloudflare-fronted public monitor history in Uptime Kuma,
  but exclude its `Public services` group from paging; only direct LAN and host
  monitor failures notify through Alertmanager/ntfy.
