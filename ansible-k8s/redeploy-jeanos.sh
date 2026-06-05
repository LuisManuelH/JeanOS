#!/usr/bin/env bash
# Redeploy JeanOS Shop (hardware catalog) usando redeploy.env
# Uso:
#   cp redeploy.env.example redeploy.env   # primera vez
#   ./redeploy-jeanos.sh
#   ./redeploy-jeanos.sh --dry-run
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
ENV_FILE="${REDEPLOY_ENV:-${SCRIPT_DIR}/redeploy.env}"
MANIFESTS="${SCRIPT_DIR}/manifests"
SEED_SQL="${SCRIPT_DIR}/seed-productos.sql"
DRY_RUN=false

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    -h|--help)
      cat <<'EOF'
Uso: redeploy-jeanos.sh [--dry-run]

Lee ansible-k8s/redeploy.env (o REDEPLOY_ENV) y ejecuta:
  build/push imágenes → seed SQL → apply manifests → rollout → smoke tests

Semana 4: si ArgoCD auto-sync está ON, haz push de manifests a Git o
PAUSE_ARGOCD_SYNC=true en redeploy.env.
EOF
      exit 0
      ;;
    *)
      echo "Opción desconocida: $arg" >&2
      exit 1
      ;;
  esac
done

log() { printf '\n[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }

run() {
  if $DRY_RUN; then
    echo "[dry-run] $*"
  else
    "$@"
  fi
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Falta comando: $1" >&2
    exit 1
  }
}

bool() {
  case "${1,,}" in
    1|true|yes|y|on) return 0 ;;
    *) return 1 ;;
  esac
}

if [[ ! -f "$ENV_FILE" ]]; then
  echo "No existe ${ENV_FILE}. Copia redeploy.env.example → redeploy.env" >&2
  exit 1
fi

# shellcheck disable=SC1090
set -a
source "$ENV_FILE"
set +a

NS="${K8S_NAMESPACE:-jeanos-shop}"
PG_POD="${POSTGRES_POD:-postgres-0}"
PG_USER="${POSTGRES_USER:-jeanosadmin}"
PG_DB="${POSTGRES_DB:-jeanosdb}"
REGISTRY="${REGISTRY:-docker.io/aliothosa}"
TAG="${IMAGE_TAG:-v1}"
BACK_NAME="${DOCKER_BACKEND_IMAGE:-jeanos-backend}"
FRONT_NAME="${DOCKER_FRONTEND_IMAGE:-jeanos-frontend}"
NODE_PORT="${FRONTEND_NODE_PORT:-30080}"
CMP_ID_1="${COMPARE_ID_1:-1}"
CMP_ID_2="${COMPARE_ID_2:-2}"
CLASS_FILTER="${PRODUCTS_CLASS_FILTER:-gpu}"

BUILD_IMAGES="${BUILD_IMAGES:-true}"
PUSH_IMAGES="${PUSH_IMAGES:-true}"
RUN_SEED="${RUN_SEED:-true}"
APPLY_MANIFESTS="${APPLY_MANIFESTS:-true}"
RESTART_DEPLOYMENTS="${RESTART_DEPLOYMENTS:-true}"
WAIT_ROLLOUT="${WAIT_ROLLOUT:-true}"
RUN_SMOKE_TESTS="${RUN_SMOKE_TESTS:-true}"
SHOW_INIT_LOGS="${SHOW_INIT_LOGS:-true}"
PAUSE_ARGOCD_SYNC="${PAUSE_ARGOCD_SYNC:-false}"
ARGOCD_APP="${ARGOCD_APP_NAME:-jeanos-shop-gitops}"
ARGOCD_NS="${ARGOCD_NAMESPACE:-argocd}"

need_cmd kubectl

log "JeanOS redeploy"
log "Env: ${ENV_FILE}"
log "Namespace: ${NS}"
log "Imágenes: ${REGISTRY}/${BACK_NAME}:${TAG} · ${REGISTRY}/${FRONT_NAME}:${TAG}"

if bool "$PAUSE_ARGOCD_SYNC"; then
  if kubectl get application "$ARGOCD_APP" -n "$ARGOCD_NS" >/dev/null 2>&1; then
    log "Pausando auto-sync ArgoCD (${ARGOCD_NS}/${ARGOCD_APP})"
    run kubectl patch application "$ARGOCD_APP" -n "$ARGOCD_NS" --type merge \
      -p '{"spec":{"syncPolicy":{"automated":null}}}'
  else
    log "Aviso: Application ArgoCD no encontrada; omitiendo pausa sync"
  fi
fi

if bool "$BUILD_IMAGES"; then
  log "Build imágenes (linux/amd64)"
  if bool "$PUSH_IMAGES"; then
    run env REGISTRY="$REGISTRY" TAG="$TAG" PLATFORM=linux/amd64 \
      "${REPO_ROOT}/scripts/build-push-x86-aliothosa.sh"
  else
    need_cmd podman
    run podman build --platform linux/amd64 -t "${REGISTRY}/${BACK_NAME}:${TAG}" "${REPO_ROOT}/app/backend"
    run podman build --platform linux/amd64 -t "${REGISTRY}/${FRONT_NAME}:${TAG}" "${REPO_ROOT}/app/frontend"
  fi
