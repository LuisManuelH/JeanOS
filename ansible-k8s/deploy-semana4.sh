#!/usr/bin/env bash
# Semana 4 — Tekton (CI) + ArgoCD (GitOps)
# Uso: cp lab.env.example lab.env && editar → ./deploy-semana4.sh --yes
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
S4="${SCRIPT_DIR}/manifests/semana-4"
TEKTON="${S4}/tekton"
ARGOCD_MANIFEST="${S4}/argocd/application.yaml"
ARGOCD_ADMIN_PW_MANIFEST="${S4}/argocd/argocd-admin-password.yaml"
LAB_ENV="${SCRIPT_DIR}/lab.env"
TEKTON_RELEASE="https://storage.googleapis.com/tekton-releases/pipeline/latest/release.yaml"
ARGOCD_INSTALL="https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml"

AUTO_YES=false
SKIP_TEKTON=false
SKIP_PIPELINE=false
SKIP_ARGOCD=false

for arg in "$@"; do
  case "$arg" in
    --yes|-y) AUTO_YES=true ;;
    --skip-tekton) SKIP_TEKTON=true ;;
    --skip-pipeline) SKIP_PIPELINE=true ;;
    --skip-argocd) SKIP_ARGOCD=true ;;
    -h|--help)
      cat <<'EOF'
Uso: ./deploy-semana4.sh [--yes] [--skip-tekton] [--skip-pipeline] [--skip-argocd]

  --yes            Sin confirmaciones
  --skip-tekton    No instalar Tekton (ya instalado)
  --skip-pipeline  No lanzar PipelineRun
  --skip-argocd    No instalar ArgoCD ni Application

Requisitos: lab.env (copiar desde lab.env.example), nfs-client, kubectl en master.
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
confirm() {
  if $AUTO_YES; then return 0; fi
  read -r -p "$1 [s/N]: " ans
  [[ "${ans,,}" == "s" || "${ans,,}" == "y" || "${ans,,}" == "si" ]]
}

if [[ ! -f "${LAB_ENV}" ]]; then
  echo "Falta ${LAB_ENV}. Copia lab.env.example y edita GITHUB_REPO_URL, DOCKER_IMAGE, DOCKER_USERNAME." >&2
  exit 1
fi
# shellcheck source=/dev/null
source "${LAB_ENV}"

: "${GITHUB_REPO_URL:?Define GITHUB_REPO_URL en lab.env}"
: "${DOCKER_BACKEND_IMAGE:?Define DOCKER_BACKEND_IMAGE en lab.env}"
: "${DOCKER_FRONTEND_IMAGE:?Define DOCKER_FRONTEND_IMAGE en lab.env}"
: "${DOCKER_USERNAME:?Define DOCKER_USERNAME en lab.env}"
GITHUB_REVISION="${GITHUB_REVISION:-lab/equipo}"
PIPELINE_RUN_NAME="${PIPELINE_RUN_NAME:-jeanos-shop-build-run-1}"
ARGOCD_ADMIN_PASSWORD="${ARGOCD_ADMIN_PASSWORD:-jeanos2026}"

set_argocd_admin_password() {
  if [[ "${ARGOCD_ADMIN_PASSWORD}" == "jeanos2026" ]]; then
    log "Contraseña ArgoCD desde manifest (admin / jeanos2026)"
    kubectl apply -f "${ARGOCD_ADMIN_PW_MANIFEST}"
    return
  fi
  if ! command -v htpasswd >/dev/null 2>&1; then
    echo "Para otra ARGOCD_ADMIN_PASSWORD instala htpasswd (httpd-tools) o deja jeanos2026." >&2
    exit 1
  fi
  local hash
  hash="$(htpasswd -nbBC 10 "" "${ARGOCD_ADMIN_PASSWORD}" | tr -d '\n:' | sed 's/\$2y/\$2a/')"
  kubectl patch secret argocd-secret -n argocd --type merge -p \
    "$(printf '{"stringData":{"admin.password":"%s","admin.passwordMtime":"%s"}}' \
      "${hash}" "$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S%z)")"
}

render() {
  local src="$1"
  sed -e "s|__GITHUB_REPO_URL__|${GITHUB_REPO_URL}|g" \
      -e "s|__GITHUB_REVISION__|${GITHUB_REVISION}|g" \
      -e "s|__DOCKER_BACKEND_IMAGE__|${DOCKER_BACKEND_IMAGE}|g" \
      -e "s|__DOCKER_FRONTEND_IMAGE__|${DOCKER_FRONTEND_IMAGE}|g" \
      -e "s|jeanos-shop-build-run-1|${PIPELINE_RUN_NAME}|g" \
      "${src}"
}

