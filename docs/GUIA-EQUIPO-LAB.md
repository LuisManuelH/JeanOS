# Guía del equipo — JeanOS Lab (Semanas 2, 3 y 4)

Rama de referencia: **`lab/equipo`** (configuración probada en cluster **aarch64** con NFS `nfs-client`).

Cada compañero debe **personalizar IPs y Docker Hub** antes de desplegar. No uses las IPs de otro compañero si tu red es distinta.

---

## 1. Clonar y usar la rama del equipo

```bash
git clone git@github.com:aliothosa/JeanOS.git
cd JeanOS
git fetch origin
git checkout lab/equipo
```

---

## 2. Personalizar IPs y Docker Hub (obligatorio)

| Dato | Ejemplo Emmanuel | Tú debes poner |
|------|------------------|----------------|
| Master | 172.16.50.135 | IP de tu `k8s-master01` |
| Worker1 | 172.16.50.136 | IP de tu `k8s-worker01` |
| Worker2 | 172.16.50.137 | IP de tu `k8s-worker02` |
| Docker Hub | `emmanuelmal2` | **Tu usuario** |

### Opción A — Script (recomendado, desde Mac o Linux)

```bash
chmod +x scripts/personalizar-lab.sh
./scripts/personalizar-lab.sh IP_MASTER IP_WORKER1 IP_WORKER2 TU_USUARIO_DOCKERHUB
```

### Opción B — Manual

Editar estos archivos:

1. `ansible-k8s/inventory/hosts.ini` (copiar desde `hosts.ini.example`)
2. `ansible-k8s/playbooks/nfs-setup.yml` → `nfs_server_ip`
3. `ansible-k8s/manifests/storage/nfs-subdir-provisioner.yaml` → IP del master (2 lugares)
4. `ansible-k8s/manifests/monitoring/prometheus/configmap.yaml` → targets `:9100` de los 3 nodos
5. `ansible-k8s/manifests/backend/backend-deployment.yaml` → imagen `docker.io/TU_USUARIO/jeanos-backend:v1`
6. `ansible-k8s/manifests/frontend/frontend-deployment.yaml` → imagen `docker.io/TU_USUARIO/jeanos-frontend:v1`

---

## 3. Arquitectura del cluster (recordatorio)

| Máquina | Rol | Herramientas |
|---------|-----|--------------|
| Mac | Ansible, Podman build | No lleva `kubectl` del cluster |
| Master | Control plane, NFS, `kubectl` | `/root/.kube/config` |
| Workers | Pods de aplicación | Sin `kubectl` (salvo que copies config) |

**Cluster ARM64 (`aarch64`):** construir imágenes en Mac con:

```bash
podman build --platform linux/arm64 -t docker.io/TU_USUARIO/jeanos-backend:v1 app/backend
podman push docker.io/TU_USUARIO/jeanos-backend:v1
# Igual para jeanos-frontend en app/frontend
```

---

## 4. Semana 2 — JeanOS Shop

Desde el **master** (repo en `/root/JeanOS`):

```bash
# Firewall red pods (si no corrió el playbook actualizado)
for port in 9100 30080 30300 30900; do
  firewall-cmd --add-port=${port}/tcp --permanent
done
firewall-cmd --permanent --zone=trusted --add-source=10.244.0.0/16
firewall-cmd --reload
```

```bash
cd /root/JeanOS/ansible-k8s
./deploy-jeanos.sh --yes
kubectl get pods -n jeanos-shop -o wide
```

Tienda: `http://IP_WORKER:30080/`

---

## 5. Semana 3 — Monitoreo

Orden en el master (`M=ansible-k8s/manifests/monitoring`):

1. `namespace.yaml`
2. `node-exporter/daemonset.yaml`
3. `prometheus/kube-state-metrics-*.yaml` (3 archivos)
4. `loki/*`
5. `promtail/*`
6. `prometheus/*` (rbac, pvc, configmap, deployment, service)
7. `grafana/*`

| URL | Puerto |
|-----|--------|
| Prometheus | `:30900` |
| Grafana (`admin` / `jeanos2026`) | `:30300` |
| Tienda | `:30080` |

**Reloj:** hora del Mac y VMs debe coincidir (si Graph vacío en Prometheus, sincronizar con `date -s`).

**Prueba métricas backend** (desde master):

```bash
kubectl exec -n jeanos-shop deploy/jeanos-backend -- \
  wget -qO- http://127.0.0.1:3000/metrics | head -5
```

Detalle: `docs/semana-3-monitoring.md`

---

## 6. Semana 4 — Tekton + ArgoCD

Carpeta: `examples/tekton-argocd/` (ya usa `nfs-client`, no `nfs-csi`).

1. Copiar al master: `scp -r examples/tekton-argocd root@IP_MASTER:/root/JeanOS/examples/`
2. Tekton + label `pod-security=privileged` en `tekton-pipelines`
3. Secret Docker Hub en `tekton-pipelines`
4. Editar `pipelinerun-demo.yaml` y `argocd-application.yaml` (repo GitHub + imagen)
5. ArgoCD UI: `https://IP_NODO:30443`

**CLI en ARM64:**

- `tkn_*_Linux_arm64.tar.gz`
- `argocd-linux-arm64`

Guía completa: `examples/tekton-argocd/README.md`

---

## 7. Firewall mínimo (todos los nodos)

```bash
for port in 9100 30080 30300 30900 30443 31080; do
  firewall-cmd --add-port=${port}/tcp --permanent
done
firewall-cmd --permanent --zone=trusted --add-source=10.244.0.0/16
firewall-cmd --reload
```

---

## 8. Subir cambios propios (sin pisar al equipo)

```bash
git checkout lab/equipo
git pull origin lab/equipo
git checkout -b lab/tu-nombre
# personalizar con el script
git add ...
git commit -m "Lab personalizado: IPs y Docker Hub"
git push -u origin lab/tu-nombre
```

No hagas merge de IPs distintas a `lab/equipo` sin coordinar.

---

## 9. Referencia rápida — Emmanuel (lab probado)

| Item | Valor |
|------|--------|
| IPs | .135 master, .136 worker1, .137 worker2 |
| Imágenes | `emmanuelmal2/jeanos-backend:v1`, `emmanuelmal2/jeanos-frontend:v1` |
| StorageClass | `nfs-client` |
| Arquitectura nodos | `aarch64` |