else
  log "Build omitido (BUILD_IMAGES=false)"
fi

if bool "$RUN_SEED"; then
  log "Seed SQL → ${PG_POD}"
  run kubectl exec -n "$NS" "$PG_POD" -- pg_isready -U "$PG_USER" -d "$PG_DB"
  if $DRY_RUN; then
    echo "[dry-run] kubectl exec -i ... psql < ${SEED_SQL}"
  else
    kubectl exec -i -n "$NS" "$PG_POD" -- \
      psql -v ON_ERROR_STOP=1 -U "$PG_USER" -d "$PG_DB" < "$SEED_SQL"
  fi
  run kubectl exec -n "$NS" "$PG_POD" -- psql -U "$PG_USER" -d "$PG_DB" -c "
    SELECT 'clases_producto' AS tabla, COUNT(*)::text FROM clases_producto
    UNION ALL SELECT 'productos', COUNT(*)::text FROM productos
    UNION ALL SELECT 'spec_definitions', COUNT(*)::text FROM spec_definitions
    UNION ALL SELECT 'producto_specs', COUNT(*)::text FROM producto_specs;
  "
else
  log "Seed omitido (RUN_SEED=false)"
fi

if bool "$APPLY_MANIFESTS"; then
  log "Apply manifests backend + frontend"
  run kubectl apply -f "${MANIFESTS}/backend/backend-service.yaml"
  run kubectl apply -f "${MANIFESTS}/backend/backend-deployment.yaml"
  run kubectl apply -f "${MANIFESTS}/frontend/frontend-service.yaml"
  run kubectl apply -f "${MANIFESTS}/frontend/frontend-deployment.yaml"
else
  log "Apply manifests omitido (APPLY_MANIFESTS=false)"
fi

if bool "$RESTART_DEPLOYMENTS"; then
  log "Rollout restart backend + frontend"
  run kubectl rollout restart deployment/jeanos-backend -n "$NS"
  run kubectl rollout restart deployment/jeanos-frontend -n "$NS"
fi

if bool "$WAIT_ROLLOUT"; then
  log "Esperando rollouts"
  run kubectl rollout status deployment/jeanos-backend -n "$NS" --timeout=300s
  run kubectl rollout status deployment/jeanos-frontend -n "$NS" --timeout=300s
fi

log "Estado pods y services"
run kubectl get pods,svc -n "$NS" -o wide

if bool "$SHOW_INIT_LOGS"; then
  POD="$(kubectl get pods -n "$NS" -l app=jeanos-backend -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
  if [[ -n "$POD" ]]; then
    log "Logs init (${POD})"
    run kubectl logs -n "$NS" "$POD" -c wait-for-postgres --tail=40 || true
    run kubectl logs -n "$NS" "$POD" -c preload-redis --tail=60 || true
    run kubectl logs -n "$NS" "$POD" -c backend --tail=30 || true
  fi
fi

if bool "$RUN_SMOKE_TESTS" && ! $DRY_RUN; then
  log "Smoke tests dentro del cluster"
  kubectl run -n "$NS" jeanos-smoke-$RANDOM --rm -i --restart=Never \
    --image=curlimages/curl:8.5.0 -- \
    sh -c "
      set -e
      curl -sf http://jeanos-backend-service:3000/healthz >/dev/null
      curl -sf http://jeanos-backend-service:3000/readyz >/dev/null
      curl -sf http://jeanos-backend-service:3000/api/classes | head -c 200
      echo ''
      curl -sf 'http://jeanos-backend-service:3000/api/products?class=${CLASS_FILTER}' | head -c 300
      echo ''
      curl -sf -X POST http://jeanos-backend-service:3000/api/compare \
        -H 'Content-Type: application/json' \
        -d '{\"ids\":[${CMP_ID_1},${CMP_ID_2}]}' | head -c 400
      echo ''
      curl -sf http://jeanos-frontend-service/api/classes | head -c 200
      echo ''
    "

  NODE_IP="${NODE_IP:-$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || true)}"
  if [[ -n "$NODE_IP" ]]; then
    log "Smoke tests NodePort http://${NODE_IP}:${NODE_PORT}"
    curl -sf "http://${NODE_IP}:${NODE_PORT}/api/classes" | head -c 200 || echo "NodePort curl falló"
    echo ""
    echo "UI: http://${NODE_IP}:${NODE_PORT}/"
  fi
fi

log "Redeploy completado"
if bool "$PAUSE_ARGOCD_SYNC"; then
  echo ""
  echo "Recuerda: reactiva ArgoCD sync o haz git push de manifests para alinear GitOps."
fi
