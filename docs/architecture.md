# Architecture — Smart Infrastructure Monitoring Platform

## System Overview

A multi-layer infrastructure monitoring system built with production-grade tooling: bash-based metrics collection, Prometheus time-series storage, Grafana visualization, and n8n automation for multi-channel alerting.

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                  Host / Linux System                         │
│  /proc/stat  /proc/meminfo  /proc/loadavg  df               │
└─────────────────────┬───────────────────────────────────────┘
                      │ reads
                      ▼
┌─────────────────────────────────────┐
│         monitor.sh (bash)           │  every 60s
│  - Collects CPU / MEM / DISK / LOAD │
│  - Evaluates WARNING / CRITICAL     │
│  - Writes /data/metrics.prom        │  ──► Prometheus textfile
│  - Writes json/monitor-latest.json  │
│  - Writes logs/monitor-YYYY-MM-DD   │
│  - POST /webhook/monitor-alert      │  ──► n8n (on alert)
└─────────────────────────────────────┘
          │ /data/metrics.prom (shared Docker volume)
          ▼
┌─────────────────────────────────────┐
│     exporter.py (Python HTTP)       │  :9200/metrics
│  Reads metrics.prom, serves via HTTP│
└──────────────────┬──────────────────┘
                   │ scrapes every 15s
                   ▼
┌─────────────────────────────────────┐
│         Prometheus :9090            │
│  - Stores time-series data          │
│  - Evaluates alert.rules.yml        │
│  - 15-day retention                 │
└──────────────────┬──────────────────┘
                   │ data source
                   ▼
┌─────────────────────────────────────┐
│         Grafana :3000               │
│  - Auto-provisioned datasource      │
│  - Auto-provisioned dashboard       │
│  - 4 stat panels + 2 time-series    │
└─────────────────────────────────────┘

                                 n8n :5678
                          ┌──────────┴──────────┐
                          │  Alert Intake Wflow  │
                     ┌────┴────┐  ┌──────┐  ┌───┴───┐
                     │Telegram │  │Email │  │Discord│
                     └─────────┘  └──────┘  └───────┘
                          │  Hourly Summary Wflow     │
                          │  → Queries Prometheus     │
                          │  → Sends digest           │
                          └───────────────────────────┘
```

## Component Decisions

| Component | Choice | Reason |
|---|---|---|
| Metrics collection | bash + /proc | Zero dependencies, portable across any Linux |
| Metrics storage | Prometheus | Industry standard, native time-series, alerting built-in |
| Visualization | Grafana | Best-in-class dashboarding, native Prometheus integration |
| Alert routing | n8n | No-code workflow engine; swap channels without touching bash |
| Exporter | Python HTTP | Simple, lightweight bridge between textfile and Prometheus pull model |
| Containerization | Docker Compose | Single-command bring-up of all 5 services |
| CI | GitHub Actions | Free, native to GitHub, runs on every push |

## Data Flow

1. **Collection** — `monitor.sh` reads `/proc` filesystem (no external tools needed)
2. **Evaluation** — Thresholds compared with `bc` float math, severity assigned per metric
3. **Storage (textfile)** — Written to `/data/metrics.prom` on shared Docker volume
4. **Export** — `exporter.py` serves the textfile over HTTP for Prometheus scrape
5. **Storage (time-series)** — Prometheus pulls from exporter, stores with 15-day retention
6. **Visualization** — Grafana queries Prometheus, renders auto-provisioned dashboard
7. **Alerting** — On WARNING/CRITICAL, `monitor.sh` POSTs full JSON payload to n8n webhook
8. **Fan-out** — n8n Alert Intake workflow sends to Telegram + Email + Discord in parallel
9. **Reporting** — n8n Hourly Summary queries Prometheus API, posts digest to Telegram

## Security Design

- No credentials in code — all secrets in `.env` (gitignored)
- `.env.example` committed with placeholder values only
- n8n credentials stored in encrypted n8n internal store
- Grafana sign-up disabled, admin password from env
- All services on an internal Docker bridge network — only necessary ports exposed
