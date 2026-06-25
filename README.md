# Smart Infrastructure Monitoring Platform

A production-grade infrastructure monitoring system built with bash, Docker, Prometheus, Grafana, and n8n automation.

## Architecture

```
Linux /proc → monitor.sh → metrics.prom → exporter :9200 → Prometheus :9090 → Grafana :3000
                      └──────────────── (on alert) ──────────────────► n8n :5678
                                                                         ├── Telegram
                                                                         ├── Email
                                                                         └── Discord
```

## Features

- **Zero-dependency metrics** — reads directly from `/proc`, no agents required
- **Multi-severity alerts** — OK / WARNING / CRITICAL per metric with configurable thresholds
- **Prometheus + Grafana** — time-series storage and auto-provisioned dashboard
- **n8n automation hub** — single webhook routes alerts to Telegram, Email, and Discord in parallel; hourly summary report via scheduled workflow
- **Structured logging** — JSON history file (`monitor-history.jsonl`) + human-readable daily logs
- **Docker Compose** — one command starts all 5 services
- **GitHub Actions CI** — ShellCheck lint, unit tests, YAML/JSON validation, Docker build on every push

## Quick Start

```bash
git clone https://github.com/<your-username>/smart-infra-monitoring-platform.git
cd smart-infra-monitoring-platform
cp .env.example .env
# Fill in .env with your passwords

docker compose up --build -d
```

Then open:
- Grafana: http://localhost:3000
- Prometheus: http://localhost:9090
- n8n: http://localhost:5678

See [docs/setup-guide.md](docs/setup-guide.md) for full instructions including n8n workflow import and credential setup.

## Project Structure

```
smart-infra-monitoring-platform/
├── .github/workflows/ci.yml       # GitHub Actions CI pipeline
├── docker/
│   ├── Dockerfile.monitor         # bash monitor container
│   └── Dockerfile.exporter        # Python exporter container
├── docs/
│   ├── architecture.md            # Design decisions and data flow
│   └── setup-guide.md             # Step-by-step setup instructions
├── exporter/
│   └── exporter.py                # Prometheus metrics HTTP server
├── grafana/
│   ├── dashboards/infra-dashboard.json
│   └── provisioning/              # Auto-provisioned datasource + dashboard
├── monitor/
│   ├── config/thresholds.conf     # Configurable thresholds
│   └── monitor.sh                 # Core metrics + alerting script
├── n8n/workflows/
│   ├── alert-intake.json          # Webhook → Telegram + Email + Discord
│   └── summary-report.json        # Hourly digest from Prometheus
├── prometheus/
│   ├── prometheus.yml             # Scrape config
│   └── alert.rules.yml            # Alert rules
├── tests/
│   └── test_thresholds.sh         # Unit tests (13 assertions)
├── .env.example                   # Config template (commit this)
├── .gitignore                     # Excludes .env, logs/, json/
└── docker-compose.yml             # All 5 services
```

## Monitored Metrics

| Metric | Warning | Critical |
|---|---|---|
| CPU Usage | 70% | 90% |
| Memory Usage | 75% | 90% |
| Disk Usage (/) | 80% | 90% |
| Load Average (1m) | 2.0 | 4.0 |

All thresholds are configurable in `monitor/config/thresholds.conf`.

## Tech Stack

| Layer | Technology |
|---|---|
| Collection | Bash + /proc filesystem |
| Export | Python 3 HTTP server |
| Storage | Prometheus |
| Visualization | Grafana |
| Automation | n8n |
| Containerization | Docker + Compose |
| CI/CD | GitHub Actions |

## CI Pipeline

On every push to `main` or PR:
1. **ShellCheck** — lint all bash scripts
2. **Unit Tests** — 13 threshold assertions
3. **Config Validation** — YAML and JSON files
4. **Docker Build** — build both images

## License

MIT
