# Monitoring & Operations — GateForge Methodology

> **Class B — Methodology.** This guide is variant-agnostic. For variant-specific runtime deltas, read the active adaptation file:
>
> - Multi-agent: [`../../adaptation/MULTI-AGENT-ADAPTATION.md`](../../adaptation/MULTI-AGENT-ADAPTATION.md)
> - Single-agent: [`../../adaptation/SINGLE-AGENT-ADAPTATION.md`](../../adaptation/SINGLE-AGENT-ADAPTATION.md)



| Field | Value |
|-------|-------|
| **Class** | B — Methodology |
| **Owner** | GateForge guideline maintainers |
| **Audience** | Any GateForge agent in the relevant phase, regardless of variant |
| **Read-with** | `BLUEPRINT-GUIDE.md`, the active variant's `SOUL.md`, and the active `adaptation/*.md` |
| **Document Status** | Active |

---

## Table of Contents

1. [System Monitoring Dashboard Setup](#1-system-monitoring-dashboard-setup)
2. [OS Resource Monitoring](#2-os-resource-monitoring)
3. [Application (Microservice) Monitoring](#3-application-microservice-monitoring)
4. [Database Monitoring](#4-database-monitoring)
5. [Alerting Baseline and Notification Channels](#5-alerting-baseline-and-notification-channels)
6. [Active Prevention — Proactive Scaling and Capacity Planning](#6-active-prevention--proactive-scaling-and-capacity-planning)
7. [Post-Deployment Monitoring Checklist](#7-post-deployment-monitoring-checklist)
8. [SLA/SLO Definitions](#8-slaslo-definitions)

---

## 1. System Monitoring Dashboard Setup

### 1.1 Monitoring Stack Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│                        US VM (Production)                            │
│                                                                      │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────────────┐    │
│  │ NestJS   │  │ NestJS   │  │ NestJS   │  │ React (Nginx)    │    │
│  │ Service A│  │ Service B│  │ Service C│  │ Frontend         │    │
│  │ :3001    │  │ :3002    │  │ :3003    │  │ :80              │    │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────────────┘    │
│       │ /metrics     │ /metrics    │ /metrics     │                  │
│       ▼              ▼             ▼              ▼                  │
│  ┌────────────────────────────────────────────────────────────────┐  │
│  │                    Prometheus  :9090                           │  │
│  │  scrape → store → evaluate rules → fire alerts                │  │
│  └───────┬──────────────────────────────────┬────────────────────┘  │
│          │                                  │                       │
│          ▼                                  ▼                       │
│  ┌───────────────┐                 ┌────────────────┐               │
│  │ Grafana :3000 │◄── datasource ──│ Loki    :3100  │               │
│  │ Dashboards    │                 │ Log aggregation│               │
│  └───────────────┘                 └────────────────┘               │
│          │                                  ▲                       │
│          │                                  │                       │
│  ┌───────────────┐                 ┌────────────────┐               │
│  │ Alertmanager  │                 │ Promtail       │               │
│  │ :9093         │                 │ Log collector  │               │
│  └───────┬───────┘                 └────────────────┘               │
│          │                                                          │
│          ├──→ Telegram Bot (the end-user)                                │
│          ├──→ Email Alerts                                          │
│          └──→ Webhook → Lobster Pipeline                            │
│                                                                      │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐              │
│  │ Node Exporter│  │ postgres_exp │  │ redis_exp    │              │
│  │ :9100        │  │ :9187        │  │ :9121        │              │
│  └──────────────┘  └──────────────┘  └──────────────┘              │
└──────────────────────────────────────────────────────────────────────┘
```

**Component roles:**

| Component        | Port  | Purpose                                          |
|------------------|-------|--------------------------------------------------|
| Prometheus       | 9090  | Time-series metrics collection, storage, alerting |
| Grafana          | 3000  | Visualization dashboards                          |
| Loki             | 3100  | Log aggregation (like Prometheus but for logs)    |
| Promtail         | —     | Log shipping agent (collects and forwards to Loki)|
| Alertmanager     | 9093  | Alert routing, dedup, grouping, silencing         |
| Node Exporter    | 9100  | OS / hardware metrics                             |
| postgres_exporter| 9187  | PostgreSQL metrics                                |
| redis_exporter   | 9121  | Redis metrics                                     |
| cAdvisor         | 8080  | Container-level resource metrics                  |

> **Source:** Architecture adapted from [Grafana's Docker Compose monitoring guide](https://grafana.com/docs/grafana-cloud/send-data/metrics/metrics-prometheus/prometheus-config-examples/docker-compose-linux/) and the community [docker-monitoring-stack](https://www.reddit.com/r/devops/comments/1fy4hy4/introducing_dockermonitoringstack_a_docker/) project.

### 1.2 Docker Compose Template — Full Monitoring Stack

```yaml
# docker-compose.monitoring.yml
# GateForge Monitoring Stack — Prometheus + Grafana + Loki + Alertmanager

version: "3.8"

networks:
  monitoring:
    driver: bridge
  app:
    external: true          # Shared with application stack

volumes:
  prometheus_data: {}
  grafana_data: {}
  loki_data: {}
  alertmanager_data: {}

services:
  # ── Prometheus ──────────────────────────────────────────────
  prometheus:
    image: prom/prometheus:v2.53.0
    container_name: gateforge-prometheus
    restart: unless-stopped
    user: "nobody"
    command:
      - "--config.file=/etc/prometheus/prometheus.yml"
      - "--storage.tsdb.path=/prometheus"
      - "--storage.tsdb.retention.time=30d"
      - "--storage.tsdb.retention.size=10GB"
      - "--web.console.libraries=/etc/prometheus/console_libraries"
      - "--web.console.templates=/etc/prometheus/consoles"
      - "--web.enable-lifecycle"
      - "--web.enable-admin-api"
    volumes:
      - ./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - ./prometheus/rules/:/etc/prometheus/rules/:ro
      - ./prometheus/targets/:/etc/prometheus/targets/:ro
      - prometheus_data:/prometheus
    ports:
      - "9090:9090"
    networks:
      - monitoring
      - app
    healthcheck:
      test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:9090/-/healthy"]
      interval: 15s
      timeout: 5s
      retries: 3

  # ── Alertmanager ────────────────────────────────────────────
  alertmanager:
    image: prom/alertmanager:v0.27.0
    container_name: gateforge-alertmanager
    restart: unless-stopped
    command:
      - "--config.file=/etc/alertmanager/alertmanager.yml"
      - "--storage.path=/alertmanager"
      - "--web.external-url=http://alertmanager:9093"
    volumes:
      - ./alertmanager/alertmanager.yml:/etc/alertmanager/alertmanager.yml:ro
      - ./alertmanager/templates/:/etc/alertmanager/templates/:ro
      - alertmanager_data:/alertmanager
    ports:
      - "9093:9093"
    networks:
      - monitoring
    healthcheck:
      test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:9093/-/healthy"]
      interval: 15s
      timeout: 5s
      retries: 3

  # ── Grafana ─────────────────────────────────────────────────
  grafana:
    image: grafana/grafana:11.1.0
    container_name: gateforge-grafana
    restart: unless-stopped
    environment:
      GF_SECURITY_ADMIN_USER: ${GRAFANA_ADMIN_USER:-admin}
      GF_SECURITY_ADMIN_PASSWORD: ${GRAFANA_ADMIN_PASSWORD}
      GF_USERS_ALLOW_SIGN_UP: "false"
      GF_SERVER_ROOT_URL: "https://grafana.gateforge.io"
      GF_INSTALL_PLUGINS: "grafana-clock-panel,grafana-piechart-panel"
    volumes:
      - grafana_data:/var/lib/grafana
      - ./grafana/provisioning/:/etc/grafana/provisioning/:ro
      - ./grafana/dashboards/:/var/lib/grafana/dashboards/:ro
    ports:
      - "3000:3000"
    networks:
      - monitoring
    depends_on:
      prometheus:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:3000/api/health"]
      interval: 15s
      timeout: 5s
      retries: 3

  # ── Loki ────────────────────────────────────────────────────
  loki:
    image: grafana/loki:3.1.0
    container_name: gateforge-loki
    restart: unless-stopped
    command: -config.file=/etc/loki/loki-config.yml
    volumes:
      - ./loki/loki-config.yml:/etc/loki/loki-config.yml:ro
      - loki_data:/loki
    ports:
      - "3100:3100"
    networks:
      - monitoring
    healthcheck:
      test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:3100/ready"]
      interval: 15s
      timeout: 5s
      retries: 3

  # ── Promtail ────────────────────────────────────────────────
  promtail:
    image: grafana/promtail:3.1.0
    container_name: gateforge-promtail
    restart: unless-stopped
    command: -config.file=/etc/promtail/promtail-config.yml
    volumes:
      - ./promtail/promtail-config.yml:/etc/promtail/promtail-config.yml:ro
      - /var/log:/var/log:ro
      - /var/lib/docker/containers:/var/lib/docker/containers:ro
    networks:
      - monitoring
    depends_on:
      - loki

  # ── Node Exporter ───────────────────────────────────────────
  node-exporter:
    image: prom/node-exporter:v1.8.2
    container_name: gateforge-node-exporter
    restart: unless-stopped
    command:
      - "--path.procfs=/host/proc"
      - "--path.rootfs=/rootfs"
      - "--path.sysfs=/host/sys"
      - "--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)"
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    network_mode: host
    pid: host

  # ── PostgreSQL Exporter ─────────────────────────────────────
  postgres-exporter:
    image: quay.io/prometheuscommunity/postgres-exporter:v0.15.0
    container_name: gateforge-postgres-exporter
    restart: unless-stopped
    environment:
      DATA_SOURCE_NAME: "postgresql://${PG_EXPORTER_USER}:${PG_EXPORTER_PASSWORD}@postgres:5432/gateforge?sslmode=disable"
    ports:
      - "9187:9187"
    networks:
      - monitoring
      - app

  # ── Redis Exporter ──────────────────────────────────────────
  redis-exporter:
    image: oliver006/redis_exporter:v1.62.0
    container_name: gateforge-redis-exporter
    restart: unless-stopped
    environment:
      REDIS_ADDR: "redis://redis:6379"
      REDIS_PASSWORD: "${REDIS_PASSWORD}"
    ports:
      - "9121:9121"
    networks:
      - monitoring
      - app

  # ── cAdvisor ────────────────────────────────────────────────
  cadvisor:
    image: gcr.io/cadvisor/cadvisor:v0.49.1
    container_name: gateforge-cadvisor
    restart: unless-stopped
    privileged: true
    devices:
      - /dev/kmsg:/dev/kmsg
    volumes:
      - /:/rootfs:ro
      - /var/run:/var/run:ro
      - /sys:/sys:ro
      - /var/lib/docker/:/var/lib/docker:ro
      - /dev/disk/:/dev/disk:ro
    ports:
      - "8080:8080"
    networks:
      - monitoring
```

> **Reference:** Docker Compose structure follows patterns from [Grafana Labs documentation](https://grafana.com/docs/grafana-cloud/send-data/metrics/metrics-prometheus/prometheus-config-examples/docker-compose-linux/) and [prom/node-exporter Docker Hub](https://hub.docker.com/r/prom/node-exporter).

### 1.3 Prometheus Configuration

#### `prometheus/prometheus.yml`

```yaml
# GateForge Prometheus Configuration
global:
  scrape_interval: 15s
  scrape_timeout: 10s
  evaluation_interval: 15s
  external_labels:
    cluster: "gateforge-production"
    environment: "production"

# Alertmanager integration
alerting:
  alertmanagers:
    - static_configs:
        - targets: ["alertmanager:9093"]

# Rule files (recording + alerting)
rule_files:
  - "/etc/prometheus/rules/*.yml"

# ── Scrape Configurations ──────────────────────────────────────
scrape_configs:

  # Self-monitoring
  - job_name: "prometheus"
    static_configs:
      - targets: ["localhost:9090"]
        labels:
          service: "prometheus"

  # ── Infrastructure ──────────────────────────────────────────
  - job_name: "node-exporter"
    scrape_interval: 15s
    static_configs:
      - targets: ["host.docker.internal:9100"]
        labels:
          service: "node-exporter"
          host: "us-vm-prod"

  - job_name: "cadvisor"
    scrape_interval: 15s
    static_configs:
      - targets: ["cadvisor:8080"]
        labels:
          service: "cadvisor"

  # ── Application Services ────────────────────────────────────
  - job_name: "gateforge-api-gateway"
    scrape_interval: 10s
    metrics_path: /metrics
    static_configs:
      - targets: ["api-gateway:3001"]
        labels:
          service: "api-gateway"
          tier: "frontend"

  - job_name: "gateforge-user-service"
    scrape_interval: 10s
    metrics_path: /metrics
    static_configs:
      - targets: ["user-service:3002"]
        labels:
          service: "user-service"
          tier: "backend"

  - job_name: "gateforge-order-service"
    scrape_interval: 10s
    metrics_path: /metrics
    static_configs:
      - targets: ["order-service:3003"]
        labels:
          service: "order-service"
          tier: "backend"

  - job_name: "gateforge-auth-service"
    scrape_interval: 10s
    metrics_path: /metrics
    static_configs:
      - targets: ["auth-service:3004"]
        labels:
          service: "auth-service"
          tier: "backend"

  - job_name: "gateforge-notification-service"
    scrape_interval: 15s
    metrics_path: /metrics
    static_configs:
      - targets: ["notification-service:3005"]
        labels:
          service: "notification-service"
          tier: "backend"

  # ── Database Exporters ──────────────────────────────────────
  - job_name: "postgres"
    scrape_interval: 15s
    static_configs:
      - targets: ["postgres-exporter:9187"]
        labels:
          service: "postgresql"
          database: "gateforge"

  - job_name: "redis"
    scrape_interval: 15s
    static_configs:
      - targets: ["redis-exporter:9121"]
        labels:
          service: "redis"

  # ── Nginx (Frontend) ────────────────────────────────────────
  - job_name: "nginx"
    scrape_interval: 15s
    static_configs:
      - targets: ["nginx-exporter:9113"]
        labels:
          service: "nginx"
          tier: "frontend"
```

#### Kubernetes Service Discovery (when migrating to K8s)

```yaml
# Alternative: Kubernetes SD for pod auto-discovery
scrape_configs:
  - job_name: "kubernetes-pods"
    kubernetes_sd_configs:
      - role: pod
        namespaces:
          names:
            - gateforge-production
            - gateforge-staging
    relabel_configs:
      # Only scrape pods annotated with prometheus.io/scrape: "true"
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
        action: keep
        regex: true
      # Custom metrics path from annotation
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_path]
        action: replace
        target_label: __metrics_path__
        regex: (.+)
      # Custom port from annotation
      - source_labels:
          - __address__
          - __meta_kubernetes_pod_annotation_prometheus_io_port
        action: replace
        regex: ([^:]+)(?::\d+)?;(\d+)
        replacement: $1:$2
        target_label: __address__
      # Metadata labels
      - source_labels: [__meta_kubernetes_namespace]
        action: replace
        target_label: namespace
      - source_labels: [__meta_kubernetes_pod_name]
        action: replace
        target_label: pod
      - source_labels: [__meta_kubernetes_pod_label_app]
        action: replace
        target_label: app
```

> **Source:** Kubernetes SD relabeling patterns from [OneUptime Prometheus Scrape Targets guide](https://oneuptime.com/blog/post/2026-02-02-prometheus-scrape-targets/view).

#### Retention & Storage Configuration

| Parameter                          | Value   | Notes                                |
|------------------------------------|---------|--------------------------------------|
| `storage.tsdb.retention.time`      | `30d`   | Keep 30 days of data                 |
| `storage.tsdb.retention.size`      | `10GB`  | Hard cap on TSDB disk usage          |
| `storage.tsdb.min-block-duration`  | `2h`    | Default, controls compaction         |
| `storage.tsdb.max-block-duration`  | `36h`   | Maximum before compaction            |
| `web.enable-lifecycle`             | `true`  | Allow hot-reload via `/-/reload`     |
| `web.enable-admin-api`             | `true`  | Enable admin endpoints for snapshots |

#### Recording Rules — `prometheus/rules/recording-rules.yml`

```yaml
# GateForge Recording Rules
# Pre-compute expensive queries for dashboard performance
groups:
  - name: gateforge_http_recording_rules
    interval: 30s
    rules:
      # Request rate per service (5m window)
      - record: gateforge:http_requests:rate5m
        expr: sum(rate(http_requests_total[5m])) by (service, method, status_code)

      # Error rate per service
      - record: gateforge:http_errors:rate5m
        expr: |
          sum(rate(http_requests_total{status_code=~"5.."}[5m])) by (service)
          /
          sum(rate(http_requests_total[5m])) by (service)

      # p95 latency per service
      - record: gateforge:http_request_duration_p95
        expr: histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket[5m])) by (le, service))

      # p99 latency per service
      - record: gateforge:http_request_duration_p99
        expr: histogram_quantile(0.99, sum(rate(http_request_duration_seconds_bucket[5m])) by (le, service))

  - name: gateforge_node_recording_rules
    interval: 30s
    rules:
      # CPU usage percentage
      - record: gateforge:node_cpu:usage_percent
        expr: 100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

      # Memory usage percentage
      - record: gateforge:node_memory:usage_percent
        expr: |
          (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100

      # Disk usage percentage
      - record: gateforge:node_disk:usage_percent
        expr: |
          (1 - (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"})) * 100

  - name: gateforge_database_recording_rules
    interval: 30s
    rules:
      # PostgreSQL cache hit ratio
      - record: gateforge:pg_cache_hit_ratio
        expr: |
          pg_stat_database_blks_hit{datname="gateforge"}
          /
          (pg_stat_database_blks_hit{datname="gateforge"} + pg_stat_database_blks_read{datname="gateforge"})

      # Redis hit rate
      - record: gateforge:redis_hit_rate
        expr: |
          rate(redis_keyspace_hits_total[5m])
          /
          (rate(redis_keyspace_hits_total[5m]) + rate(redis_keyspace_misses_total[5m]))
```

> **Source:** Recording rule structure follows [Chronosphere's guide on Prometheus recording rules](https://chronosphere.io/learn/prometheus-recording-rules-right-tool/) and [PromLabs training](https://training.promlabs.com/training/recording-rules/recording-rules-overview/configuring-recording-rules/).

### 1.4 Grafana Setup

#### Data Source Provisioning — `grafana/provisioning/datasources/datasources.yml`

```yaml
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: false
    jsonData:
      timeInterval: "15s"
      httpMethod: POST

  - name: Loki
    type: loki
    access: proxy
    url: http://loki:3100
    editable: false
    jsonData:
      maxLines: 1000

  - name: Alertmanager
    type: alertmanager
    access: proxy
    url: http://alertmanager:9093
    editable: false
    jsonData:
      implementation: prometheus
```

#### Dashboard Provisioning — `grafana/provisioning/dashboards/dashboards.yml`

```yaml
apiVersion: 1

providers:
  - name: "GateForge — Infrastructure"
    orgId: 1
    folder: "Infrastructure"
    type: file
    disableDeletion: false
    updateIntervalSeconds: 30
    options:
      path: /var/lib/grafana/dashboards/infrastructure
      foldersFromFilesStructure: true

  - name: "GateForge — Application Services"
    orgId: 1
    folder: "Application Services"
    type: file
    disableDeletion: false
    updateIntervalSeconds: 30
    options:
      path: /var/lib/grafana/dashboards/services
      foldersFromFilesStructure: true

  - name: "GateForge — Databases"
    orgId: 1
    folder: "Databases"
    type: file
    disableDeletion: false
    updateIntervalSeconds: 30
    options:
      path: /var/lib/grafana/dashboards/databases
      foldersFromFilesStructure: true

  - name: "GateForge — SLO & Business"
    orgId: 1
    folder: "SLO & Business"
    type: file
    disableDeletion: false
    updateIntervalSeconds: 30
    options:
      path: /var/lib/grafana/dashboards/slo
      foldersFromFilesStructure: true
```

#### Dashboard Organization

```
grafana/dashboards/
├── infrastructure/
│   ├── os-overview.json           # Node Exporter metrics
│   ├── container-overview.json    # cAdvisor container metrics
│   └── network-overview.json      # Network traffic and connections
├── services/
│   ├── api-gateway.json           # API gateway RED metrics
│   ├── user-service.json          # User service dashboard
│   ├── order-service.json         # Order service dashboard
│   ├── auth-service.json          # Auth service dashboard
│   └── services-overview.json     # All services summary
├── databases/
│   ├── postgresql-overview.json   # PostgreSQL health
│   └── redis-overview.json        # Redis health
└── slo/
    ├── availability-slo.json      # SLO burn rate dashboard
    └── business-metrics.json      # Business KPIs
```

#### Loki Configuration — `loki/loki-config.yml`

```yaml
auth_enabled: false

server:
  http_listen_port: 3100

common:
  path_prefix: /loki
  storage:
    filesystem:
      chunks_directory: /loki/chunks
      rules_directory: /loki/rules
  replication_factor: 1
  ring:
    kvstore:
      store: inmemory

schema_config:
  configs:
    - from: 2024-01-01
      store: tsdb
      object_store: filesystem
      schema: v13
      index:
        prefix: index_
        period: 24h

limits_config:
  retention_period: 30d
  max_query_length: 721h

ruler:
  alertmanager_url: http://alertmanager:9093
  storage:
    type: local
    local:
      directory: /loki/rules
  rule_path: /loki/rules-temp
  ring:
    kvstore:
      store: inmemory
  enable_api: true
```

#### Promtail Configuration — `promtail/promtail-config.yml`

```yaml
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /tmp/positions.yaml

clients:
  - url: http://loki:3100/loki/api/v1/push

scrape_configs:
  # Docker container logs
  - job_name: docker
    static_configs:
      - targets:
          - localhost
        labels:
          job: docker
          __path__: /var/lib/docker/containers/**/*.log
    pipeline_stages:
      - docker: {}
      - json:
          expressions:
            level: level
            service: service
      - labels:
          level:
          service:

  # System logs
  - job_name: syslog
    static_configs:
      - targets:
          - localhost
        labels:
          job: syslog
          __path__: /var/log/syslog
```

---

## 2. OS Resource Monitoring

### 2.1 CPU Metrics

| Metric | PromQL Query | Description | Warning | Critical |
|--------|-------------|-------------|---------|----------|
| Overall CPU usage | `100 - (avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)` | Total CPU utilization % | >70% | >85% |
| CPU by mode | `avg by (mode)(rate(node_cpu_seconds_total[5m])) * 100` | Breakdown: user, system, iowait, steal | — | — |
| User CPU | `avg(rate(node_cpu_seconds_total{mode="user"}[5m])) * 100` | Application-level CPU time | >60% | >75% |
| System CPU | `avg(rate(node_cpu_seconds_total{mode="system"}[5m])) * 100` | Kernel-level CPU time | >20% | >30% |
| I/O Wait | `avg(rate(node_cpu_seconds_total{mode="iowait"}[5m])) * 100` | CPU waiting on disk I/O | >10% | >20% |
| Per-core usage | `100 - (rate(node_cpu_seconds_total{mode="idle"}[5m]) * 100)` | Per-core utilization | >80% | >90% |
| Load average (1m) | `node_load1 / count(count by (cpu)(node_cpu_seconds_total{mode="idle"}))` | Normalized load average | >0.7 | >1.0 |

### 2.2 Memory Metrics

| Metric | PromQL Query | Warning | Critical |
|--------|-------------|---------|----------|
| Memory usage % | `(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100` | >75% | >90% |
| Available memory | `node_memory_MemAvailable_bytes` | <2GB | <500MB |
| Buffers + Cache | `node_memory_Buffers_bytes + node_memory_Cached_bytes` | — | — |
| Swap usage % | `(node_memory_SwapTotal_bytes - node_memory_SwapFree_bytes) / node_memory_SwapTotal_bytes * 100` | >10% | >50% |
| Swap in/out | `rate(node_vmstat_pswpin[5m])` / `rate(node_vmstat_pswpout[5m])` | >0 sustained | >100/s |

### 2.3 Disk I/O Metrics

| Metric | PromQL Query | Warning | Critical |
|--------|-------------|---------|----------|
| Disk utilization % | `rate(node_disk_io_time_seconds_total[5m]) * 100` | >70% | >90% |
| Read IOPS | `rate(node_disk_reads_completed_total[5m])` | — | — |
| Write IOPS | `rate(node_disk_writes_completed_total[5m])` | — | — |
| Read throughput | `rate(node_disk_read_bytes_total[5m])` | — | — |
| Write throughput | `rate(node_disk_written_bytes_total[5m])` | — | — |
| Read latency | `rate(node_disk_read_time_seconds_total[5m]) / rate(node_disk_reads_completed_total[5m])` | >10ms | >50ms |
| Write latency | `rate(node_disk_write_time_seconds_total[5m]) / rate(node_disk_writes_completed_total[5m])` | >10ms | >50ms |
| Filesystem usage % | `(1 - node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) * 100` | >80% | >90% |
| Filesystem free | `node_filesystem_avail_bytes{mountpoint="/"}` | <10GB | <2GB |

### 2.4 Network Metrics

| Metric | PromQL Query | Warning | Critical |
|--------|-------------|---------|----------|
| Bandwidth in | `rate(node_network_receive_bytes_total{device!="lo"}[5m]) * 8` | >70% cap | >90% cap |
| Bandwidth out | `rate(node_network_transmit_bytes_total{device!="lo"}[5m]) * 8` | >70% cap | >90% cap |
| Packet loss (rx errors) | `rate(node_network_receive_errs_total{device!="lo"}[5m])` | >0 | >10/s |
| Packet loss (tx errors) | `rate(node_network_transmit_errs_total{device!="lo"}[5m])` | >0 | >10/s |
| TCP connections | `node_netstat_Tcp_CurrEstab` | >5000 | >10000 |
| TCP TIME_WAIT | `node_sockstat_TCP_tw` | >5000 | >15000 |
| TCP connections by state | `node_tcp_connection_states` | — | — |

### 2.5 Node Exporter Configuration

The Node Exporter is deployed in `docker-compose.monitoring.yml` above. Key flags:

```bash
# Command flags for production deployment
--path.procfs=/host/proc
--path.rootfs=/rootfs
--path.sysfs=/host/sys
--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)
--collector.textfile.directory=/var/lib/node_exporter/textfile_collector
--no-collector.infiniband       # Disable unused collectors
--no-collector.nfs
--no-collector.nfsd
--web.listen-address=:9100
```

> **Reference:** Node Exporter Docker deployment follows [prom/node-exporter on Docker Hub](https://hub.docker.com/r/prom/node-exporter) best practices.

### 2.6 Grafana OS Overview Dashboard (JSON snippet)

```json
{
  "dashboard": {
    "title": "GateForge — OS Overview",
    "tags": ["gateforge", "infrastructure", "os"],
    "timezone": "browser",
    "refresh": "30s",
    "panels": [
      {
        "title": "CPU Usage %",
        "type": "timeseries",
        "gridPos": { "h": 8, "w": 12, "x": 0, "y": 0 },
        "targets": [
          {
            "expr": "gateforge:node_cpu:usage_percent",
            "legendFormat": "CPU Usage %"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "thresholds": {
              "steps": [
                { "value": 0, "color": "green" },
                { "value": 70, "color": "yellow" },
                { "value": 85, "color": "red" }
              ]
            },
            "unit": "percent",
            "max": 100
          }
        }
      },
      {
        "title": "Memory Usage %",
        "type": "gauge",
        "gridPos": { "h": 8, "w": 6, "x": 12, "y": 0 },
        "targets": [
          {
            "expr": "gateforge:node_memory:usage_percent",
            "legendFormat": "Memory %"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "thresholds": {
              "steps": [
                { "value": 0, "color": "green" },
                { "value": 75, "color": "yellow" },
                { "value": 90, "color": "red" }
              ]
            },
            "unit": "percent",
            "max": 100
          }
        }
      },
      {
        "title": "Disk Usage %",
        "type": "gauge",
        "gridPos": { "h": 8, "w": 6, "x": 18, "y": 0 },
        "targets": [
          {
            "expr": "gateforge:node_disk:usage_percent",
            "legendFormat": "Disk %"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "thresholds": {
              "steps": [
                { "value": 0, "color": "green" },
                { "value": 80, "color": "yellow" },
                { "value": 90, "color": "red" }
              ]
            },
            "unit": "percent",
            "max": 100
          }
        }
      },
      {
        "title": "Network I/O",
        "type": "timeseries",
        "gridPos": { "h": 8, "w": 12, "x": 0, "y": 8 },
        "targets": [
          {
            "expr": "rate(node_network_receive_bytes_total{device!='lo'}[5m])",
            "legendFormat": "Received ({{device}})"
          },
          {
            "expr": "rate(node_network_transmit_bytes_total{device!='lo'}[5m])",
            "legendFormat": "Transmitted ({{device}})"
          }
        ],
        "fieldConfig": {
          "defaults": { "unit": "Bps" }
        }
      },
      {
        "title": "Disk I/O Latency",
        "type": "timeseries",
        "gridPos": { "h": 8, "w": 12, "x": 12, "y": 8 },
        "targets": [
          {
            "expr": "rate(node_disk_read_time_seconds_total[5m]) / rate(node_disk_reads_completed_total[5m])",
            "legendFormat": "Read latency ({{device}})"
          },
          {
            "expr": "rate(node_disk_write_time_seconds_total[5m]) / rate(node_disk_writes_completed_total[5m])",
            "legendFormat": "Write latency ({{device}})"
          }
        ],
        "fieldConfig": {
          "defaults": { "unit": "s" }
        }
      }
    ]
  }
}
```

---

## 3. Application (Microservice) Monitoring

### 3.1 Methodology — RED Method & Golden Signals

**RED Method** (request-scoped services):

| Signal   | Definition                            | Metric                                               |
|----------|---------------------------------------|------------------------------------------------------|
| **R**ate    | Requests per second                   | `rate(http_requests_total[5m])`                      |
| **E**rror   | Errors per second / error ratio       | `rate(http_requests_total{status_code=~"5.."}[5m])`  |
| **D**uration| Latency distribution                  | `histogram_quantile(0.95, ...http_request_duration...)` |

**Google's Four Golden Signals** ([SRE Book](https://sre.google/sre-book/monitoring-distributed-systems/)):

| Signal       | What to measure                             |
|--------------|---------------------------------------------|
| **Latency**  | Time to serve a request (success vs error)  |
| **Traffic**  | Demand on the system (req/s, sessions)      |
| **Errors**   | Rate of failed requests                     |
| **Saturation** | How "full" the service is (queue depth, CPU) |

### 3.2 NestJS Prometheus Integration

#### Install dependencies

```bash
npm install prom-client @willsoto/nestjs-prometheus
```

#### Metrics Module — `src/metrics/metrics.module.ts`

```typescript
import { Module } from '@nestjs/common';
import { PrometheusModule } from '@willsoto/nestjs-prometheus';
import {
  makeCounterProvider,
  makeHistogramProvider,
  makeGaugeProvider,
} from '@willsoto/nestjs-prometheus';

@Module({
  imports: [
    PrometheusModule.register({
      path: '/metrics',
      defaultMetrics: {
        enabled: true,
        config: {
          prefix: 'gateforge_',
        },
      },
    }),
  ],
  providers: [
    // HTTP request counter
    makeCounterProvider({
      name: 'http_requests_total',
      help: 'Total number of HTTP requests',
      labelNames: ['method', 'route', 'status_code', 'service'],
    }),
    // HTTP request duration histogram
    makeHistogramProvider({
      name: 'http_request_duration_seconds',
      help: 'HTTP request duration in seconds',
      labelNames: ['method', 'route', 'status_code', 'service'],
      buckets: [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10],
    }),
    // Active connections gauge
    makeGaugeProvider({
      name: 'http_active_connections',
      help: 'Number of active HTTP connections',
      labelNames: ['service'],
    }),
    // Event loop lag gauge
    makeGaugeProvider({
      name: 'nodejs_eventloop_lag_seconds',
      help: 'Node.js event loop lag in seconds',
      labelNames: ['service'],
    }),
  ],
  exports: [PrometheusModule],
})
export class MetricsModule {}
```

> **Reference:** NestJS + Prometheus integration pattern from [@willsoto/nestjs-prometheus](https://dev.to/shinigami92/how-to-setup-prometheus-metrics-for-nestjs-graphql-67n) and [Shpota's NestJS monitoring guide](https://shpota.com/2024/10/22/monitoring-with-nestjs-prometheus-grafana.html).

#### Custom Prometheus Interceptor — `src/metrics/prometheus.interceptor.ts`

```typescript
import {
  Injectable,
  NestInterceptor,
  ExecutionContext,
  CallHandler,
} from '@nestjs/common';
import { Observable, tap } from 'rxjs';
import { InjectMetric } from '@willsoto/nestjs-prometheus';
import { Counter, Histogram, Gauge } from 'prom-client';

@Injectable()
export class PrometheusInterceptor implements NestInterceptor {
  private readonly serviceName: string;

  constructor(
    @InjectMetric('http_requests_total')
    private readonly requestCounter: Counter<string>,
    @InjectMetric('http_request_duration_seconds')
    private readonly requestDuration: Histogram<string>,
    @InjectMetric('http_active_connections')
    private readonly activeConnections: Gauge<string>,
  ) {
    this.serviceName = process.env.SERVICE_NAME || 'unknown';
  }

  intercept(context: ExecutionContext, next: CallHandler): Observable<any> {
    const request = context.switchToHttp().getRequest();
    const method = request.method;
    const route = request.route?.path || request.url;
    const startTime = Date.now();

    // Increment active connections
    this.activeConnections.inc({ service: this.serviceName });

    return next.handle().pipe(
      tap({
        next: () => {
          const response = context.switchToHttp().getResponse();
          const statusCode = response.statusCode.toString();
          const duration = (Date.now() - startTime) / 1000;

          this.requestCounter.inc({
            method,
            route,
            status_code: statusCode,
            service: this.serviceName,
          });
          this.requestDuration.observe(
            { method, route, status_code: statusCode, service: this.serviceName },
            duration,
          );
          this.activeConnections.dec({ service: this.serviceName });
        },
        error: (error) => {
          const statusCode = error.status?.toString() || '500';
          const duration = (Date.now() - startTime) / 1000;

          this.requestCounter.inc({
            method,
            route,
            status_code: statusCode,
            service: this.serviceName,
          });
          this.requestDuration.observe(
            { method, route, status_code: statusCode, service: this.serviceName },
            duration,
          );
          this.activeConnections.dec({ service: this.serviceName });
        },
      }),
    );
  }
}
```

#### Event Loop Lag Monitoring — `src/metrics/eventloop.service.ts`

```typescript
import { Injectable, OnModuleInit, OnModuleDestroy } from '@nestjs/common';
import { InjectMetric } from '@willsoto/nestjs-prometheus';
import { Gauge } from 'prom-client';
import { monitorEventLoopDelay } from 'perf_hooks';

@Injectable()
export class EventLoopService implements OnModuleInit, OnModuleDestroy {
  private histogram: ReturnType<typeof monitorEventLoopDelay>;
  private interval: NodeJS.Timeout;

  constructor(
    @InjectMetric('nodejs_eventloop_lag_seconds')
    private readonly eventLoopLag: Gauge<string>,
  ) {}

  onModuleInit() {
    this.histogram = monitorEventLoopDelay({ resolution: 20 });
    this.histogram.enable();

    this.interval = setInterval(() => {
      this.eventLoopLag.set(
        { service: process.env.SERVICE_NAME || 'unknown' },
        this.histogram.mean / 1e9, // Convert nanoseconds to seconds
      );
    }, 5000);
  }

  onModuleDestroy() {
    clearInterval(this.interval);
    this.histogram.disable();
  }
}
```

#### Custom Business Metrics — `src/metrics/business-metrics.service.ts`

```typescript
import { Injectable } from '@nestjs/common';
import { Counter, Gauge, Registry } from 'prom-client';

@Injectable()
export class BusinessMetricsService {
  public readonly ordersProcessed: Counter<string>;
  public readonly usersLoggedIn: Counter<string>;
  public readonly activeUsers: Gauge<string>;
  public readonly paymentAmount: Counter<string>;

  constructor(private readonly registry: Registry) {
    this.ordersProcessed = new Counter({
      name: 'gateforge_orders_processed_total',
      help: 'Total number of orders processed',
      labelNames: ['type', 'status', 'payment_method'],
      registers: [registry],
    });

    this.usersLoggedIn = new Counter({
      name: 'gateforge_user_logins_total',
      help: 'Total number of user login events',
      labelNames: ['method', 'status'],
      registers: [registry],
    });

    this.activeUsers = new Gauge({
      name: 'gateforge_active_users',
      help: 'Number of currently active users (via WebSocket or session)',
      registers: [registry],
    });

    this.paymentAmount = new Counter({
      name: 'gateforge_payment_amount_total',
      help: 'Total payment amount processed in cents',
      labelNames: ['currency', 'provider'],
      registers: [registry],
    });
  }
}
```

> **Source:** Custom metrics pattern adapted from [OneUptime's Node.js custom metrics guide](https://oneuptime.com/blog/post/2026-01-06-nodejs-custom-metrics-prometheus/view).

#### Register Globally — `src/main.ts`

```typescript
import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';
import { PrometheusInterceptor } from './metrics/prometheus.interceptor';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);

  // Global metrics interceptor
  const prometheusInterceptor = app.get(PrometheusInterceptor);
  app.useGlobalInterceptors(prometheusInterceptor);

  await app.listen(process.env.PORT || 3000);
}
bootstrap();
```

### 3.3 Key PromQL Queries — Application Metrics

| Metric | PromQL | Use Case |
|--------|--------|----------|
| Request rate by service | `sum(rate(http_requests_total[5m])) by (service)` | Traffic overview |
| Request rate by route | `sum(rate(http_requests_total[5m])) by (route, method)` | Hot path analysis |
| Error rate (%) | `sum(rate(http_requests_total{status_code=~"5.."}[5m])) by (service) / sum(rate(http_requests_total[5m])) by (service) * 100` | Error budget tracking |
| Error rate by status | `sum(rate(http_requests_total{status_code=~"[45].."}[5m])) by (status_code)` | Error breakdown |
| p50 latency | `histogram_quantile(0.50, sum(rate(http_request_duration_seconds_bucket[5m])) by (le, service))` | Median latency |
| p95 latency | `histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket[5m])) by (le, service))` | Tail latency |
| p99 latency | `histogram_quantile(0.99, sum(rate(http_request_duration_seconds_bucket[5m])) by (le, service))` | Worst-case latency |
| Active connections | `http_active_connections` | Current load |
| Event loop lag | `nodejs_eventloop_lag_seconds` | Node.js health |
| Orders per minute | `sum(rate(gateforge_orders_processed_total[5m])) * 60` | Business throughput |
| Login rate | `sum(rate(gateforge_user_logins_total[5m])) by (status)` | Auth monitoring |

### 3.4 Service-Level Grafana Dashboard Template

```json
{
  "dashboard": {
    "title": "GateForge — Service: {{service_name}}",
    "tags": ["gateforge", "service", "red"],
    "templating": {
      "list": [
        {
          "name": "service",
          "type": "query",
          "query": "label_values(http_requests_total, service)",
          "refresh": 2
        }
      ]
    },
    "panels": [
      {
        "title": "Request Rate (req/s)",
        "type": "timeseries",
        "gridPos": { "h": 8, "w": 8, "x": 0, "y": 0 },
        "targets": [
          {
            "expr": "sum(rate(http_requests_total{service=\"$service\"}[5m])) by (method)",
            "legendFormat": "{{method}}"
          }
        ]
      },
      {
        "title": "Error Rate (%)",
        "type": "timeseries",
        "gridPos": { "h": 8, "w": 8, "x": 8, "y": 0 },
        "targets": [
          {
            "expr": "sum(rate(http_requests_total{service=\"$service\",status_code=~\"5..\"}[5m])) / sum(rate(http_requests_total{service=\"$service\"}[5m])) * 100",
            "legendFormat": "Error %"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "thresholds": {
              "steps": [
                { "value": 0, "color": "green" },
                { "value": 1, "color": "yellow" },
                { "value": 5, "color": "red" }
              ]
            }
          }
        }
      },
      {
        "title": "Latency Percentiles",
        "type": "timeseries",
        "gridPos": { "h": 8, "w": 8, "x": 16, "y": 0 },
        "targets": [
          {
            "expr": "histogram_quantile(0.50, sum(rate(http_request_duration_seconds_bucket{service=\"$service\"}[5m])) by (le))",
            "legendFormat": "p50"
          },
          {
            "expr": "histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket{service=\"$service\"}[5m])) by (le))",
            "legendFormat": "p95"
          },
          {
            "expr": "histogram_quantile(0.99, sum(rate(http_request_duration_seconds_bucket{service=\"$service\"}[5m])) by (le))",
            "legendFormat": "p99"
          }
        ],
        "fieldConfig": {
          "defaults": { "unit": "s" }
        }
      },
      {
        "title": "Active Connections",
        "type": "stat",
        "gridPos": { "h": 4, "w": 6, "x": 0, "y": 8 },
        "targets": [
          {
            "expr": "http_active_connections{service=\"$service\"}",
            "legendFormat": "Connections"
          }
        ]
      },
      {
        "title": "Event Loop Lag",
        "type": "stat",
        "gridPos": { "h": 4, "w": 6, "x": 6, "y": 8 },
        "targets": [
          {
            "expr": "nodejs_eventloop_lag_seconds{service=\"$service\"}",
            "legendFormat": "Lag"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "unit": "s",
            "thresholds": {
              "steps": [
                { "value": 0, "color": "green" },
                { "value": 0.1, "color": "yellow" },
                { "value": 0.5, "color": "red" }
              ]
            }
          }
        }
      },
      {
        "title": "Request Rate by Route (Top 10)",
        "type": "table",
        "gridPos": { "h": 8, "w": 12, "x": 12, "y": 8 },
        "targets": [
          {
            "expr": "topk(10, sum(rate(http_requests_total{service=\"$service\"}[5m])) by (route, method))",
            "format": "table",
            "instant": true
          }
        ]
      }
    ]
  }
}
```

---

## 4. Database Monitoring

### 4.1 PostgreSQL Monitoring via `postgres_exporter`

#### Key Metrics and PromQL Queries

| Metric | PromQL Query | Healthy Range | Alert Threshold |
|--------|-------------|---------------|-----------------|
| Active connections | `pg_stat_activity_count{state="active"}` | <50% of max | >80% of `max_connections` |
| Connection utilization | `pg_stat_activity_count / pg_settings_max_connections * 100` | <70% | >80% |
| Transaction rate | `rate(pg_stat_database_xact_commit{datname="gateforge"}[5m]) + rate(pg_stat_database_xact_rollback{datname="gateforge"}[5m])` | Baseline ± 30% | Sudden spike or drop |
| Commit rate | `rate(pg_stat_database_xact_commit{datname="gateforge"}[5m])` | — | — |
| Rollback rate | `rate(pg_stat_database_xact_rollback{datname="gateforge"}[5m])` | Near 0 | >5/s |
| Cache hit ratio | `pg_stat_database_blks_hit{datname="gateforge"} / (pg_stat_database_blks_hit{datname="gateforge"} + pg_stat_database_blks_read{datname="gateforge"})` | >0.99 | <0.95 |
| Replication lag (bytes) | `pg_stat_replication_pg_wal_lsn_diff` | <1MB | >10MB |
| Replication lag (seconds) | `pg_replication_lag_seconds` | <1s | >10s |
| Dead tuples (bloat) | `pg_stat_user_tables_n_dead_tup` | Low | >10,000 per table |
| Last vacuum age | `time() - pg_stat_user_tables_last_autovacuum` | <1h | >24h |
| Slow queries | `pg_stat_statements_mean_time_seconds{quantile="0.95"}` | <100ms | >500ms |
| Lock contention | `pg_locks_count{mode="ExclusiveLock"}` | 0 | >5 sustained |
| Database size | `pg_database_size_bytes{datname="gateforge"}` | Trending | >80% disk |
| Temp files created | `rate(pg_stat_database_temp_bytes{datname="gateforge"}[5m])` | 0 | >0 sustained |

> **Source:** PostgreSQL monitoring metrics from [Sysdig's PostgreSQL monitoring guide](https://www.sysdig.com/blog/postgresql-monitoring) and [ComputingForGeeks](https://computingforgeeks.com/monitor-postgresql-prometheus-grafana/).

#### postgres_exporter Docker Configuration

```yaml
# Already included in docker-compose.monitoring.yml above
# Environment variable reference:
# DATA_SOURCE_NAME: "postgresql://exporter:password@postgres:5432/gateforge?sslmode=disable"
#
# Required PostgreSQL setup:
# CREATE USER exporter WITH PASSWORD 'secure_password';
# GRANT pg_monitor TO exporter;
# ALTER USER exporter SET search_path TO exporter, pg_catalog;
```

#### Enable `pg_stat_statements` (for slow query detection)

```sql
-- In postgresql.conf or via ALTER SYSTEM:
ALTER SYSTEM SET shared_preload_libraries = 'pg_stat_statements';
ALTER SYSTEM SET pg_stat_statements.track = 'all';
ALTER SYSTEM SET pg_stat_statements.max = 10000;

-- After restart:
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- Grant access to exporter user:
GRANT SELECT ON pg_stat_statements TO exporter;
```

### 4.2 Redis Monitoring via `redis_exporter`

#### Key Metrics and PromQL Queries

| Metric | PromQL Query | Healthy Range | Alert Threshold |
|--------|-------------|---------------|-----------------|
| Redis up | `redis_up` | 1 | != 1 |
| Memory usage | `redis_memory_used_bytes` | <75% maxmemory | >80% maxmemory |
| Memory utilization % | `redis_memory_used_bytes / redis_memory_max_bytes * 100` | <75% | >80% |
| Hit rate | `rate(redis_keyspace_hits_total[5m]) / (rate(redis_keyspace_hits_total[5m]) + rate(redis_keyspace_misses_total[5m]))` | >0.95 | <0.90 |
| Connected clients | `redis_connected_clients` | <1000 | >80% of maxclients |
| Evicted keys rate | `rate(redis_evicted_keys_total[5m])` | 0 | >0 sustained |
| Commands per second | `rate(redis_commands_processed_total[5m])` | Baseline ± 30% | Sudden drop |
| Rejected connections | `rate(redis_rejected_connections_total[5m])` | 0 | >0 |
| Replication lag | `redis_connected_slaves` / replication offset delta | In sync | >1s lag |
| Key count | `redis_db_keys` | Stable growth | Sudden spike |
| CPU usage | `rate(redis_cpu_user_seconds_total[5m]) + rate(redis_cpu_sys_seconds_total[5m])` | <70% | >90% |
| Network I/O | `rate(redis_net_input_bytes_total[5m])` + `rate(redis_net_output_bytes_total[5m])` | — | Saturated |
| Avg command latency | `rate(redis_commands_duration_seconds_total[5m]) / rate(redis_commands_total[5m])` | <1ms | >5ms |

> **Source:** Redis metrics reference from [Grafana Labs Redis exporter docs](https://grafana.com/docs/grafana-cloud/knowledge-graph/advanced-configuration/enable-prom-metrics-collection/data-stores/redis/) and [OneUptime Redis exporter setup guide](https://oneuptime.com/blog/post/2026-03-31-redis-how-to-set-up-redis-exporter-for-prometheus/view).

### 4.3 Database Alert Rules — `prometheus/rules/database-alerts.yml`

```yaml
groups:
  - name: postgresql_alerts
    rules:
      # Connection pool exhaustion
      - alert: PostgreSQLConnectionsHigh
        expr: pg_stat_activity_count / pg_settings_max_connections * 100 > 80
        for: 5m
        labels:
          severity: warning
          service: postgresql
        annotations:
          summary: "PostgreSQL connection usage >80%"
          description: "PostgreSQL connection pool at {{ $value | printf \"%.1f\" }}% capacity on {{ $labels.instance }}"

      - alert: PostgreSQLConnectionsCritical
        expr: pg_stat_activity_count / pg_settings_max_connections * 100 > 95
        for: 2m
        labels:
          severity: critical
          service: postgresql
        annotations:
          summary: "PostgreSQL connections near max"
          description: "PostgreSQL connection pool at {{ $value | printf \"%.1f\" }}% — risk of exhaustion"

      # Cache hit ratio
      - alert: PostgreSQLCacheHitLow
        expr: gateforge:pg_cache_hit_ratio < 0.95
        for: 10m
        labels:
          severity: warning
          service: postgresql
        annotations:
          summary: "PostgreSQL cache hit ratio below 95%"
          description: "Cache hit ratio at {{ $value | printf \"%.2f\" }} — consider increasing shared_buffers"

      # Replication lag
      - alert: PostgreSQLReplicationLag
        expr: pg_replication_lag_seconds > 10
        for: 5m
        labels:
          severity: critical
          service: postgresql
        annotations:
          summary: "PostgreSQL replication lag >10s"
          description: "Replication lag is {{ $value | printf \"%.1f\" }}s on {{ $labels.instance }}"

      # Dead tuples (bloat)
      - alert: PostgreSQLDeadTuples
        expr: pg_stat_user_tables_n_dead_tup > 100000
        for: 30m
        labels:
          severity: warning
          service: postgresql
        annotations:
          summary: "High dead tuple count"
          description: "Table {{ $labels.relname }} has {{ $value }} dead tuples — check autovacuum"

      # Slow queries
      - alert: PostgreSQLSlowQueries
        expr: pg_stat_statements_mean_time_seconds > 1
        for: 10m
        labels:
          severity: warning
          service: postgresql
        annotations:
          summary: "PostgreSQL slow queries detected"

  - name: redis_alerts
    rules:
      # Redis down
      - alert: RedisDown
        expr: redis_up != 1
        for: 1m
        labels:
          severity: critical
          service: redis
        annotations:
          summary: "Redis instance is DOWN"
          description: "Redis on {{ $labels.instance }} is unreachable"

      # Memory usage
      - alert: RedisMemoryHigh
        expr: redis_memory_used_bytes / redis_memory_max_bytes * 100 > 80
        for: 5m
        labels:
          severity: warning
          service: redis
        annotations:
          summary: "Redis memory >80%"
          description: "Redis memory at {{ $value | printf \"%.1f\" }}% — risk of eviction"

      # Hit rate
      - alert: RedisHitRateLow
        expr: gateforge:redis_hit_rate < 0.90
        for: 10m
        labels:
          severity: warning
          service: redis
        annotations:
          summary: "Redis hit rate below 90%"
          description: "Hit rate at {{ $value | printf \"%.2f\" }} — review caching strategy"

      # Evictions
      - alert: RedisEvictions
        expr: rate(redis_evicted_keys_total[5m]) > 0
        for: 5m
        labels:
          severity: warning
          service: redis
        annotations:
          summary: "Redis keys being evicted"
          description: "Eviction rate: {{ $value | printf \"%.1f\" }}/s — increase maxmemory or review key TTLs"

      # Rejected connections
      - alert: RedisRejectedConnections
        expr: rate(redis_rejected_connections_total[5m]) > 0
        for: 1m
        labels:
          severity: critical
          service: redis
        annotations:
          summary: "Redis rejecting connections"
          description: "Redis is rejecting connections — maxclients may be exhausted"
```

> **Source:** Alert rules adapted from [Grafana Labs Redis alerts reference](https://grafana.com/docs/grafana-cloud/knowledge-graph/advanced-configuration/enable-prom-metrics-collection/data-stores/redis/) and [Sysdig PostgreSQL monitoring](https://www.sysdig.com/blog/postgresql-monitoring).

---

## 5. Alerting Baseline and Notification Channels

### 5.1 Alert Severity Levels

| Level | Name | Response Time | Description | Examples |
|-------|------|---------------|-------------|----------|
| **P0** | CRITICAL | Immediate (<5 min) | Service down, data loss risk, security breach | Service unreachable, database corruption, replication failed |
| **P1** | HIGH | <15 minutes | Degraded performance, error spike, near-capacity | Error rate >5%, p95 >2s, disk >90% |
| **P2** | MEDIUM | <1 hour | Approaching threshold, performance degradation | CPU >85% trending up, cache hit dropping, connection pool >70% |
| **P3** | LOW | <4 hours / next business day | Informational, capacity planning | Disk growth trend, certificate expiry in 30d, dependency update |

### 5.2 Alert Rules — `prometheus/rules/alerting-rules.yml`

```yaml
groups:
  # ── Infrastructure Alerts ─────────────────────────────────────
  - name: infrastructure_alerts
    rules:
      # CPU
      - alert: HostHighCpuUsage
        expr: gateforge:node_cpu:usage_percent > 85
        for: 5m
        labels:
          severity: warning
          category: infrastructure
        annotations:
          summary: "Host CPU >85% for 5 minutes"
          description: "CPU usage at {{ $value | printf \"%.1f\" }}% on {{ $labels.instance }}"

      - alert: HostCriticalCpuUsage
        expr: gateforge:node_cpu:usage_percent > 95
        for: 2m
        labels:
          severity: critical
          category: infrastructure
        annotations:
          summary: "Host CPU >95%"
          description: "CPU at {{ $value | printf \"%.1f\" }}% — immediate action required"

      # Memory
      - alert: HostHighMemoryUsage
        expr: gateforge:node_memory:usage_percent > 90
        for: 5m
        labels:
          severity: warning
          category: infrastructure
        annotations:
          summary: "Host memory >90%"
          description: "Memory at {{ $value | printf \"%.1f\" }}% on {{ $labels.instance }}"

      - alert: HostCriticalMemoryUsage
        expr: gateforge:node_memory:usage_percent > 95
        for: 2m
        labels:
          severity: critical
          category: infrastructure
        annotations:
          summary: "Host memory >95%"
          description: "Memory at {{ $value | printf \"%.1f\" }}% — OOM risk"

      # Disk
      - alert: HostDiskSpaceWarning
        expr: gateforge:node_disk:usage_percent > 80
        for: 10m
        labels:
          severity: warning
          category: infrastructure
        annotations:
          summary: "Disk usage >80%"
          description: "Disk at {{ $value | printf \"%.1f\" }}% on {{ $labels.instance }}"

      - alert: HostDiskSpaceCritical
        expr: gateforge:node_disk:usage_percent > 90
        for: 5m
        labels:
          severity: critical
          category: infrastructure
        annotations:
          summary: "Disk usage >90%"
          description: "Disk at {{ $value | printf \"%.1f\" }}% — free space critically low"

      # Disk fill prediction
      - alert: HostDiskWillFillIn24h
        expr: predict_linear(node_filesystem_avail_bytes{mountpoint="/"}[6h], 24*3600) < 0
        for: 30m
        labels:
          severity: warning
          category: infrastructure
        annotations:
          summary: "Disk predicted to fill within 24 hours"
          description: "Based on 6h trend, disk {{ $labels.mountpoint }} will be full in ~24h"

      # Network
      - alert: HostNetworkErrors
        expr: rate(node_network_receive_errs_total[5m]) + rate(node_network_transmit_errs_total[5m]) > 10
        for: 5m
        labels:
          severity: warning
          category: infrastructure
        annotations:
          summary: "Network errors detected"
          description: "{{ $value | printf \"%.1f\" }} errors/s on {{ $labels.device }}"

  # ── Application Alerts ────────────────────────────────────────
  - name: application_alerts
    rules:
      # Error rate
      - alert: ServiceHighErrorRate
        expr: gateforge:http_errors:rate5m > 0.01
        for: 5m
        labels:
          severity: warning
          category: application
        annotations:
          summary: "Service {{ $labels.service }} error rate >1%"
          description: "Error rate at {{ $value | printf \"%.2f\" }}% for {{ $labels.service }}"

      - alert: ServiceCriticalErrorRate
        expr: gateforge:http_errors:rate5m > 0.05
        for: 2m
        labels:
          severity: critical
          category: application
        annotations:
          summary: "Service {{ $labels.service }} error rate >5%"
          description: "Error rate at {{ $value | printf \"%.2f\" }}% — service degraded"

      # 5xx spike
      - alert: Service5xxSpike
        expr: sum(rate(http_requests_total{status_code=~"5.."}[5m])) by (service) > 5
        for: 2m
        labels:
          severity: critical
          category: application
        annotations:
          summary: "5xx error spike for {{ $labels.service }}"
          description: "{{ $value | printf \"%.1f\" }} 5xx errors/s"

      # Latency
      - alert: ServiceHighLatencyP95
        expr: gateforge:http_request_duration_p95 > 0.5
        for: 5m
        labels:
          severity: warning
          category: application
        annotations:
          summary: "p95 latency >500ms for {{ $labels.service }}"
          description: "p95 at {{ $value | printf \"%.3f\" }}s"

      - alert: ServiceCriticalLatencyP99
        expr: gateforge:http_request_duration_p99 > 2
        for: 5m
        labels:
          severity: critical
          category: application
        annotations:
          summary: "p99 latency >2s for {{ $labels.service }}"
          description: "p99 at {{ $value | printf \"%.3f\" }}s — severely degraded"

      # Service down (no scrape data)
      - alert: ServiceDown
        expr: up{job=~"gateforge-.*"} == 0
        for: 1m
        labels:
          severity: critical
          category: application
        annotations:
          summary: "Service {{ $labels.job }} is DOWN"
          description: "Prometheus cannot scrape {{ $labels.instance }}"

      # Event loop lag
      - alert: NodejsEventLoopLag
        expr: nodejs_eventloop_lag_seconds > 0.5
        for: 2m
        labels:
          severity: warning
          category: application
        annotations:
          summary: "Node.js event loop lag >500ms"
          description: "Event loop lag at {{ $value | printf \"%.3f\" }}s for {{ $labels.service }}"

      # No traffic (potential issue)
      - alert: ServiceNoTraffic
        expr: sum(rate(http_requests_total[5m])) by (service) == 0
        for: 10m
        labels:
          severity: warning
          category: application
        annotations:
          summary: "No traffic to {{ $labels.service }}"
          description: "Zero requests for 10 minutes — check if service is healthy"
```

### 5.3 Alertmanager Configuration — `alertmanager/alertmanager.yml`

```yaml
# GateForge Alertmanager Configuration
global:
  resolve_timeout: 5m
  smtp_smarthost: "smtp.gmail.com:587"
  smtp_from: "gateforge-alerts@gateforge.io"
  smtp_auth_username: "${SMTP_USERNAME}"
  smtp_auth_password: "${SMTP_PASSWORD}"
  smtp_require_tls: true
  telegram_api_url: "https://api.telegram.org"

# Notification templates
templates:
  - "/etc/alertmanager/templates/*.tmpl"

# ── Routing Tree ──────────────────────────────────────────────────
route:
  receiver: "default-telegram"
  group_by: ["alertname", "service", "severity"]
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h

  routes:
    # P0 CRITICAL → Telegram + Email + Webhook (immediate)
    - receiver: "critical-all-channels"
      match:
        severity: critical
      group_wait: 10s
      group_interval: 1m
      repeat_interval: 15m
      continue: false

    # P1 HIGH → Telegram + Email
    - receiver: "high-telegram-email"
      match:
        severity: warning
      match_re:
        category: "application|infrastructure"
      group_wait: 30s
      repeat_interval: 1h
      continue: false

    # Database alerts → dedicated channel
    - receiver: "database-alerts"
      match:
        service: "postgresql|redis"
      group_wait: 30s
      repeat_interval: 2h

# ── Receivers ─────────────────────────────────────────────────────
receivers:
  # Default: Telegram only
  - name: "default-telegram"
    telegram_configs:
      - bot_token: "${TELEGRAM_BOT_TOKEN}"
        chat_id: ${TELEGRAM_CHAT_ID}
        parse_mode: "HTML"
        message: '{{ template "telegram.default" . }}'
        send_resolved: true

  # Critical: All channels
  - name: "critical-all-channels"
    telegram_configs:
      - bot_token: "${TELEGRAM_BOT_TOKEN}"
        chat_id: ${TELEGRAM_CHAT_ID}
        parse_mode: "HTML"
        message: '{{ template "telegram.critical" . }}'
        send_resolved: true
    email_configs:
      - to: "tonylnng@gmail.com"
        send_resolved: true
        headers:
          Subject: "[GateForge P0] {{ .GroupLabels.alertname }} — {{ .GroupLabels.service }}"
    webhook_configs:
      - url: "http://lobster-pipeline:8080/api/v1/webhooks/alertmanager"
        send_resolved: true
        max_alerts: 10

  # High: Telegram + Email
  - name: "high-telegram-email"
    telegram_configs:
      - bot_token: "${TELEGRAM_BOT_TOKEN}"
        chat_id: ${TELEGRAM_CHAT_ID}
        parse_mode: "HTML"
        message: '{{ template "telegram.default" . }}'
        send_resolved: true
    email_configs:
      - to: "tonylnng@gmail.com"
        send_resolved: true

  # Database-specific
  - name: "database-alerts"
    telegram_configs:
      - bot_token: "${TELEGRAM_BOT_TOKEN}"
        chat_id: ${TELEGRAM_DB_CHAT_ID}
        parse_mode: "HTML"
        message: '{{ template "telegram.default" . }}'
        send_resolved: true

# ── Inhibition Rules ──────────────────────────────────────────────
inhibit_rules:
  # If a critical alert is firing, suppress warnings for the same service
  - source_match:
      severity: "critical"
    target_match:
      severity: "warning"
    equal: ["alertname", "service"]

  # If the host is down, suppress all service-level alerts
  - source_match:
      alertname: "HostDown"
    target_match_re:
      category: "application|database"
    equal: ["instance"]
```

> **Source:** Alertmanager Telegram integration pattern from [GitHub Gist by sanchpet](https://gist.github.com/sanchpet/7641275a42243d3667b3146c5402be40) and [Charmhub Alertmanager guide](https://discourse.charmhub.io/t/integrating-with-an-alertmanager-receiver/13928).

### 5.4 Telegram Message Template — `alertmanager/templates/telegram.tmpl`

```go
{{ define "telegram.default" }}
{{ if gt (len .Alerts.Firing) 0 }}
🔥 <b>ALERTS FIRING ({{ len .Alerts.Firing }})</b>

{{ range .Alerts.Firing }}
<b>{{ .Labels.alertname }}</b>
{{ if eq .Labels.severity "critical" }}🚨 CRITICAL{{ end -}}
{{ if eq .Labels.severity "warning" }}⚠️ WARNING{{ end }}
{{ if .Labels.service }}Service: <code>{{ .Labels.service }}</code>{{ end }}
{{ if .Annotations.summary }}📝 {{ .Annotations.summary }}{{ end }}
{{ if .Annotations.description }}📖 {{ .Annotations.description }}{{ end }}
Started: {{ .StartsAt.Format "2006-01-02 15:04:05 MST" }}
---
{{ end }}
{{ end }}

{{ if gt (len .Alerts.Resolved) 0 }}
✅ <b>ALERTS RESOLVED ({{ len .Alerts.Resolved }})</b>

{{ range .Alerts.Resolved }}
<b>{{ .Labels.alertname }}</b> — {{ .Labels.service }}
Resolved: {{ .EndsAt.Format "2006-01-02 15:04:05 MST" }}
---
{{ end }}
{{ end }}

🏷️ Cluster: <code>gateforge-production</code>
🔗 <a href="http://grafana.gateforge.io:3000">Grafana</a> | <a href="http://prometheus.gateforge.io:9090">Prometheus</a>
{{ end }}

{{ define "telegram.critical" }}
🚨🚨🚨 <b>P0 CRITICAL ALERT</b> 🚨🚨🚨

{{ range .Alerts.Firing }}
<b>{{ .Labels.alertname }}</b>
Service: <code>{{ .Labels.service }}</code>
Instance: <code>{{ .Labels.instance }}</code>

{{ if .Annotations.summary }}📝 {{ .Annotations.summary }}{{ end }}
{{ if .Annotations.description }}📖 {{ .Annotations.description }}{{ end }}

Started: {{ .StartsAt.Format "2006-01-02 15:04:05 MST" }}
---
{{ end }}

⏰ <b>Immediate action required</b>
🔗 <a href="http://grafana.gateforge.io:3000">Dashboard</a> | <a href="http://alertmanager.gateforge.io:9093">Silence</a>

@end-user
{{ end }}
```

### 5.5 Silence and Maintenance Window Management

#### Create a silence (via API)

```bash
# Silence all alerts for a planned maintenance window (2 hours)
curl -X POST http://alertmanager:9093/api/v2/silences \
  -H "Content-Type: application/json" \
  -d '{
    "matchers": [
      {
        "name": "category",
        "value": "infrastructure",
        "isRegex": false
      }
    ],
    "startsAt": "2026-04-07T02:00:00Z",
    "endsAt": "2026-04-07T04:00:00Z",
    "createdBy": "operator-agent",
    "comment": "Planned maintenance: OS kernel upgrade"
  }'
```

#### Silence via Lobster pipeline task

```yaml
# lobster-pipeline/tasks/create-silence.yml
name: create-maintenance-silence
type: http
config:
  method: POST
  url: "http://alertmanager:9093/api/v2/silences"
  headers:
    Content-Type: "application/json"
  body:
    matchers:
      - name: "instance"
        value: "{{ .Params.instance }}"
        isRegex: false
    startsAt: "{{ .Params.start_time }}"
    endsAt: "{{ .Params.end_time }}"
    createdBy: "lobster-pipeline"
    comment: "{{ .Params.reason }}"
```

### 5.6 On-Call Escalation Policy

```
┌────────────────────────────────────────────────────────────┐
│                  Escalation Policy                          │
├────────────────────────────────────────────────────────────┤
│ Level 1: Automated (0–5 min)                               │
│   → Lobster pipeline runs automated remediation            │
│   → Auto-restart failed containers                         │
│   → Scale up if HPA trigger met                            │
│                                                            │
│ Level 2: Operator Agent (5–15 min)                         │
│   → Telegram alert to the end-user                              │
│   → Operator Agent assesses and reports to Architect (VM-1)│
│   → Automated rollback if deployment-related               │
│                                                            │
│ Level 3: System Architect (15–30 min)                      │
│   → VM-1 System Architect reviews and decides              │
│   → Email escalation if Telegram unacknowledged            │
│                                                            │
│ Level 4: Human Escalation (30+ min)                        │
│   → Phone call / urgent contact to the end-user                 │
│   → Full incident war room                                 │
│   → Maximum 3 retries per automated action before human    │
│     escalation (per GateForge SDLC constraints)            │
└────────────────────────────────────────────────────────────┘
```

### 5.7 Alert Deduplication and Grouping

| Setting            | Value   | Purpose                                               |
|--------------------|---------|-------------------------------------------------------|
| `group_by`         | `["alertname", "service", "severity"]` | Group related alerts together |
| `group_wait`       | `30s`   | Wait before sending first notification for a group    |
| `group_interval`   | `5m`    | Wait before sending updated notifications             |
| `repeat_interval`  | `4h`    | Resend unresolved alert after this period              |
| Inhibition         | Critical suppresses Warning for same alertname+service | Reduce noise |

---

## 6. Active Prevention — Proactive Scaling and Capacity Planning

### 6.1 Usage Trend Analysis

#### Key PromQL Forecasting Queries

```promql
# Predict disk full in N hours (linear regression on 7d data)
predict_linear(node_filesystem_avail_bytes{mountpoint="/"}[7d], 30*24*3600) < 0

# Memory trend — will exceed 90% within 24h?
predict_linear(
  (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)[6h:5m],
  24*3600
) > 0.90

# Request growth rate over 7 days
(sum(rate(http_requests_total[1h])) - sum(rate(http_requests_total[1h] offset 7d)))
/ sum(rate(http_requests_total[1h] offset 7d)) * 100

# Database size growth prediction (30d out)
predict_linear(pg_database_size_bytes{datname="gateforge"}[30d], 90*24*3600)
```

### 6.2 Capacity Forecasting Methodology

| Method | Input Data | Forecast Period | Use Case |
|--------|-----------|-----------------|----------|
| **Linear regression** | `predict_linear()` in PromQL | 7–90 days | Disk, memory, DB size growth |
| **Seasonal analysis** | Weekly pattern overlay | 1 week | Traffic-based scaling (business hours) |
| **Growth rate** | Week-over-week / month-over-month delta | 1–6 months | Capacity planning |
| **Percentile analysis** | p95/p99 of peak usage over 30d | Next peak | Right-sizing resource limits |

#### Weekly Capacity Review Checklist

- [ ] Current resource utilization vs limits (CPU, memory, disk)
- [ ] Growth rate: compare this week's peak to last week
- [ ] Disk space: days until full at current growth rate
- [ ] Database size trend: predict next 30/60/90 days
- [ ] Connection pool headroom: current vs max
- [ ] Cost per service: resource allocation efficiency
- [ ] SLO burn rate: are we consuming error budget faster than expected?

### 6.3 Leading vs Lagging Indicators

| Type | Indicator | Action |
|------|-----------|--------|
| **Leading** | Queue depth increasing | Scale before latency degrades |
| **Leading** | Event loop lag rising | Investigate before errors spike |
| **Leading** | Connection pool usage trending up | Add capacity before saturation |
| **Leading** | CPU sustained >70% for 15min | Trigger horizontal scale-out |
| **Leading** | `predict_linear()` disk full in 7d | Provision storage |
| **Lagging** | Error rate spike | Already impacting users |
| **Lagging** | p99 latency exceeding SLO | SLO budget burning |
| **Lagging** | OOM kill events | Too late for graceful handling |

### 6.4 Horizontal Scaling Triggers

| Trigger | Threshold | Duration | Action |
|---------|-----------|----------|--------|
| CPU utilization | >70% | 15 min sustained | Add pod replicas |
| Memory utilization | >75% | 10 min sustained | Add pod replicas |
| Request queue depth | Increasing trend for 5min | — | Scale up |
| p95 latency exceeding SLO | >500ms | 5 min | Scale up |
| Event loop lag | >200ms | 5 min | Scale up (Node.js specific) |
| Active connections per pod | >500 | 10 min | Scale up |

### 6.5 Kubernetes HPA with Custom Metrics

#### Prerequisites: Prometheus Adapter

```yaml
# prometheus-adapter-values.yml (Helm)
prometheus:
  url: http://prometheus.monitoring.svc.cluster.local
  port: 9090

replicas: 2

rules:
  default: true
  custom:
    # HTTP request rate per pod
    - seriesQuery: 'http_requests_total{namespace!="",pod!=""}'
      resources:
        overrides:
          namespace: { resource: namespace }
          pod: { resource: pod }
      name:
        as: "http_requests_per_second"
      metricsQuery: 'sum(rate(<<.Series>>{<<.LabelMatchers>>}[2m])) by (<<.GroupBy>>)'

    # Event loop lag
    - seriesQuery: 'nodejs_eventloop_lag_seconds{namespace!="",pod!=""}'
      resources:
        overrides:
          namespace: { resource: namespace }
          pod: { resource: pod }
      name:
        as: "eventloop_lag"
      metricsQuery: 'avg(<<.Series>>{<<.LabelMatchers>>}) by (<<.GroupBy>>)'

    # Active connections
    - seriesQuery: 'http_active_connections{namespace!="",pod!=""}'
      resources:
        overrides:
          namespace: { resource: namespace }
          pod: { resource: pod }
      name:
        as: "active_connections"
      metricsQuery: 'avg(<<.Series>>{<<.LabelMatchers>>}) by (<<.GroupBy>>)'
```

> **Source:** Prometheus Adapter custom metrics configuration based on [LiveWyer's Kubernetes scaling guide](https://livewyer.io/blog/set-up-kubernetes-scaling-via-prometheus-custom-metrics/) and [BigBinary's prometheus-adapter guide](https://www.bigbinary.com/blog/prometheus-adapter).

#### Install via Helm

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install prometheus-adapter prometheus-community/prometheus-adapter \
  -n monitoring \
  -f prometheus-adapter-values.yml
```

#### HPA Configuration per Service

```yaml
# k8s/hpa/api-gateway-hpa.yml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: api-gateway-hpa
  namespace: gateforge-production
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: api-gateway
  minReplicas: 2
  maxReplicas: 10
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 60
      policies:
        - type: Pods
          value: 2
          periodSeconds: 60
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
        - type: Pods
          value: 1
          periodSeconds: 120
  metrics:
    # CPU-based scaling
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70

    # Memory-based scaling
    - type: Resource
      resource:
        name: memory
        target:
          type: Utilization
          averageUtilization: 75

    # Custom: Request rate per pod
    - type: Pods
      pods:
        metric:
          name: http_requests_per_second
        target:
          type: AverageValue
          averageValue: "100"

    # Custom: Event loop lag
    - type: Pods
      pods:
        metric:
          name: eventloop_lag
        target:
          type: AverageValue
          averageValue: "200m"  # 200ms
```

> **Source:** HPA custom metrics pattern from [OneUptime Prometheus Adapter guide](https://oneuptime.com/blog/post/2026-03-13-prometheus-adapter-custom-metrics-hpa-flux-cd/view).

### 6.6 Resource Requests vs Limits — Right-Sizing

```yaml
# k8s/deployments/api-gateway.yml (resource section)
resources:
  requests:
    cpu: "250m"      # Guaranteed CPU
    memory: "256Mi"  # Guaranteed memory
  limits:
    cpu: "1000m"     # Max CPU burst
    memory: "512Mi"  # Max memory (OOM kill if exceeded)
```

**Right-sizing methodology:**

1. Collect p95 and p99 resource usage over 7 days
2. Set `requests` = p95 usage + 20% buffer
3. Set `limits` = p99 usage + 50% buffer
4. Review monthly; adjust after load testing

### 6.7 Cost Optimization Checklist

- [ ] Identify over-provisioned pods (limits >> actual p99 usage)
- [ ] Reduce replicas for low-traffic services during off-hours
- [ ] Use `scaleDown.stabilizationWindowSeconds` to avoid thrashing
- [ ] Consolidate small services onto fewer nodes
- [ ] Use spot/preemptible instances for non-critical workloads
- [ ] Set appropriate `PriorityClass` for critical vs best-effort pods

### 6.8 Database Scaling Triggers

| Condition | Threshold | Action |
|-----------|-----------|--------|
| Read query latency increasing | p95 >100ms for 15min | Add read replica |
| Connection pool at capacity | >80% of max_connections | Increase pool size or add PgBouncer |
| Replication lag growing | >5s for 10min | Investigate replica health |
| Redis memory near maxmemory | >85% | Increase maxmemory or add shard |
| Redis evictions occurring | >0 sustained | Increase maxmemory |
| Database size growth rate | >10% month-over-month | Plan storage expansion |

### 6.9 Pre-Scaling for Known Traffic Patterns

```yaml
# k8s/cronjob/pre-scale.yml
# Scale up 30 minutes before known peak (e.g., business hours HKT 09:00)
apiVersion: batch/v1
kind: CronJob
metadata:
  name: pre-scale-business-hours
  namespace: gateforge-production
spec:
  schedule: "30 0 * * 1-5"  # 08:30 HKT (00:30 UTC) weekdays
  jobTemplate:
    spec:
      template:
        spec:
          containers:
            - name: kubectl
              image: bitnami/kubectl:latest
              command:
                - /bin/sh
                - -c
                - |
                  kubectl scale deployment api-gateway --replicas=4
                  kubectl scale deployment user-service --replicas=3
                  kubectl scale deployment order-service --replicas=3
          restartPolicy: OnFailure

---
# Scale back down after business hours
apiVersion: batch/v1
kind: CronJob
metadata:
  name: scale-down-off-hours
  namespace: gateforge-production
spec:
  schedule: "0 14 * * 1-5"  # 22:00 HKT (14:00 UTC) weekdays
  jobTemplate:
    spec:
      template:
        spec:
          containers:
            - name: kubectl
              image: bitnami/kubectl:latest
              command:
                - /bin/sh
                - -c
                - |
                  kubectl scale deployment api-gateway --replicas=2
                  kubectl scale deployment user-service --replicas=2
                  kubectl scale deployment order-service --replicas=2
          restartPolicy: OnFailure
```

### 6.10 Load Testing Baseline

| Item | Schedule | Tool | Target |
|------|----------|------|--------|
| Baseline load test | Every major release | k6 / Artillery | Establish p95 latency baseline |
| Stress test | Monthly | k6 | Find breaking point |
| Soak test | Quarterly | k6 (12h run) | Memory leaks, connection leaks |
| Spike test | Before product launch | k6 | Validate auto-scaling response |

**Re-test triggers:**
- After infrastructure changes (VM resize, new node pool)
- After database schema changes
- After new service deployment
- After dependency upgrades (NestJS, Node.js version)

---

## 7. Post-Deployment Monitoring Checklist

### 7.1 15-Minute Post-Deploy Protocol

Execute this protocol immediately after every deployment. The Operator agent must monitor for 15 minutes before marking a deployment as stable (per [SOUL.md constraints](./SOUL.md)).

```
T+0:00  ─── Deployment Executed ──────────────────────────────────
  □ Verify all containers started successfully
    └─ docker compose ps | grep -v "Up"  (should be empty)
  □ Confirm new image version is running
    └─ docker inspect <container> | jq '.[0].Config.Image'
  □ Check container logs for startup errors
    └─ docker compose logs --tail=50 <service>

T+0:01  ─── Health Checks ────────────────────────────────────────
  □ Hit /health endpoint for each service
  □ Verify Prometheus scrape targets are UP
    └─ curl http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.health != "up")'
  □ Run smoke test suite (see 7.2)

T+0:02  ─── Core Metrics Baseline ────────────────────────────────
  □ Compare current error rate to pre-deploy baseline
  □ Compare p95 latency to pre-deploy baseline
  □ Check for any new 5xx responses
  □ Verify request rate is in expected range

T+0:05  ─── Deep Health Check ────────────────────────────────────
  □ Database connections: within normal range?
  □ Redis hit rate: stable?
  □ Event loop lag: within baseline?
  □ Memory usage: not climbing abnormally?
  □ No new alerts firing in Alertmanager

T+0:10  ─── Functional Validation ────────────────────────────────
  □ Core user flows working (login, primary actions)
  □ API responses returning expected data shapes
  □ WebSocket connections stable (if applicable)

T+0:15  ─── Final Assessment ─────────────────────────────────────
  □ All metrics within acceptable thresholds
  □ No rollback triggers met (see 7.3)
  □ Mark deployment as STABLE or ROLLBACK

  ✅ Outcome: { stable | needs-investigation | rollback }
```

### 7.2 Smoke Test Automation

```bash
#!/bin/bash
# smoke-test.sh — Post-deployment smoke tests
# Exit on first failure
set -e

BASE_URL="${1:-http://localhost:3001}"
PASS=0
FAIL=0

check() {
  local name="$1"
  local url="$2"
  local expected_status="${3:-200}"

  status=$(curl -s -o /dev/null -w "%{http_code}" "$url" --max-time 10)
  if [ "$status" = "$expected_status" ]; then
    echo "✅ PASS: $name (HTTP $status)"
    ((PASS++))
  else
    echo "❌ FAIL: $name (expected $expected_status, got $status)"
    ((FAIL++))
  fi
}

echo "═══════════════════════════════════════════"
echo "  GateForge Post-Deploy Smoke Tests"
echo "═══════════════════════════════════════════"
echo ""

# Health endpoints
check "API Gateway Health"         "$BASE_URL/health"
check "User Service Health"        "http://localhost:3002/health"
check "Order Service Health"       "http://localhost:3003/health"
check "Auth Service Health"        "http://localhost:3004/health"

# Metrics endpoints (for Prometheus)
check "API Gateway Metrics"        "$BASE_URL/metrics"
check "User Service Metrics"       "http://localhost:3002/metrics"

# Core API validation
check "GET /api/v1/status"         "$BASE_URL/api/v1/status"

# Database connectivity (via service)
check "DB Connection Check"        "$BASE_URL/api/v1/health/db"
check "Redis Connection Check"     "$BASE_URL/api/v1/health/redis"

echo ""
echo "═══════════════════════════════════════════"
echo "  Results: $PASS passed, $FAIL failed"
echo "═══════════════════════════════════════════"

if [ "$FAIL" -gt 0 ]; then
  echo "🚨 SMOKE TESTS FAILED — Initiate rollback assessment"
  exit 1
fi

echo "✅ All smoke tests passed"
exit 0
```

### 7.3 Rollback Trigger Criteria

A rollback MUST be initiated if ANY of the following conditions are met within the 15-minute observation window:

| Trigger | Threshold | Auto-Rollback? |
|---------|-----------|----------------|
| Any service fails health check | After 3 retries (30s apart) | Yes |
| Error rate (5xx) | >5% for 2 minutes | Yes |
| p95 latency | >3x pre-deploy baseline for 5min | Yes |
| Smoke test failure | Any critical path fails | Yes |
| Container crash loop | >3 restarts in 5 minutes | Yes |
| Memory usage | Climbing >5% per minute (leak) | Manual assessment |
| Database connection errors | Any new connection failures | Manual assessment |
| Business metric anomaly | Orders/logins dropped >50% | Manual assessment |

**Rollback command:**

```bash
# Standard rollback (per SOUL.md)
ssh user@tonic.sailfish-bass.ts.net \
  "cd /opt/app && docker compose down && docker compose -f docker-compose.rollback.yml up -d"
```

### 7.4 Deployment Metrics

Track these metrics for each deployment in the `decision-log.md`:

```json
{
  "deploymentId": "DEPLOY-2026-04-07-001",
  "version": "v1.5.2",
  "environment": "production",
  "strategy": "rolling",
  "startTime": "2026-04-07T01:00:00Z",
  "endTime": "2026-04-07T01:15:00Z",
  "status": "stable",
  "metrics": {
    "deployDurationSeconds": 120,
    "smokeTestResult": "pass",
    "smokeTestDurationSeconds": 45,
    "errorRateDuringDeploy": 0.001,
    "p95LatencyDuringDeploy": 0.23,
    "rollbackTriggered": false,
    "containerRestarts": 0
  },
  "approvedBy": "system-architect-vm1",
  "monitoredBy": "operator-vm5"
}
```

### 7.5 Release Health Dashboard

Create a dedicated Grafana dashboard that shows deployment events overlaid on metrics:

| Panel | PromQL / Query | Purpose |
|-------|---------------|---------|
| Deploy annotations | Grafana annotations API | Vertical lines on all charts |
| Error rate (before/after) | `gateforge:http_errors:rate5m` | Compare pre/post deploy |
| p95 latency (before/after) | `gateforge:http_request_duration_p95` | Detect latency regression |
| Container restarts | `rate(kube_pod_container_status_restarts_total[5m])` | Crash detection |
| Request rate delta | `sum(rate(http_requests_total[5m])) - sum(rate(http_requests_total[5m] offset 1h))` | Traffic comparison |

---

## 8. SLA/SLO Definitions

### 8.1 Service Level Indicator (SLI) Mapping

| SLI | Definition | Metric | Measurement Window |
|-----|-----------|--------|-------------------|
| **Availability** | Proportion of successful requests | `1 - (rate(http_requests_total{status_code=~"5.."}[30d]) / rate(http_requests_total[30d]))` | 30-day rolling |
| **Latency** | Proportion of requests faster than threshold | `histogram_quantile(0.95, ...) < 500ms` | 30-day rolling |
| **Correctness** | Proportion of requests returning correct data | Custom business validation metric | 30-day rolling |
| **Freshness** | Data staleness (for async systems) | Cache age, replication lag | Continuous |

### 8.2 Service Level Objective (SLO) Targets

| Service | SLO Type | Target | SLI Metric |
|---------|----------|--------|------------|
| API Gateway | Availability | 99.9% (43.8 min/month downtime) | Successful requests / total requests |
| API Gateway | Latency (p95) | <500ms | 95th percentile response time |
| API Gateway | Latency (p99) | <2s | 99th percentile response time |
| User Service | Availability | 99.9% | Successful requests / total requests |
| Order Service | Availability | 99.95% (21.9 min/month) | Successful requests / total requests |
| Auth Service | Availability | 99.99% (4.3 min/month) | Successful requests / total requests |
| PostgreSQL | Availability | 99.99% | `pg_up == 1` uptime |
| Redis | Availability | 99.9% | `redis_up == 1` uptime |
| Overall Platform | Availability | 99.9% | Composite of all services |

### 8.3 Error Budget Calculation

```
Error Budget = 1 - SLO Target

Example for 99.9% SLO:
  Error Budget     = 1 - 0.999 = 0.001 (0.1%)
  Monthly budget   = 30 days × 24h × 60min × 0.001 = 43.2 minutes
  Weekly budget    = 7 days × 24h × 60min × 0.001 = 10.08 minutes

Budget consumed this period:
  consumed = (total_failed_requests / total_requests)
  remaining_budget = error_budget - consumed
  burn_rate = consumed / (elapsed_time / total_window)
```

#### PromQL — Error Budget Queries

```promql
# Total error budget (30d window, 99.9% SLO)
# Remaining budget as percentage
(1 - (
  sum(rate(http_requests_total{status_code=~"5.."}[30d]))
  /
  sum(rate(http_requests_total[30d]))
)) / 0.001 * 100

# Burn rate (how fast we're consuming budget)
# burn_rate > 1 means consuming faster than sustainable
(
  sum(rate(http_requests_total{status_code=~"5.."}[1h]))
  /
  sum(rate(http_requests_total[1h]))
) / 0.001

# Multi-window burn rate alerts
# Fast burn (last 1h vs 5m)
(
  sum(rate(http_requests_total{status_code=~"5.."}[1h]))
  /
  sum(rate(http_requests_total[1h]))
) > 14.4 * 0.001
AND
(
  sum(rate(http_requests_total{status_code=~"5.."}[5m]))
  /
  sum(rate(http_requests_total[5m]))
) > 14.4 * 0.001
```

### 8.4 SLO Alert Rules — `prometheus/rules/slo-alerts.yml`

```yaml
groups:
  - name: slo_burn_rate_alerts
    rules:
      # Fast burn — 2% of monthly budget consumed in 1 hour
      - alert: SLOBurnRateFast
        expr: |
          (
            sum(rate(http_requests_total{status_code=~"5.."}[1h]))
            /
            sum(rate(http_requests_total[1h]))
          ) > (14.4 * 0.001)
          and
          (
            sum(rate(http_requests_total{status_code=~"5.."}[5m]))
            /
            sum(rate(http_requests_total[5m]))
          ) > (14.4 * 0.001)
        for: 2m
        labels:
          severity: critical
          category: slo
        annotations:
          summary: "SLO burn rate critical — 2% budget consumed in 1h"
          description: "Error budget is being consumed 14.4x faster than sustainable"

      # Slow burn — 5% of monthly budget consumed in 6 hours
      - alert: SLOBurnRateSlow
        expr: |
          (
            sum(rate(http_requests_total{status_code=~"5.."}[6h]))
            /
            sum(rate(http_requests_total[6h]))
          ) > (6 * 0.001)
          and
          (
            sum(rate(http_requests_total{status_code=~"5.."}[30m]))
            /
            sum(rate(http_requests_total[30m]))
          ) > (6 * 0.001)
        for: 15m
        labels:
          severity: warning
          category: slo
        annotations:
          summary: "SLO burn rate elevated — 5% budget consumed in 6h"
          description: "Error budget consumption rate is 6x above sustainable level"

      # Budget nearly exhausted
      - alert: SLOBudgetNearlyExhausted
        expr: |
          1 - (
            sum(rate(http_requests_total{status_code=~"5.."}[30d]))
            /
            sum(rate(http_requests_total[30d]))
          ) / 0.001 * 100 < 10
        for: 5m
        labels:
          severity: critical
          category: slo
        annotations:
          summary: "SLO error budget <10% remaining"
          description: "Less than 10% of monthly error budget remains — freeze non-critical deployments"
```

### 8.5 Monthly Reliability Report Template

Generate this report on the 1st of each month. Automate via Lobster pipeline or Grafana PDF export.

```markdown
# GateForge Monthly Reliability Report
## Period: {MONTH} {YEAR}

### Executive Summary
| Metric | Target | Actual | Status |
|--------|--------|--------|--------|
| Platform Availability | 99.9% | XX.XX% | ✅/❌ |
| API p95 Latency | <500ms | XXXms | ✅/❌ |
| Error Budget Remaining | >0% | XX.X% | ✅/❌ |
| Incidents (P0/P1) | 0 | X | ✅/❌ |

### Availability by Service
| Service | SLO | Actual | Downtime | Budget Used |
|---------|-----|--------|----------|-------------|
| API Gateway | 99.9% | | | |
| User Service | 99.9% | | | |
| Order Service | 99.95% | | | |
| Auth Service | 99.99% | | | |
| PostgreSQL | 99.99% | | | |
| Redis | 99.9% | | | |

### Incidents
| Date | Severity | Duration | Service | Root Cause | Resolution |
|------|----------|----------|---------|------------|------------|
| | | | | | |

### Latency Trends
- p50 avg: XXms (prev month: XXms, Δ: +/-XX%)
- p95 avg: XXms (prev month: XXms, Δ: +/-XX%)
- p99 avg: XXms (prev month: XXms, Δ: +/-XX%)

### Capacity Forecast
- Disk: XX% used, fills in ~XX days at current rate
- Memory: XX% avg utilization, headroom: XX%
- CPU: XX% avg utilization, peak: XX%
- Database size: XX GB, growth: XX GB/month
- Connection pool: XX% utilization at peak

### Deployments
| Metric | Value |
|--------|-------|
| Total deployments | X |
| Successful | X |
| Rolled back | X |
| Mean deploy time | Xm |
| Mean time to recovery (MTTR) | Xm |

### Action Items
- [ ] Action item 1
- [ ] Action item 2
- [ ] Action item 3

### Report Generated
- By: Operator Agent (VM-5)
- Date: {DATE}
- Reviewed by: the end-user
```

---

## Appendix A: File Structure Reference

```
/opt/app/monitoring/
├── docker-compose.monitoring.yml
├── .env                              # Secrets (TELEGRAM_BOT_TOKEN, etc.)
├── prometheus/
│   ├── prometheus.yml
│   ├── rules/
│   │   ├── recording-rules.yml
│   │   ├── alerting-rules.yml
│   │   ├── database-alerts.yml
│   │   └── slo-alerts.yml
│   └── targets/
│       └── external/
├── alertmanager/
│   ├── alertmanager.yml
│   └── templates/
│       └── telegram.tmpl
├── grafana/
│   ├── provisioning/
│   │   ├── datasources/
│   │   │   └── datasources.yml
│   │   └── dashboards/
│   │       └── dashboards.yml
│   └── dashboards/
│       ├── infrastructure/
│       ├── services/
│       ├── databases/
│       └── slo/
├── loki/
│   └── loki-config.yml
└── promtail/
    └── promtail-config.yml
```

## Appendix B: Quick Reference — Critical PromQL Queries

```promql
# ── System Health ──────────────────────────────────────────
# CPU %
100 - (avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# Memory %
(1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100

# Disk %
(1 - node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) * 100

# ── Application Health ─────────────────────────────────────
# Request rate
sum(rate(http_requests_total[5m])) by (service)

# Error rate %
sum(rate(http_requests_total{status_code=~"5.."}[5m])) by (service) / sum(rate(http_requests_total[5m])) by (service) * 100

# p95 latency
histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket[5m])) by (le, service))

# ── Database Health ────────────────────────────────────────
# PG cache hit ratio
pg_stat_database_blks_hit / (pg_stat_database_blks_hit + pg_stat_database_blks_read)

# PG connection utilization
pg_stat_activity_count / pg_settings_max_connections * 100

# Redis hit rate
rate(redis_keyspace_hits_total[5m]) / (rate(redis_keyspace_hits_total[5m]) + rate(redis_keyspace_misses_total[5m]))

# Redis memory %
redis_memory_used_bytes / redis_memory_max_bytes * 100

# ── SLO ────────────────────────────────────────────────────
# Availability (30d)
1 - sum(rate(http_requests_total{status_code=~"5.."}[30d])) / sum(rate(http_requests_total[30d]))

# Error budget burn rate
(sum(rate(http_requests_total{status_code=~"5.."}[1h])) / sum(rate(http_requests_total[1h]))) / 0.001
```

## Appendix C: Environment Variables Reference

```bash
# .env file for monitoring stack
# ── Grafana ──────────────────────────────────
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=<secure-password>

# ── PostgreSQL Exporter ──────────────────────
PG_EXPORTER_USER=exporter
PG_EXPORTER_PASSWORD=<secure-password>

# ── Redis ────────────────────────────────────
REDIS_PASSWORD=<secure-password>

# ── Alertmanager / Telegram ──────────────────
TELEGRAM_BOT_TOKEN=<bot-token-from-botfather>
TELEGRAM_CHAT_ID=<chat-id-for-alerts>
TELEGRAM_DB_CHAT_ID=<chat-id-for-db-alerts>

# ── Email (SMTP) ─────────────────────────────
SMTP_USERNAME=<smtp-user>
SMTP_PASSWORD=<smtp-password>
```

---

*This document is the single source of truth for GateForge monitoring and operations. All changes must be approved by the System Architect (VM-1) and logged in `decision-log.md`.*

---

## Appendix: Managed Output Documents

The Operator agent produces and maintains the following documents in the Blueprint repository's `operations/` directory.

### Document Ownership Map

| Document | Path in Blueprint Repo | When to Create | When to Update |
|----------|----------------------|----------------|----------------|
| Deployment Runbook | `operations/deployment-runbook.md` | Before first deployment | When deployment procedure changes |
| Deployment Log | `operations/deployment-log.md` | At first deployment | After every deployment (append entry) |
| Operation Log | `operations/operation-log.md` | At system launch | After every operational event (append entry) |
| SLA/SLO Tracking | `operations/sla-slo-tracking.md` | When SLOs are defined | Monthly (reliability report) + after any incident |
| Incident Reports | `operations/incident-reports/INC-<NNN>.md` | When an incident occurs | Through incident lifecycle (open → resolved → post-mortem) |

### Output Rules

1. **Use the templates** from `gateforge-blueprint-template/operations/` (`tonylnng/gateforge-blueprint-template`, read-only) — do not invent new formats
2. **Deployment log is append-only** — never modify past entries, only add new ones
3. **Operation log is append-only** — every operational event must be recorded
4. **Incident reports must include**: Timeline, root cause analysis (5 Whys), prevention actions, lessons learned
5. **SLA/SLO tracking must include**: Error budget status, monthly reliability report
6. **Structured report to Architect**: After every deployment, produce:

```json
{
  "taskId": "TASK-NNN",
  "type": "deployment",
  "status": "completed",
  "deployId": "DEP-NNN",
  "version": "v1.0.0",
  "environment": "dev | uat | production",
  "commitSha": "abc123",
  "imageTags": ["auth-service:v1.0.0", "patient-service:v1.0.0"],
  "smokeTestResult": "pass",
  "healthCheckResult": "all services healthy",
  "monitoringConfirmed": true,
  "documentsUpdated": ["operations/deployment-log.md"],
  "rollbackTested": true,
  "issues": []
}
```

7. **Git commit convention**: `ops(<env>): <description>` (e.g., `ops(uat): deploy v1.0.0 to UAT`)
8. **Monthly operations summary**: On the last day of each month, produce a summary in `operations/operation-log.md` covering total events, uptime %, incidents, planned maintenance

---

*This document is the single source of truth for GateForge monitoring and operations. All changes must be approved by the System Architect (VM-1) and logged in `decision-log.md`.*

*Last updated: 2026-04-07 by Operator Agent (VM-5)*
