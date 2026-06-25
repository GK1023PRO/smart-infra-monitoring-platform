#!/usr/bin/env bash
# =============================================================
# Smart Infrastructure Monitoring Platform - monitor.sh
# Version: 3.0 | Author: DevOps Engineer
# =============================================================
set -euo pipefail

# ── Paths ────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config/thresholds.conf"
ENV_FILE="${SCRIPT_DIR}/../.env"
LOG_DIR="${SCRIPT_DIR}/../logs"
JSON_DIR="${SCRIPT_DIR}/../json"
METRICS_FILE="/data/metrics.prom"

# ── Load env & config ─────────────────────────────────────────
# shellcheck source=/dev/null
[[ -f "$ENV_FILE" ]]     && source "$ENV_FILE"
# shellcheck source=/dev/null
[[ -f "$CONFIG_FILE" ]]  && source "$CONFIG_FILE"

# ── Defaults (override via .env or thresholds.conf) ───────────
CPU_WARN="${CPU_WARN:-70}"
CPU_CRIT="${CPU_CRIT:-90}"
MEM_WARN="${MEM_WARN:-75}"
MEM_CRIT="${MEM_CRIT:-90}"
DISK_WARN="${DISK_WARN:-80}"
DISK_CRIT="${DISK_CRIT:-90}"
LOAD_WARN="${LOAD_WARN:-2.0}"
LOAD_CRIT="${LOAD_CRIT:-4.0}"
CHECK_INTERVAL="${CHECK_INTERVAL:-60}"
N8N_WEBHOOK_URL="${N8N_WEBHOOK_URL:-}"
HOSTNAME_LABEL="${HOSTNAME_LABEL:-$(hostname)}"

# ── Dependency check ──────────────────────────────────────────
for cmd in jq curl bc awk; do
  command -v "$cmd" &>/dev/null || { echo "[ERROR] Missing dependency: $cmd"; exit 1; }
done

# ── Logging ───────────────────────────────────────────────────
mkdir -p "$LOG_DIR" "$JSON_DIR"
LOG_FILE="${LOG_DIR}/monitor-$(date +%F).log"

log() {
  local level="$1"; shift
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*" | tee -a "$LOG_FILE"
}

# ── Metrics collection ────────────────────────────────────────
collect_metrics() {
  # CPU  (use /proc/stat for portability, no mpstat needed)
  local cpu_idle
  cpu_idle=$(awk '/^cpu /{idle=$5; total=0; for(i=2;i<=NF;i++) total+=$i; printf "%.1f", idle/total*100}' /proc/stat)
  CPU=$(echo "100 - $cpu_idle" | bc)

  # Memory
  local mem_total mem_available
  mem_total=$(awk '/^MemTotal/{print $2}' /proc/meminfo)
  mem_available=$(awk '/^MemAvailable/{print $2}' /proc/meminfo)
  MEM=$(echo "scale=1; (1 - $mem_available/$mem_total)*100" | bc)

  # Disk (root partition)
  DISK=$(df / | awk 'NR==2{gsub(/%/,""); print $5}')

  # Load average (1-min)
  LOAD=$(awk '{print $1}' /proc/loadavg)

  TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
  EPOCH=$(date +%s)
}

# ── Severity helper ───────────────────────────────────────────
severity() {
  local val="$1" warn="$2" crit="$3"
  if (( $(echo "$val >= $crit" | bc -l) )); then echo "CRITICAL"
  elif (( $(echo "$val >= $warn" | bc -l) )); then echo "WARNING"
  else echo "OK"
  fi
}

# ── Prometheus textfile metrics ───────────────────────────────
write_prometheus_metrics() {
  mkdir -p "$(dirname "$METRICS_FILE")" 2>/dev/null || true
  cat > "$METRICS_FILE" <<EOF
# HELP system_cpu_usage_percent Current CPU usage percentage
# TYPE system_cpu_usage_percent gauge
system_cpu_usage_percent{host="${HOSTNAME_LABEL}"} ${CPU}
# HELP system_mem_usage_percent Current memory usage percentage
# TYPE system_mem_usage_percent gauge
system_mem_usage_percent{host="${HOSTNAME_LABEL}"} ${MEM}
# HELP system_disk_usage_percent Current disk usage percentage (root)
# TYPE system_disk_usage_percent gauge
system_disk_usage_percent{host="${HOSTNAME_LABEL}"} ${DISK}
# HELP system_load_average Current 1-minute load average
# TYPE system_load_average gauge
system_load_average{host="${HOSTNAME_LABEL}"} ${LOAD}
# HELP monitor_last_check_timestamp Unix timestamp of last check
# TYPE monitor_last_check_timestamp gauge
monitor_last_check_timestamp{host="${HOSTNAME_LABEL}"} ${EPOCH}
EOF
}

