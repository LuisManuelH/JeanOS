#!/usr/bin/env bash
# Personaliza IPs y usuario Docker Hub en los manifests del lab.
# Uso: ./scripts/personalizar-lab.sh 172.16.50.135 172.16.50.136 172.16.50.137 emmanuelmal2

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MASTER_IP="${1:-}"
WORKER1_IP="${2:-}"
WORKER2_IP="${3:-}"
DOCKER_USER="${4:-}"

if [[ -z "$MASTER_IP" || -z "$WORKER1_IP" || -z "$WORKER2_IP" || -z "$DOCKER_USER" ]]; then
  echo "Uso: $0 IP_MASTER IP_WORKER1 IP_WORKER2 USUARIO_DOCKERHUB"
  echo "Ej:  $0 172.16.50.135 172.16.50.136 172.16.50.137 emmanuelmal2"
  exit 1
fi

echo "==> Inventario Ansible"
cp "${ROOT}/ansible-k8s/inventory/hosts.ini.example" "${ROOT}/ansible-k8s/inventory/hosts.ini"
sed -i.bak "s/IP_MASTER/${MASTER_IP}/g; s/IP_WORKER1/${WORKER1_IP}/g; s/IP_WORKER2/${WORKER2_IP}/g" \
  "${ROOT}/ansible-k8s/inventory/hosts.ini"
rm -f "${ROOT}/ansible-k8s/inventory/hosts.ini.bak"

echo "==> NFS (provisioner + playbook)"
sed -i.bak "s/nfs_server_ip: \".*\"/nfs_server_ip: \"${MASTER_IP}\"/" \
  "${ROOT}/ansible-k8s/playbooks/nfs-setup.yml"
sed -i.bak "s|value: [0-9.]*$|value: ${MASTER_IP}|" \
  "${ROOT}/ansible-k8s/manifests/storage/nfs-subdir-provisioner.yaml"
sed -i.bak "s|server: [0-9.]*$|server: ${MASTER_IP}|" \
  "${ROOT}/ansible-k8s/manifests/storage/nfs-subdir-provisioner.yaml"
rm -f "${ROOT}/ansible-k8s/playbooks/nfs-setup.yml.bak" \
  "${ROOT}/ansible-k8s/manifests/storage/nfs-subdir-provisioner.yaml.bak"

echo "==> Prometheus node-exporter targets"
perl -i.bak -0pe "s/- '.*:9100'   # k8s-master01/- '${MASTER_IP}:9100'   # k8s-master01/;
  s/- '.*:9100'   # k8s-worker01/- '${WORKER1_IP}:9100'   # k8s-worker01/;
  s/- '.*:9100'   # k8s-worker02/- '${WORKER2_IP}:9100'   # k8s-worker02/;" \
  "${ROOT}/ansible-k8s/manifests/monitoring/prometheus/configmap.yaml"
rm -f "${ROOT}/ansible-k8s/manifests/monitoring/prometheus/configmap.yaml.bak"

echo "==> Imágenes JeanOS (backend + frontend)"
for f in \
  "${ROOT}/ansible-k8s/manifests/backend/backend-deployment.yaml" \
  "${ROOT}/ansible-k8s/manifests/frontend/frontend-deployment.yaml"; do
  sed -i.bak "s|docker.io/[^/]*/jeanos-|docker.io/${DOCKER_USER}/jeanos-|g" "$f"
  rm -f "${f}.bak"
done

echo "Listo. Revisa: ansible-k8s/inventory/hosts.ini y grep -r ${DOCKER_USER} ansible-k8s/manifests"
