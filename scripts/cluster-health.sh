#!/usr/bin/env bash
# ==============================================================================
# scripts/cluster-health.sh
# Kubernetes + ArgoCD 叢集健康檢查腳本
#
# 用途：
#   - 由 cluster-health-check.yml workflow 呼叫
#   - 也可手動執行（需先設定 KUBECONFIG 環境變數）
#
# 使用方式：
#   # CI（KUBECONFIG 由 workflow 設定）：
#   scripts/cluster-health.sh <environment> <mgmt_label> <worker_label>
#
#   # 本地手動執行：
#   export KUBECONFIG=/path/to/kubeconfig
#   scripts/cluster-health.sh dev lke-dev-mgmt lke-dev-ateam
#
# 輸出：
#   PASS/WARN/FAIL 格式的結構化報告，exitcode 0=all-pass 1=has-failures
# ==============================================================================

set -euo pipefail

ENVIRONMENT="${1:-unknown}"
MGMT_LABEL="${2:-unknown}"
WORKER_LABEL="${3:-unknown}"

# ── 顏色輸出（CI 環境自動禁用）─────────────────────────────────────────────
if [ -t 1 ] && [ -z "${CI:-}" ]; then
  GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
else
  GREEN=''; YELLOW=''; RED=''; NC=''
fi

PASS=0; WARN=0; FAIL=0

pass()  { PASS=$((PASS+1));  echo -e "${GREEN}[PASS]${NC} $*"; }
warn()  { WARN=$((WARN+1));  echo -e "${YELLOW}[WARN]${NC} $*"; }
fail()  { FAIL=$((FAIL+1));  echo -e "${RED}[FAIL]${NC} $*"; }
header(){ echo ""; echo "=== $* ==="; }

# ==============================================================================
header "Cluster Health Check — ${ENVIRONMENT} / ${MGMT_LABEL}"
echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "KUBECONFIG: ${KUBECONFIG:-<not set>}"
echo ""

# ── 1. Kubernetes API Server 檢查 ─────────────────────────────────────────────
header "1. Kubernetes API Server"

if kubectl cluster-info --request-timeout=10s > /dev/null 2>&1; then
  SERVER_VERSION="$(kubectl version --output=json 2>/dev/null | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('serverVersion',{}).get('gitVersion','unknown'))" 2>/dev/null || echo 'unknown')"
  pass "API server reachable — server version: ${SERVER_VERSION}"
else
  fail "API server unreachable (request timed out or refused)"
fi

# ── 2. Node 就緒狀態 ──────────────────────────────────────────────────────────
header "2. Node Readiness"

TOTAL_NODES="$(kubectl get nodes --no-headers 2>/dev/null | wc -l || echo 0)"
READY_NODES="$(kubectl get nodes --no-headers 2>/dev/null | grep -c ' Ready' || true)"
NOTREADY_NODES="$(kubectl get nodes --no-headers 2>/dev/null | grep -c 'NotReady' || true)"

echo "  Total:    ${TOTAL_NODES}"
echo "  Ready:    ${READY_NODES}"
echo "  NotReady: ${NOTREADY_NODES}"
kubectl get nodes -o wide --no-headers 2>/dev/null | awk '{printf "  %-40s %-10s %-10s\n", $1, $2, $5}' || true

if [ "${TOTAL_NODES}" -eq 0 ]; then
  fail "No nodes found in cluster"
elif [ "${NOTREADY_NODES}" -gt 0 ]; then
  fail "${NOTREADY_NODES}/${TOTAL_NODES} nodes are NotReady"
  kubectl get nodes --no-headers 2>/dev/null | grep NotReady | awk '{print "  NotReady node: "$1}' || true
else
  pass "${READY_NODES}/${TOTAL_NODES} nodes are Ready"
fi

# ── 3. System Pods 健康狀態（kube-system）─────────────────────────────────────
header "3. System Pods Health (kube-system)"

SYSTEM_TOTAL="$(kubectl get pods -n kube-system --no-headers 2>/dev/null | wc -l || echo 0)"
SYSTEM_RUNNING="$(kubectl get pods -n kube-system --no-headers 2>/dev/null | grep -c 'Running' || true)"
SYSTEM_FAILED="$(kubectl get pods -n kube-system --no-headers 2>/dev/null | grep -cE 'Error|CrashLoopBackOff|OOMKilled|Evicted' || true)"

echo "  Total:   ${SYSTEM_TOTAL}"
echo "  Running: ${SYSTEM_RUNNING}"
echo "  Failed:  ${SYSTEM_FAILED}"

if [ "${SYSTEM_FAILED}" -gt 0 ]; then
  fail "${SYSTEM_FAILED} system pod(s) in failed state"
  kubectl get pods -n kube-system --no-headers 2>/dev/null | \
    grep -E 'Error|CrashLoopBackOff|OOMKilled|Evicted' | \
    awk '{print "  Failed: "$1" ("$3")"}' || true
elif [ "${SYSTEM_TOTAL}" -eq 0 ]; then
  warn "No pods found in kube-system namespace"
else
  pass "System pods healthy (${SYSTEM_RUNNING}/${SYSTEM_TOTAL} Running)"
fi

# ── 4. ArgoCD Pods 健康狀態 ───────────────────────────────────────────────────
header "4. ArgoCD Pods Health (argocd namespace)"

