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

### Opción A — Script (en el **master** o en PC con bash: Linux / WSL / Git Bash)

```bash
# Normalmente en el master, dentro de /root/JeanOS:
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
| **Master** | Control plane, NFS, `kubectl`, **git clone del repo** | `/root/.kube/config` — aquí aplicas casi todo |
| Workers | Pods de aplicación | Sin `kubectl` (salvo que copies config) |
| PC de casa (opcional) | Editar repo, `scp`, navegador | Windows + WSL/WinSCP, o Linux; **no obligatorio** |

**Cluster ARM64 (`aarch64`):** imágenes `linux/arm64`. Opciones:

1. **Tekton en el cluster** (Semana 4) — no necesitas PC para build.
2. **En el master o un worker** (si tienen `podman`):

```bash
cd /root/JeanOS
podman build --platform linux/arm64 -t docker.io/TU_USUARIO/jeanos-backend:v1 app/backend
podman push docker.io/TU_USUARIO/jeanos-backend:v1
# Igual para jeanos-frontend en app/frontend
```

3. PC con Podman/Docker (`--platform linux/arm64`) solo si ya lo usas en casa.

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

## 5. Semana 3 — Monitoreo + dashboard Grafana

**Guía copiable para el equipo (sin Mac):** **`docs/SEMANA-3-REPLICAR.md`** — **Ruta A = todo en el master**

Resumen del flujo habitual (solo VMs):

| Paso | Dónde | Acción |
|------|-------|--------|
| 1 | Master | `git clone` / `git pull` `lab/equipo` + `./scripts/personalizar-lab.sh IP_MASTER IP_W1 IP_W2 DOCKERHUB` |
| 2 | Master | Bloque `kubectl apply` de `SEMANA-3-REPLICAR.md` (orden namespace → grafana) |
| 3 | Navegador (Windows/Linux) | `http://IP_WORKER:30300` → **Dashboards → JeanOS → jeanOS — Hardware del cluster** |

Opcional: preparar en PC y `scp` al master (**Ruta B** en la misma guía).

Si ya tenías Grafana sin dashboard: en el master solo aplicas los 3 YAML de `grafana/` (provider + dashboards + deployment) y `kubectl rollout restart deployment/grafana -n monitoring` (ver sección **Paso 4** de `SEMANA-3-REPLICAR.md`).

| URL | Puerto |
|-----|--------|
| Prometheus | `:30900` |
| Grafana (`admin` / `jeanos2026`) | `:30300` |
| Tienda | `:30080` |

**Reloj:** hora de las VMs (y tu PC si usas navegador local) debe coincidir (si gráficas vacías en Prometheus, `date` / NTP en los nodos).

Detalle largo / troubleshooting: `docs/semana-3-monitoring.md` · manifiestos: `ansible-k8s/manifests/monitoring/README.md`

---

## 6. Semana 4 — Tekton + ArgoCD

Manifests del equipo: **`ansible-k8s/manifests/semana-4/`** + script **`ansible-k8s/deploy-semana4.sh`**.

1. Personalizar: `./scripts/personalizar-lab.sh IP_MASTER IP_W1 IP_W2 USUARIO_DOCKERHUB`
2. `cd ansible-k8s && cp lab.env.example lab.env` → editar `GITHUB_REPO_URL`, `DOCKER_TOKEN`, etc.
3. Copiar al master: `scp -r ansible-k8s root@IP_MASTER:/root/JeanOS/`
4. En el master: `chmod +x deploy-semana4.sh && ./deploy-semana4.sh --yes`
5. ArgoCD UI: `https://IP_NODO:30443` — app **`jeanos-shop-gitops`** sincroniza la tienda en `jeanos-shop` (`:30080`)

**CLI en ARM64:** `tkn_*_Linux_arm64.tar.gz`, `argocd-linux-arm64`

Guías: **`docs/SEMANA-4-REPLICAR.md`** · conceptos: `examples/tekton-argocd/README.md`

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
