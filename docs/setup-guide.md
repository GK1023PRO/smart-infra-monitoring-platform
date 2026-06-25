# Setup Guide — Smart Infrastructure Monitoring Platform

## Prerequisites

| Tool | Version | Install |
|---|---|---|
| Docker Desktop | 24+ | https://docs.docker.com/get-docker/ |
| Docker Compose | v2 (bundled) | Included with Docker Desktop |
| Git | any | https://git-scm.com |
| VSCode | any | https://code.visualstudio.com |

---

## 1. Clone & configure

```bash
git clone https://github.com/<your-username>/smart-infra-monitoring-platform.git
cd smart-infra-monitoring-platform

cp .env.example .env
```

Edit `.env` and fill in:

```env
HOSTNAME_LABEL=my-server
N8N_WEBHOOK_URL=http://n8n:5678/webhook/monitor-alert
GRAFANA_ADMIN_PASSWORD=yourSecurePassword
```

Telegram/Email/Discord credentials are configured inside n8n (Step 4), not in `.env`.

---

## 2. Start all services

```bash
docker compose up --build -d
```

This starts: **monitor → exporter → prometheus → grafana → n8n**

Check everything is running:

```bash
docker compose ps
docker compose logs -f monitor
```

---

## 3. Verify metrics are flowing

```bash
# Exporter serves raw metrics
curl http://localhost:9200/metrics

# Prometheus has scraped them (wait 30s after start)
curl "http://localhost:9090/api/v1/query?query=system_cpu_usage_percent"
```

Open Prometheus: http://localhost:9090 → Status → Targets — "system-monitor" should show **UP**

---

## 4. Open Grafana

URL: http://localhost:3000  
Login: `admin` / `<GRAFANA_ADMIN_PASSWORD from .env>`

The dashboard **Smart Infrastructure Monitoring Platform** is auto-provisioned. If it's missing: Dashboards → Browse → Smart Infra.

---

## 5. Configure n8n workflows

URL: http://localhost:5678  
Login: `admin` / `<GRAFANA_ADMIN_PASSWORD from .env>`

### Import workflows

1. In n8n: **Workflows → Import from file**
2. Import `n8n/workflows/alert-intake.json`
3. Import `n8n/workflows/summary-report.json`

### Add credentials

**Telegram:**
1. Settings → Credentials → New → Telegram API
2. Enter your Bot Token (from @BotFather)
3. Name it `Telegram Bot`

**Email (SMTP):**
1. New → SMTP
2. Fill in your SMTP server, port, username, password

**Discord:**
- No credential needed — the Discord webhook URL is passed directly in the workflow node's URL field. Edit the Discord Alert node and paste your webhook URL.

### Set environment variables in n8n

Settings → Variables:
- `TELEGRAM_CHAT_ID` → your Telegram chat ID
- `EMAIL_TO` → your email address
- `DISCORD_WEBHOOK_URL` → your Discord webhook URL

### Activate workflows

Toggle both workflows to **Active**.

---

## 6. Test an alert end-to-end

Temporarily lower thresholds to force an alert:

```bash
# Edit monitor/config/thresholds.conf
CPU_WARN=1
CPU_CRIT=2
```

Restart monitor:

```bash
docker compose restart monitor
```

Watch the logs:

```bash
docker compose logs -f monitor
```

You should see `[INFO] n8n alert delivered (HTTP 200)` and receive a Telegram/Discord message within seconds.

Reset thresholds when done.

---

## 7. Stop all services

```bash
docker compose down
# To also remove volumes (WARNING: deletes stored metrics):
docker compose down -v
```

---

## Ports reference

| Service | URL |
|---|---|
| Grafana | http://localhost:3000 |
| Prometheus | http://localhost:9090 |
| n8n | http://localhost:5678 |
| Metrics Exporter | http://localhost:9200/metrics |