# ── JSON output ───────────────────────────────────────────────
write_json() {
  local sev_cpu sev_mem sev_disk sev_load overall
  sev_cpu=$(severity  "$CPU"  "$CPU_WARN"  "$CPU_CRIT")
  sev_mem=$(severity  "$MEM"  "$MEM_WARN"  "$MEM_CRIT")
  sev_disk=$(severity "$DISK" "$DISK_WARN" "$DISK_CRIT")
  sev_load=$(severity "$LOAD" "$LOAD_WARN" "$LOAD_CRIT")

  # Overall = worst of the four
  overall="OK"
  for s in "$sev_cpu" "$sev_mem" "$sev_disk" "$sev_load"; do
    [[ "$s" == "CRITICAL" ]] && overall="CRITICAL" && break
    [[ "$s" == "WARNING"  ]] && overall="WARNING"
  done

  PAYLOAD=$(jq -n \
    --arg ts "$TIMESTAMP" \
    --arg host "$HOSTNAME_LABEL" \
    --argjson cpu "$CPU" --arg scpu "$sev_cpu" \
    --argjson mem "$MEM" --arg smem "$sev_mem" \
    --argjson disk "$DISK" --arg sdisk "$sev_disk" \
    --arg load "$LOAD"     --arg sload "$sev_load" \
    --arg overall "$overall" \
    '{
      timestamp: $ts,
      host: $host,
      overall_status: $overall,
      metrics: {
        cpu:  { value: $cpu,  unit: "%", severity: $scpu  },
        mem:  { value: $mem,  unit: "%", severity: $smem  },
        disk: { value: $disk, unit: "%", severity: $sdisk },
        load: { value: $load, unit: "load", severity: $sload }
      }
    }')

  echo "$PAYLOAD" > "${JSON_DIR}/monitor-latest.json"
  echo "$PAYLOAD" >> "${JSON_DIR}/monitor-history.jsonl"
}

# ── n8n alert ─────────────────────────────────────────────────
send_n8n_alert() {
  local _message="$1" _status="$2"
  if [[ -z "$N8N_WEBHOOK_URL" ]]; then
    log "WARN" "N8N_WEBHOOK_URL not set — alert not forwarded"
    return 0
  fi

  local http_code
  http_code=$(curl -s -o /dev/null -w "%{http_code}" \
    --max-time 10 \
    -H "Content-Type: application/json" \
    -X POST "$N8N_WEBHOOK_URL" \
    -d "$PAYLOAD") || true

  if [[ "$http_code" == "200" || "$http_code" == "201" ]]; then
    log "INFO" "n8n alert delivered (HTTP $http_code)"
  else
    log "WARN" "n8n alert failed (HTTP $http_code) — check N8N_WEBHOOK_URL"
  fi
}

# ── Main loop ─────────────────────────────────────────────────
log "INFO" "Monitor starting — interval=${CHECK_INTERVAL}s host=${HOSTNAME_LABEL}"

while true; do
  collect_metrics
  write_json
  write_prometheus_metrics

  OVERALL=$(jq -r '.overall_status' "${JSON_DIR}/monitor-latest.json")
  log "INFO" "CPU=${CPU}% MEM=${MEM}% DISK=${DISK}% LOAD=${LOAD} STATUS=${OVERALL}"

  if [[ "$OVERALL" == "CRITICAL" || "$OVERALL" == "WARNING" ]]; then
    MESSAGE="[${OVERALL}] ${HOSTNAME_LABEL} @ ${TIMESTAMP} | CPU:${CPU}% MEM:${MEM}% DISK:${DISK}% LOAD:${LOAD}"
    send_n8n_alert "$MESSAGE" "$OVERALL"
  fi

  sleep "$CHECK_INTERVAL"
done
