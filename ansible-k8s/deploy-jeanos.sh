#!/usr/bin/env bash
# Despliegue ordenado de JeanOS Shop en Kubernetes.
# Uso: ./deploy-jeanos.sh [--skip-nfs] [--skip-seed] [--yes]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS="${SCRIPT_DIR}/manifests"
NS="jeanos-shop"
SEED_SQL="${SCRIPT_DIR}/seed-productos.sql"

SKIP_NFS=false
SKIP_SEED=false
AUTO_YES=false

for arg in "$@"; do
  case "$arg" in
    --skip-nfs) SKIP_NFS=true ;;
    --skip-seed) SKIP_SEED=true ;;
    --yes|-y) AUTO_YES=true ;;
    -h|--help)
      echo "Uso: $0 [--skip-nfs] [--skip-seed] [--yes]"
      echo "  --skip-nfs   No aplicar nfs-subdir-provisioner (si ya existe StorageClass nfs-client)"
      echo "  --skip-seed  No ejecutar seed SQL en postgres-0"
      echo "  --yes        Sin confirmación interactiva"
      exit 0
      ;;
    *)
      echo "Opción desconocida: $arg" >&2
      exit 1
      ;;
  esac
done

log() { printf '\n[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
confirm() {
  if $AUTO_YES; then return 0; fi
  read -r -p "$1 [s/N]: " ans
  [[ "${ans,,}" == "s" || "${ans,,}" == "y" || "${ans,,}" == "si" ]]
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Falta comando: $1" >&2
    exit 1
  }
}

wait_rollout() {
  local kind="$1" name="$2"
  log "Esperando rollout: $kind/$name"
  kubectl rollout status "$kind/$name" -n "$NS" --timeout=300s
}

wait_pod_label() {
  local label="$1" timeout="${2:-300}"
  log "Esperando pod Running: $label"
  kubectl wait --for=condition=ready pod -l "$label" -n "$NS" --timeout="${timeout}s"
}

need_cmd kubectl

if ! confirm "¿Desplegar JeanOS Shop en namespace ${NS}?"; then
  echo "Cancelado."
  exit 0
fi

# --- Capa 0: Namespace ---
log "Paso 0: Namespace"
kubectl apply -f "${MANIFESTS}/namespace/jeanos-shop.yaml"

# --- Capa 1: NFS provisioner ---
if ! $SKIP_NFS; then
  log "Paso 1: NFS subdir provisioner + StorageClass nfs-client"
  kubectl apply -f "${MANIFESTS}/storage/nfs-subdir-provisioner.yaml"
  kubectl wait --for=condition=available deployment/nfs-client-provisioner \
    -n nfs-provisioner --timeout=300s 2>/dev/null || {
    log "Aviso: espera manual del provisioner NFS si el deployment aún no existe"
    sleep 15
  }
else
  log "Paso 1: omitido (--skip-nfs)"
fi

kubectl get storageclass nfs-client >/dev/null 2>&1 || {
  echo "ERROR: StorageClass nfs-client no encontrada. Quita --skip-nfs o instala el provisioner." >&2
  exit 1
}

# --- Capa 2-4: PostgreSQL ---
log "Paso 2: Secret PostgreSQL"
kubectl apply -f "${MANIFESTS}/postgresql/postgres-secret.yaml"

log "Paso 3: Service + StatefulSet PostgreSQL"
kubectl apply -f "${MANIFESTS}/postgresql/postgres-service.yaml"
kubectl apply -f "${MANIFESTS}/postgresql/postgres-statefulset.yaml"

wait_rollout statefulset postgres

log "Comprobando PVC"
kubectl get pvc -n "$NS"
kubectl wait --for=jsonpath='{.status.phase}'=Bound pvc -n "$NS" --timeout=300s 2>/dev/null || {
  log "Aviso: algún PVC aún no está Bound; revisa nfs-provisioner y exports NFS"
}

kubectl exec -n "$NS" postgres-0 -- pg_isready -U jeanosadmin -d jeanosdb

# --- Seed (antes de Redis/backend; incluye clases, productos y specs) ---
if ! $SKIP_SEED; then
  log "Paso 4: Seed catálogo SQL (${SEED_SQL##*/})"
  kubectl exec -i -n "$NS" postgres-0 -- \
    psql -v ON_ERROR_STOP=1 -U jeanosadmin -d jeanosdb < "$SEED_SQL"
else
  log "Paso 4: seed omitido (--skip-seed) — el backend exige clases_producto, productos, spec_definitions y producto_specs con datos"
fi

# --- Capa 5: Redis ---
log "Paso 5: Redis"
kubectl apply -f "${MANIFESTS}/redis/redis-configmap.yaml"
kubectl apply -f "${MANIFESTS}/redis/redis-deployment.yaml"
kubectl apply -f "${MANIFESTS}/redis/redis-service.yaml"
wait_rollout deployment redis
kubectl exec -n "$NS" deploy/redis -- redis-cli ping | grep -q PONG

# --- Capa 6: Backend ---
log "Paso 6: Backend"
kubectl apply -f "${MANIFESTS}/backend/backend-service.yaml"
kubectl apply -f "${MANIFESTS}/backend/backend-deployment.yaml"
wait_rollout deployment jeanos-backend

# --- Capa 7: Frontend ---
log "Paso 7: Frontend"
kubectl apply -f "${MANIFESTS}/frontend/frontend-service.yaml"
kubectl apply -f "${MANIFESTS}/frontend/frontend-deployment.yaml"
wait_rollout deployment jeanos-frontend

# --- Resumen ---
log "Despliegue completado"
kubectl get pods,svc,pvc -n "$NS" -o wide

NODE_IP="$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || true)"
if [[ -n "$NODE_IP" ]]; then
  echo ""
  echo "Frontend (NodePort 30080): http://${NODE_IP}:30080/"
  echo "API vía proxy:            http://${NODE_IP}:30080/api/products"
  echo ""
  echo "Recoger evidencias: docs/evidencias/collect-evidence.sh"
fi