if ! kubectl get namespace argocd > /dev/null 2>&1; then
  fail "ArgoCD namespace does not exist"
else
  ARGOCD_TOTAL="$(kubectl get pods -n argocd --no-headers 2>/dev/null | wc -l || echo 0)"
  ARGOCD_RUNNING="$(kubectl get pods -n argocd --no-headers 2>/dev/null | grep -c 'Running' || true)"
  ARGOCD_FAILED="$(kubectl get pods -n argocd --no-headers 2>/dev/null | grep -cE 'Error|CrashLoopBackOff|OOMKilled' || true)"

  echo "  Total:   ${ARGOCD_TOTAL}"
  echo "  Running: ${ARGOCD_RUNNING}"
  echo "  Failed:  ${ARGOCD_FAILED}"

  kubectl get pods -n argocd -o wide --no-headers 2>/dev/null | \
    awk '{printf "  %-50s %-12s %-5s\n", $1, $3, $2}' || true

  if [ "${ARGOCD_FAILED}" -gt 0 ]; then
    fail "ArgoCD has ${ARGOCD_FAILED} pod(s) in failed state"
  elif [ "${ARGOCD_RUNNING}" -lt 4 ]; then
    warn "Only ${ARGOCD_RUNNING} ArgoCD pods Running (expected >= 4)"
  else
    pass "ArgoCD pods healthy (${ARGOCD_RUNNING}/${ARGOCD_TOTAL} Running)"
  fi
fi

# ── 5. ArgoCD Applications 狀態 ───────────────────────────────────────────────
header "5. ArgoCD Applications Status"

if ! kubectl get crd applications.argoproj.io > /dev/null 2>&1; then
  warn "ArgoCD CRD not installed — skipping application status check"
else
  APP_TOTAL="$(kubectl get applications -n argocd --no-headers 2>/dev/null | wc -l || echo 0)"
  APP_SYNCED="$(kubectl get applications -n argocd --no-headers 2>/dev/null | grep -c 'Synced' || true)"
  APP_OUTOFSYNC="$(kubectl get applications -n argocd --no-headers 2>/dev/null | grep -c 'OutOfSync' || true)"
  APP_UNHEALTHY="$(kubectl get applications -n argocd --no-headers 2>/dev/null | grep -c 'Degraded\|Unknown' || true)"

  echo "  Total:      ${APP_TOTAL}"
  echo "  Synced:     ${APP_SYNCED}"
  echo "  OutOfSync:  ${APP_OUTOFSYNC}"
  echo "  Unhealthy:  ${APP_UNHEALTHY}"

  if [ "${APP_TOTAL}" -gt 0 ]; then
    kubectl get applications -n argocd \
      -o custom-columns="NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status" \
      --no-headers 2>/dev/null | awk '{printf "  %-40s %-12s %s\n", $1, $2, $3}' || true
  fi

  if [ "${APP_UNHEALTHY}" -gt 0 ]; then
    fail "${APP_UNHEALTHY} application(s) in Degraded/Unknown health state"
  elif [ "${APP_OUTOFSYNC}" -gt 0 ]; then
    warn "${APP_OUTOFSYNC} application(s) OutOfSync"
  elif [ "${APP_TOTAL}" -eq 0 ]; then
    warn "No ArgoCD applications found"
  else
    pass "All ${APP_TOTAL} application(s) healthy and Synced"
  fi
fi

# ── 6. Worker Cluster 註冊狀態 ────────────────────────────────────────────────
header "6. Worker Cluster Registration"

if ! kubectl get crd applications.argoproj.io > /dev/null 2>&1; then
  warn "ArgoCD CRD not installed — skipping cluster registration check"
else
  CLUSTER_COUNT="$(kubectl get secrets -n argocd \
    -l "argocd.argoproj.io/secret-type=cluster" \
    --no-headers 2>/dev/null | wc -l || echo 0)"

  echo "  Registered clusters: ${CLUSTER_COUNT}"
  echo "  Expected worker:     ${WORKER_LABEL}"

  kubectl get secrets -n argocd \
    -l "argocd.argoproj.io/secret-type=cluster" \
    -o custom-columns="SECRET:.metadata.name,CREATED:.metadata.creationTimestamp" \
    --no-headers 2>/dev/null | awk '{print "  "$0}' || true

  # 檢查預期的 worker cluster Secret 是否存在
  if kubectl get secret "cluster-${WORKER_LABEL}" -n argocd > /dev/null 2>&1; then
    pass "Worker cluster 'cluster-${WORKER_LABEL}' is registered in ArgoCD"
  else
    fail "Worker cluster secret 'cluster-${WORKER_LABEL}' not found in ArgoCD"
  fi
fi

# ==============================================================================
# 摘要
# ==============================================================================
echo ""
echo "══════════════════════════════════════════════"
echo "  Health Check Summary — ${ENVIRONMENT}"
echo "══════════════════════════════════════════════"
printf "  PASS: %d  WARN: %d  FAIL: %d\n" "${PASS}" "${WARN}" "${FAIL}"
echo "══════════════════════════════════════════════"

if [ "${FAIL}" -gt 0 ]; then
  echo "  ❌ Health check FAILED (${FAIL} failures)"
  exit 1
elif [ "${WARN}" -gt 0 ]; then
  echo "  ⚠️  Health check PASSED with ${WARN} warning(s)"
  exit 0
else
  echo "  ✅ Health check PASSED"
  exit 0
fi
