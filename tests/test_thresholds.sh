#!/usr/bin/env bash
# =============================================================
# test_thresholds.sh - Unit tests for monitor threshold logic
# =============================================================
set -euo pipefail

PASS=0
FAIL=0

# Load thresholds
CPU_WARN=70; CPU_CRIT=90
MEM_WARN=75; MEM_CRIT=90
DISK_WARN=80; DISK_CRIT=90
LOAD_WARN=2.0; LOAD_CRIT=4.0

severity() {
  local val="$1" warn="$2" crit="$3"
  if (( $(echo "$val >= $crit" | bc -l) )); then echo "CRITICAL"
  elif (( $(echo "$val >= $warn" | bc -l) )); then echo "WARNING"
  else echo "OK"
  fi
}

assert_eq() {
  local test_name="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "  ✅ PASS: $test_name"
    PASS=$((PASS + 1))
  else
    echo "  ❌ FAIL: $test_name — expected '$expected', got '$actual'"
    FAIL=$((FAIL + 1))
  fi
}

echo ""
echo "════════════════════════════════════════"
echo " Smart Infra Monitor — Unit Tests"
echo "════════════════════════════════════════"
echo ""

echo "── CPU Thresholds ──────────────────────"
assert_eq "CPU 50% → OK"       "OK"       "$(severity 50  $CPU_WARN  $CPU_CRIT)"
assert_eq "CPU 70% → WARNING"  "WARNING"  "$(severity 70  $CPU_WARN  $CPU_CRIT)"
assert_eq "CPU 89% → WARNING"  "WARNING"  "$(severity 89  $CPU_WARN  $CPU_CRIT)"
assert_eq "CPU 90% → CRITICAL" "CRITICAL" "$(severity 90  $CPU_WARN  $CPU_CRIT)"
assert_eq "CPU 99% → CRITICAL" "CRITICAL" "$(severity 99  $CPU_WARN  $CPU_CRIT)"

echo ""
echo "── Memory Thresholds ───────────────────"
assert_eq "MEM 50% → OK"       "OK"       "$(severity 50  $MEM_WARN  $MEM_CRIT)"
assert_eq "MEM 75% → WARNING"  "WARNING"  "$(severity 75  $MEM_WARN  $MEM_CRIT)"
assert_eq "MEM 90% → CRITICAL" "CRITICAL" "$(severity 90  $MEM_WARN  $MEM_CRIT)"

echo ""
echo "── Disk Thresholds ─────────────────────"
assert_eq "DISK 79% → OK"      "OK"       "$(severity 79  $DISK_WARN $DISK_CRIT)"
assert_eq "DISK 80% → WARNING" "WARNING"  "$(severity 80  $DISK_WARN $DISK_CRIT)"
assert_eq "DISK 90% → CRITICAL" "CRITICAL" "$(severity 90 $DISK_WARN $DISK_CRIT)"

echo ""
echo "── Load Thresholds ─────────────────────"
assert_eq "LOAD 1.0 → OK"      "OK"       "$(severity 1.0 $LOAD_WARN $LOAD_CRIT)"
assert_eq "LOAD 2.0 → WARNING" "WARNING"  "$(severity 2.0 $LOAD_WARN $LOAD_CRIT)"
assert_eq "LOAD 4.0 → CRITICAL" "CRITICAL" "$(severity 4.0 $LOAD_WARN $LOAD_CRIT)"

echo ""
echo "════════════════════════════════════════"
echo " Results: ${PASS} passed / ${FAIL} failed"
echo "════════════════════════════════════════"
echo ""

[[ $FAIL -eq 0 ]] && exit 0 || exit 1
