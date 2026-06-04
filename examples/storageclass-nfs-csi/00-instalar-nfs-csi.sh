#!/bin/bash
# ============================================================
# Instalar NFS CSI Driver para aprovisionamiento dinámico
# Permite crear PVs automáticamente sin configuración manual
# Repo: https://github.com/kubernetes-csi/csi-driver-nfs
# ============================================================

set -e

echo "=== Paso 1: Instalar nfs-utils en todos los nodos ==="
# Necesario para que los nodos puedan montar NFS
ansible all -i /root/kubernetes/ansible-k8s/inventory/hosts.ini \
  -m shell -a "dnf install -y nfs-utils" --become

echo ""
echo "=== Paso 2: Verificar conectividad con NFS ==="
showmount -e 192.168.121.135 || {
  echo "ERROR: No se puede conectar al servidor NFS 192.168.121.135"
  exit 1
}

echo ""
echo "=== Paso 3: Instalar NFS CSI Driver via Helm ==="
helm repo add csi-driver-nfs \
  https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/charts
helm repo update

helm upgrade --install csi-driver-nfs csi-driver-nfs/csi-driver-nfs \
  --namespace kube-system \
  --set kubeletDir=/var/lib/kubelet \
  --version v4.9.0 \
  --wait

echo ""
echo "=== Paso 4: Verificar instalación ==="
kubectl get pods -n kube-system | grep nfs

echo ""
echo "=== Paso 5: Verificar CSI Driver registrado ==="
kubectl get csidrivers | grep nfs

echo ""
echo "=== NFS CSI Driver instalado correctamente ==="
echo "Siguiente paso: kubectl apply -f 01-storageclass-nfs.yaml"
