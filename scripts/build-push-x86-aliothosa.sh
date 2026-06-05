#!/usr/bin/env bash
# Construye y publica imágenes jeanOS para linux/amd64 en docker.io/aliothosa.
# Requiere: podman o docker, sesión en Docker Hub (podman login docker.io).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REGISTRY="${REGISTRY:-docker.io/aliothosa}"
TAG="${TAG:-v1}"
PLATFORM="${PLATFORM:-linux/amd64}"
BACK_NAME="${DOCKER_BACKEND_IMAGE:-jeanos-backend}"
FRONT_NAME="${DOCKER_FRONTEND_IMAGE:-jeanos-frontend}"

if command -v podman >/dev/null 2>&1; then
  BUILDER=podman
elif command -v docker >/dev/null 2>&1; then
  BUILDER=docker
else
  echo "Instala podman o docker." >&2
  exit 1
fi

if ! "${BUILDER}" login --get-login docker.io >/dev/null 2>&1; then
  echo "Inicia sesión: ${BUILDER} login docker.io" >&2
  exit 1
fi

build_push() {
  local context="$1"
  local name="$2"
  local image="${REGISTRY}/${name}:${TAG}"
  echo "==> ${image} (${PLATFORM})"
  "${BUILDER}" build --platform "${PLATFORM}" -t "${image}" "${context}"
  "${BUILDER}" push "${image}"
}

build_push "${ROOT}/app/backend" "${BACK_NAME}"
build_push "${ROOT}/app/frontend" "${FRONT_NAME}"

echo "Listo:"
echo "  ${REGISTRY}/${BACK_NAME}:${TAG}"
echo "  ${REGISTRY}/${FRONT_NAME}:${TAG}"