cleanup_legacy_argocd_apps() {
  for app in mi-tienda semana4-gitops-landing; do
    kubectl delete application "${app}" -n argocd --wait=false 2>/dev/null || true
  done
  for ns in demo semana4-gitops; do
    kubectl delete ns "${ns}" --wait=false 2>/dev/null || true
  done
}

log "Comprobar StorageClass nfs-client"
kubectl get storageclass nfs-client >/dev/null

if ! $SKIP_TEKTON; then
  log "Instalar Tekton Pipelines"
  if confirm "¿Aplicar Tekton release.yaml?"; then
    kubectl apply -f "${TEKTON_RELEASE}"
    log "Etiquetar namespace tekton-pipelines (PodSecurity privileged)"
    kubectl label namespace tekton-pipelines \
      pod-security.kubernetes.io/enforce=privileged \
      pod-security.kubernetes.io/warn=privileged \
      pod-security.kubernetes.io/audit=privileged \
      --overwrite 2>/dev/null || true
    log "Esperando pods tekton-pipelines..."
    kubectl wait --for=condition=Ready pods -l app.kubernetes.io/part-of=tekton-pipelines \
      -n tekton-pipelines --timeout=300s 2>/dev/null || kubectl get pods -n tekton-pipelines
  fi
fi

log "Secret Docker Hub en tekton-pipelines"
if [[ -z "${DOCKER_TOKEN:-}" ]]; then
  echo "Define DOCKER_TOKEN en lab.env (Docker Hub Access Token) o exporta DOCKER_TOKEN antes de ejecutar." >&2
  exit 1
fi
kubectl create secret docker-registry docker-credentials \
  --docker-server=https://index.docker.io/v1/ \
  --docker-username="${DOCKER_USERNAME}" \
  --docker-password="${DOCKER_TOKEN}" \
  -n tekton-pipelines \
  --dry-run=client -o yaml | kubectl apply -f -

log "Tasks y Pipeline Tekton"
kubectl apply -f "${TEKTON}/task-git-clone.yaml"
kubectl apply -f "${TEKTON}/task-build-push.yaml"
kubectl apply -f "${TEKTON}/pipeline-build-jeanos.yaml"

if ! $SKIP_PIPELINE; then
  log "PipelineRun ${PIPELINE_RUN_NAME}"
  if kubectl get pipelinerun "${PIPELINE_RUN_NAME}" -n tekton-pipelines >/dev/null 2>&1; then
    echo "Ya existe ${PIPELINE_RUN_NAME}. Borra con:" >&2
    echo "  kubectl delete pipelinerun ${PIPELINE_RUN_NAME} -n tekton-pipelines" >&2
    exit 1
  fi
  render "${TEKTON}/pipelinerun.yaml" | kubectl apply -f -
  echo "Logs: tkn pipelinerun logs ${PIPELINE_RUN_NAME} -f -n tekton-pipelines"
fi

if ! $SKIP_ARGOCD; then
  log "Instalar ArgoCD"
  if confirm "¿Aplicar ArgoCD install.yaml?"; then
    kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
    kubectl apply -n argocd -f "${ARGOCD_INSTALL}" --server-side --force-conflicts
    log "Esperando pods argocd (puede tardar 3-5 min)..."
    kubectl wait --for=condition=Available deployment -l app.kubernetes.io/part-of=argocd \
      -n argocd --timeout=600s 2>/dev/null || kubectl get pods -n argocd
    log "Exponer ArgoCD NodePort 30443"
    kubectl patch svc argocd-server -n argocd --type merge -p \
      '{"spec":{"type":"NodePort","ports":[{"port":443,"nodePort":30443,"targetPort":8080,"protocol":"TCP","name":"https"}]}}'
    set_argocd_admin_password
  fi

  cleanup_legacy_argocd_apps
  log "ArgoCD Application jeanos-shop-gitops → namespace jeanos-shop"
  kubectl apply -f "${ARGOCD_MANIFEST}"
fi

log "Semana 4 manifests aplicados."
echo "  ArgoCD:      https://<IP-NODO>:30443  (admin / ${ARGOCD_ADMIN_PASSWORD})"
echo "  jeanOS Shop: http://<IP-NODO>:30080  (app jeanos-shop-gitops en ArgoCD)"
echo "  Demo clase:  comparador Redis vs Postgres en la tienda (proyecto final G-09)"
