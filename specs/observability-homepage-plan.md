# Observability Stack and Homepage Plan

Status: implementation in progress
Last updated: 2026-07-21

## Goal

Make the Grafana observability stack and Homepage observability section answer useful operational questions quickly:

- Is anything down or degraded?
- Which host or service is causing the problem?
- Did Flux apply the latest repo state?
- Are apps getting slower or erroring?
- Can a failing request be followed from metric spike to trace?
- What needs attention today?

## Current Baseline

Deployed on `themachine`:

- Prometheus with 30 day retention.
- Grafana with Prometheus and Tempo datasources.
- Tempo with 72 hour trace retention.
- OpenTelemetry Collector accepting OTLP gRPC/HTTP inside the cluster and through LAN NodePorts.
- Uptime Kuma with a `homelab` status page.
- Node exporter on `themachine` and `homeserver`.
- Homepage cards for host metrics, Uptime Kuma status, OpenTelemetry Explore, Fleet Sync, and app status checks.

Current gaps:

- Homepage observability cards are mostly links or broad summaries.
- OpenTelemetry card has a broken/missing icon in the screenshot.
- Grafana only has a host dashboard; no app/service RED dashboard.
- Prometheus has no Kubernetes pod/service scrape discovery.
- Collector receives traces/metrics, but hosted apps are not yet consistently instrumented.
- Alert rules and first-pass notification routing are source-controlled.
- No logs backend yet; log correlation should wait until a Loki or equivalent path exists.

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
- `Fleet Sync`: repo revision, applied revision, sync state, failed object count.
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
- [x] Route notifications to a low-noise target first.
- [x] Add Homepage alert count card.

### Phase 4 - Instrument Hosted Apps

- First target pair: Clean Mail and VS Book App. Either may land first.
- [x] Wire VS Book App locally with Node.js HTTP/Express auto-instrumentation,
  OTLP trace/metric export, stable HTTP semantic conventions, and explicit
  `service.name=vs-book-app` identity.
- [ ] Commit/push VS Book App changes, let its image workflow publish, update
  the pinned deployment image, and verify the Flux rollout.
- [ ] Verify VS Book App traces in Tempo and RED metrics in Prometheus against
  real cluster traffic.
- [ ] Finish Clean Mail instrumentation in its app session and apply the same
  end-to-end checks.
- Add app auto-instrumentation where practical:
  - HTTP server spans and `http.server.request.duration`.
  - HTTP client spans for external calls.
  - DB spans/metrics where each app has a database.
- Set `OTEL_SERVICE_NAME`, `OTEL_RESOURCE_ATTRIBUTES`, and OTLP endpoint in app manifests.
- Add manual spans only at external service boundaries or business-critical operations.
- Keep status route labels templated and low cardinality.

### Phase 5 - Metric to Trace Investigation

- Enable Grafana Tempo service graph/traces-to-metrics only after app traces exist.
- Add exemplar support if current Prometheus/Grafana/SDK path supports it cleanly.
- Add dashboard links from RED panels into Tempo searches by `service.name`, `http.route`, and status/error attributes.

### Phase 6 - Logs Later

- Add Loki only when there is a clear question metrics/traces do not answer.
- Use OTel appender/bridge or promtail/vector-style collection; do not duplicate `trace_id`/`span_id` into custom metric labels.
- Keep logs behind Cloudflare Access or LAN-only controls.

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
- Wired VS Book App locally with OpenTelemetry Node.js auto-instrumentation,
  OTLP/HTTP trace and metric exporters, stable HTTP semantic conventions, and
  production collector settings in its Kubernetes Deployment.
- Verified the VS Book App build, rendered Kubernetes manifests, and ran a
  local OTLP smoke test proving `vs-book-app` HTTP traces and
  `http.server.request.duration` metrics export. GitOps rollout remains pending.

## Decisions

- 2026-07-20: Keep Homepage as triage and Grafana as investigation.
- 2026-07-20: Prioritize Kubernetes metrics and alert visibility before deeper app instrumentation.
- 2026-07-20: Defer logs until there is a backend and a concrete use case.
- 2026-07-20: Use kube-state-metrics for Kubernetes health instead of broad pod scraping. Pod scraping is opt-in through annotations.
- 2026-07-21: Use Alertmanager to route first-pass notifications to action-runner as a low-noise internal receiver before adding push/email targets.
- 2026-07-21: Bridge Uptime Kuma monitor state into Prometheus through action-runner metrics instead of depending on hand-managed Uptime Kuma notification settings.
- 2026-07-21: Use Clean Mail and VS Book App as the first application
  observability targets. Start with HTTP traces and RED metrics; defer logs,
  sampling, and custom business metrics.
