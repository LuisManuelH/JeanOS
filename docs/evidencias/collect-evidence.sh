#!/usr/bin/env bash
# Guarda evidencias de despliegue JeanOS Shop en docs/evidencias/<timestamp>/
# Uso: ./collect-evidence.sh [--node-ip IP]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
NS="jeanos-shop"
TS="$(date +%Y%m%d-%H%M%S)"
OUT="${SCRIPT_DIR}/${TS}"
NODE_IP=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --node-ip)
      NODE_IP="$2"
      shift 2
      ;;
    -h|--help)
      echo "Uso: $0 [--node-ip IP]"
      exit 0
      ;;
    *)
      echo "Opción desconocida: $1" >&2
      exit 1
      ;;
  esac
done

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Falta comando: $1" >&2
    exit 1
  }
}

need_cmd kubectl
mkdir -p "$OUT"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }

log "Guardando evidencias en: $OUT"

{
  echo "timestamp=$TS"
  echo "namespace=$NS"
  echo "repo_root=$REPO_ROOT"
  kubectl config current-context 2>/dev/null || echo "context=unknown"
} > "${OUT}/00-meta.txt"

kubectl get nodes -o wide > "${OUT}/01-nodes.txt" 2>&1
kubectl get ns > "${OUT}/02-namespaces.txt" 2>&1
kubectl get pods,deploy,sts,svc,cm,secret,pvc -n nfs-provisioner -o wide > "${OUT}/03-nfs-provisioner.txt" 2>&1
kubectl get storageclass -o wide > "${OUT}/04-storageclass.txt" 2>&1
kubectl get all,pvc,configmap,secret -n "$NS" -o wide > "${OUT}/05-jeanos-shop-all.txt" 2>&1
kubectl get events -n "$NS" --sort-by='.lastTimestamp' > "${OUT}/06-events-jeanos-shop.txt" 2>&1
kubectl get events -n nfs-provisioner --sort-by='.lastTimestamp' > "${OUT}/07-events-nfs.txt" 2>&1

kubectl describe statefulset postgres -n "$NS" > "${OUT}/10-describe-postgres-sts.txt" 2>&1
kubectl logs postgres-0 -n "$NS" --tail=200 > "${OUT}/11-postgres-logs.txt" 2>&1 || true
kubectl exec -n "$NS" postgres-0 -- psql -U jeanosadmin -d jeanosdb -c '\dt' > "${OUT}/12-postgres-tables.txt" 2>&1 || true
kubectl exec -n "$NS" postgres-0 -- psql -U jeanosadmin -d jeanosdb -c 'SELECT * FROM productos ORDER BY id;' > "${OUT}/13-productos-data.txt" 2>&1 || true

kubectl describe deploy redis -n "$NS" > "${OUT}/20-describe-redis.txt" 2>&1
kubectl logs -n "$NS" -l app=redis --tail=100 > "${OUT}/21-redis-logs.txt" 2>&1 || true
kubectl exec -n "$NS" deploy/redis -- redis-cli ping > "${OUT}/22-redis-ping.txt" 2>&1 || true

kubectl describe deploy jeanos-backend -n "$NS" > "${OUT}/30-describe-backend-deploy.txt" 2>&1
while IFS= read -r pod; do
  [[ -z "$pod" ]] && continue
  base="$(basename "$pod")"
  kubectl describe "$pod" -n "$NS" > "${OUT}/31-${base}-describe.txt" 2>&1 || true
  kubectl logs "$pod" -n "$NS" -c wait-for-postgres --tail=100 > "${OUT}/32-${base}-init-postgres.log" 2>&1 || true
  kubectl logs "$pod" -n "$NS" -c wait-for-redis --tail=50 > "${OUT}/33-${base}-init-redis.log" 2>&1 || true
  kubectl logs "$pod" -n "$NS" -c preload-redis --tail=100 > "${OUT}/33b-${base}-init-preload-redis.log" 2>&1 || true
  kubectl logs "$pod" -n "$NS" -c backend --tail=200 > "${OUT}/34-${base}-backend.log" 2>&1 || true
done < <(kubectl get pods -n "$NS" -l app=jeanos-backend -o name 2>/dev/null)

CURL_POD="curl-readyz-${TS}"
if kubectl run "$CURL_POD" --restart=Never -n "$NS" \
  --image=curlimages/curl:latest --command -- sleep 120 >/dev/null 2>&1; then
  kubectl wait --for=condition=ready "pod/${CURL_POD}" -n "$NS" --timeout=90s >/dev/null 2>&1 || true
  kubectl exec -n "$NS" "$CURL_POD" -- \
    curl -sS "http://jeanos-backend-service:3000/readyz" > "${OUT}/35-backend-readyz.json" 2>&1 || true
  kubectl delete pod "$CURL_POD" -n "$NS" --wait=false >/dev/null 2>&1 || true
else
  echo "No se pudo crear pod temporal para readyz" > "${OUT}/35-backend-readyz.json"
fi

kubectl describe deploy jeanos-frontend -n "$NS" > "${OUT}/40-describe-frontend-deploy.txt" 2>&1
kubectl get svc jeanos-frontend-service -n "$NS" -o yaml > "${OUT}/41-frontend-service.yaml" 2>&1

if [[ -z "$NODE_IP" ]]; then
  NODE_IP="$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || true)"
fi

{
  echo "NODE_IP=${NODE_IP:-unset}"
  if [[ -n "$NODE_IP" ]]; then
    curl -sS -w "\nHTTP %{http_code}\n" "http://${NODE_IP}:30080/" || true
    echo "---"
    curl -sS "http://${NODE_IP}:30080/api/products" || true
    echo ""
    echo "---"
    curl -sS -X POST "http://${NODE_IP}:30080/api/compare" \
      -H "Content-Type: application/json" \
      -d '{"ids":[1,2]}' || true
  else
    echo "Sin NODE_IP: omitidas pruebas HTTP externas"
  fi
} > "${OUT}/50-curl-frontend.txt" 2>&1

kubectl get deploy,sts,svc,cm,secret,pvc -n "$NS" -o yaml > "${OUT}/60-manifests-live-snapshot.yaml" 2>&1

ARCHIVE="${SCRIPT_DIR}/jeanos-deploy-evidencia-${TS}.tar.gz"
tar -czf "$ARCHIVE" -C "$SCRIPT_DIR" "$TS"

log "Listo."
echo "  Carpeta:  $OUT"
echo "  Archivo:  $ARCHIVE"
echo ""
echo "Archivos clave para Semana 2:"
echo "  - 05-jeanos-shop-all.txt"
echo "  - 32-*-init-postgres.log / 33-*-init-redis.log"
echo "  - 34-*-backend.log"
echo "  - 50-curl-frontend.txt"
