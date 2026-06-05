# Semana 4 — CI/CD Tekton + ArgoCD (jeanOS Shop)

Guía paso a paso para replicar **Semana 4** cuando **ya tienes Semana 3** (Prometheus, Grafana, Loki, dashboard JeanOS) y la tienda en `jeanos-shop`.

- **Prerequisito Semana 3:** `docs/SEMANA-3-REPLICAR.md`
- **Tutorial de clase (solo referencia):** `examples/tekton-argocd/`
- **Proyecto jeanOS:** `ansible-k8s/manifests/semana-4/` + `ansible-k8s/deploy-semana4.sh`

---

## Qué añade Semana 4 (sin repetir Semana 3)

| Pieza | Función |
|-------|---------|
| **Tekton** | Clona el repo, construye `app/backend` y `app/frontend`, push a Docker Hub |
| **ArgoCD** | Sincroniza **solo** `backend/` y `frontend/` en `jeanos-shop` desde Git |
| **Tienda :30080** | Sigue siendo el demo del proyecto (comparador Redis vs Postgres) |

Postgres, Redis, NFS y el namespace `monitoring` **no** los gestiona ArgoCD; siguen como en Semana 2/3.

---

## Ramas del repo

| Rama | Cluster | Imágenes por defecto | Build local |
|------|---------|----------------------|-------------|
| `lab/equipo` | ARM64 (`aarch64`) | `TU_USUARIO/jeanos-*:v1` | `podman build --platform linux/arm64` |
| `lab/x86-aliothosa` | x86_64 (`amd64`) | `aliothosa/jeanos-*:v1` | `./scripts/build-push-x86-aliothosa.sh` |

Usa **una sola rama** en todo el flujo (clone, `lab.env`, ArgoCD `targetRevision`).

---

## Antes de empezar (checklist)

Marca solo lo que **no** hayas validado ya tras Semana 3:

- [ ] `kubectl get nodes` → todos **Ready** (en el master)
- [ ] `kubectl get storageclass nfs-client` → existe
- [ ] Semana 2: pods en `jeanos-shop` (backend, frontend, postgres, redis)
- [ ] Semana 3: pods en `monitoring` (prometheus, grafana, loki, promtail, node-exporter)
- [ ] Tienda responde: `http://IP_WORKER:30080`
- [ ] Grafana responde: `http://IP_WORKER:30300` (`admin` / `jeanos2026`)
- [ ] Cuenta **Docker Hub** + **Access Token** (para Tekton push)
- [ ] Repo en GitHub accesible desde el cluster (URL pública o token si es privado)
- [ ] Imágenes de la tienda **ya publicadas** para tu arquitectura *o* vas a construirlas con Tekton en este paso

Comprobación rápida en el master:

```bash
kubectl get pods -n jeanos-shop
kubectl get pods -n monitoring
kubectl get pods -n nfs-provisioner
```

---

## ¿Solo VMs del lab? (Ruta A vs B)

| Ruta | Dónde preparas | Dónde ejecutas |
|------|----------------|----------------|
| **A — Recomendada** | Master (`git pull` + `lab.env`) | Master (`./deploy-semana4.sh`) |
| **B — Opcional** | PC → `scp` al master | Master |

El navegador sirve para ArgoCD (`https://IP:30443`) y la tienda (`http://IP:30080`).

---

## Paso 1 — Código y rama correcta

Sustituye IPs y rama según tu lab.

```bash
export IP_MASTER=192.168.41.154      # tu k8s-master01
export IP_WORKER1=192.168.41.157     # worker (NodePorts)
export IP_WORKER2=192.168.41.158
export DOCKERHUB=aliothosa           # tu usuario Docker Hub
export GIT_BRANCH=lab/x86-aliothosa  # o lab/equipo en ARM
```

### Ruta A — En el master

```bash
ssh root@${IP_MASTER}

cd /root/JeanOS
git fetch origin
git checkout ${GIT_BRANCH}
git pull origin ${GIT_BRANCH}

chmod +x scripts/personalizar-lab.sh ansible-k8s/deploy-semana4.sh
./scripts/personalizar-lab.sh ${IP_MASTER} ${IP_WORKER1} ${IP_WORKER2} ${DOCKERHUB}
```

### Ruta B — Desde PC y copiar

```bash
git clone https://github.com/aliothosa/JeanOS.git
cd JeanOS
git checkout ${GIT_BRANCH} && git pull origin ${GIT_BRANCH}
./scripts/personalizar-lab.sh ${IP_MASTER} ${IP_WORKER1} ${IP_WORKER2} ${DOCKERHUB}
scp -r ansible-k8s scripts docs root@${IP_MASTER}:/root/JeanOS/
```

---

## Paso 2 — Imágenes Docker (arquitectura correcta)

Los manifiestos de `backend` y `frontend` deben apuntar a imágenes que **corran en tus nodos** (amd64 o arm64).

### Opción A — Ya tienes imágenes en Hub

Comprueba que los deployments usan tu usuario:

```bash
grep 'image: docker.io' ansible-k8s/manifests/backend/backend-deployment.yaml
grep 'image: docker.io' ansible-k8s/manifests/frontend/frontend-deployment.yaml
```

Si cambiaste solo el script `personalizar-lab.sh`, vuelve a aplicar la tienda:

```bash
cd /root/JeanOS/ansible-k8s
./deploy-jeanos.sh --yes
```

### Opción B — Construir en tu PC (x86, rama `lab/x86-aliothosa`)

```bash
podman login docker.io
./scripts/build-push-x86-aliothosa.sh
```

### Opción C — Construir en el cluster con Tekton (Paso 4)

El PipelineRun de Semana 4 hace build + push; los deployments deben usar **el mismo tag** que defines en `lab.env`.

### ARM (`lab/equipo`)

```bash
podman build --platform linux/arm64 -t docker.io/${DOCKERHUB}/jeanos-backend:v1 app/backend
podman build --platform linux/arm64 -t docker.io/${DOCKERHUB}/jeanos-frontend:v1 app/frontend
podman push docker.io/${DOCKERHUB}/jeanos-backend:v1
podman push docker.io/${DOCKERHUB}/jeanos-frontend:v1
```

---

## Paso 3 — `lab.env` (secretos, no subir a Git)

En el master:

```bash
cd /root/JeanOS/ansible-k8s
cp lab.env.example lab.env
vi lab.env   # o nano
```

Ejemplo (ajusta rama e imágenes):

```bash
GITHUB_REPO_URL=https://github.com/aliothosa/JeanOS
GITHUB_REVISION=lab/x86-aliothosa

DOCKER_BACKEND_IMAGE=aliothosa/jeanos-backend:v1
DOCKER_FRONTEND_IMAGE=aliothosa/jeanos-frontend:v1
DOCKER_USERNAME=aliothosa
DOCKER_TOKEN=dckr_pat_XXXXXXXXXXXX

PIPELINE_RUN_NAME=jeanos-shop-build-run-1
ARGOCD_ADMIN_PASSWORD=jeanos2026
```

**Docker Hub token:** Account Settings → Security → Access Token (permiso **Read & Write**). Sin `DOCKER_TOKEN`, `deploy-semana4.sh` se detiene al crear el secret de Tekton.

---

## Paso 4 — Firewall (si aún no está abierto)

En cada nodo del cluster (o vía playbook `k8s-install.yml` del equipo):

```bash
for port in 30443 30080 30300 30900; do
  firewall-cmd --add-port=${port}/tcp --permanent
done
firewall-cmd --permanent --zone=trusted --add-source=10.244.0.0/16
firewall-cmd --reload
```

| Puerto | Servicio |
|--------|----------|
| 30080 | Tienda jeanOS |
| 30300 | Grafana (Semana 3) |
| 30900 | Prometheus (Semana 3) |
| 30443 | ArgoCD UI (Semana 4) |

---

## Paso 5 — Desplegar Semana 4

Solo en el master, con Semana 3 ya estable:

```bash
cd /root/JeanOS/ansible-k8s
./deploy-semana4.sh --yes
```

El script, en orden:

1. Comprueba StorageClass `nfs-client`
2. Instala **Tekton Pipelines** (namespace `tekton-pipelines`, PSA privileged)
3. Crea secret `docker-credentials` en `tekton-pipelines`
4. Aplica Tasks + Pipeline `build-jeanos-shop`
5. Lanza **PipelineRun** `jeanos-shop-build-run-1` (PVC `nfs-client`)
6. Instala **ArgoCD**, NodePort **30443**, contraseña admin
7. Aplica Application **`jeanos-shop-gitops`** → sync `backend/**` y `frontend/**`

### Ver logs del pipeline

Instala CLI Tekton en el master si no la tienes:

```bash
# x86_64
curl -LO https://github.com/tektoncd/cli/releases/download/v0.38.0/tkn_0.38.0_Linux_x86_64.tar.gz
tar xvzf tkn_0.38.0_Linux_x86_64.tar.gz -C /usr/local/bin tkn

# ARM64
# curl -LO .../tkn_0.38.0_Linux_arm64.tar.gz
```

```bash
tkn pipelinerun logs jeanos-shop-build-run-1 -f -n tekton-pipelines
```

Sin `tkn`:

```bash
kubectl logs -n tekton-pipelines -l tekton.dev/pipelineRun=jeanos-shop-build-run-1 --all-containers -f
```

---

## Paso 6 — Validar

### 6.1 Tekton

```bash
kubectl get pipelinerun -n tekton-pipelines
tkn pipelinerun describe jeanos-shop-build-run-1 -n tekton-pipelines
# Estado final: Succeeded
```

### 6.2 ArgoCD

```bash
kubectl get pods -n argocd
kubectl get application -n argocd
```

| Comprobación | Esperado |
|--------------|----------|
| Application `jeanos-shop-gitops` | Synced, Healthy |
| UI | `https://${IP_WORKER1}:30443` — usuario `admin`, contraseña de `lab.env` (por defecto `jeanos2026`) |
| Destino | namespace `jeanos-shop` |

```bash
# Contraseña inicial (si no aplicaste el manifest del equipo)
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
```

### 6.3 Tienda (proyecto final G-09)

| URL | Qué ver |
|-----|---------|
| `http://${IP_WORKER1}:30080` | Catálogo, comparador Redis vs Postgres |
| DevTools / red | Latencia comparador con Redis caliente (WOW &lt;5 ms) |
| `kubectl delete pod -n jeanos-shop -l app=redis` | Tras reinicio Redis, init `preload-redis` recarga caché |

### 6.4 Semana 3 sigue intacta

```bash
kubectl get pods -n monitoring
curl -s "http://${IP_WORKER1}:30900/api/v1/query?query=up" | head
# Grafana :30300 → Dashboards → JeanOS
```

Si Semana 3 falla **después** de Semana 4, suele ser firewall o recursos; ArgoCD no toca `monitoring`.

---

## Paso 7 — WOW moment (commit → deploy)

Flujo para demostrar CI/CD en clase:

1. Cambio en `app/backend` o en tag de imagen en manifests → **commit + push** a tu rama (`lab/equipo` o `lab/x86-aliothosa`).
2. Relanzar pipeline (Paso 8) → nuevas imágenes en Docker Hub.
3. ArgoCD detecta cambios en Git → sync → rollout en `jeanos-shop`.
4. Mostrar en UI ArgoCD + tienda `:30080` + (opcional) métricas en Grafana.

---

## Relanzar pipeline (nuevo build)

```bash
kubectl delete pipelinerun jeanos-shop-build-run-1 -n tekton-pipelines
```

Edita `lab.env`:

```bash
PIPELINE_RUN_NAME=jeanos-shop-build-run-2
```

```bash
cd /root/JeanOS/ansible-k8s
./deploy-semana4.sh --yes --skip-tekton --skip-argocd
```

---

## Opciones del script

```bash
./deploy-semana4.sh --yes              # Todo
./deploy-semana4.sh --yes --skip-tekton    # Tekton ya instalado
./deploy-semana4.sh --yes --skip-pipeline  # Solo ArgoCD / sin build
./deploy-semana4.sh --yes --skip-argocd    # Solo Tekton + PipelineRun
```

---

## Estructura de manifests

```
ansible-k8s/manifests/semana-4/
├── tekton/
│   ├── task-git-clone.yaml
│   ├── task-build-push.yaml      # Kaniko → Docker Hub
│   ├── pipeline-build-jeanos.yaml
│   └── pipelinerun.yaml          # placeholders __GITHUB_*__, __DOCKER_*__
└── argocd/
    ├── application.yaml          # jeanos-shop-gitops
    └── argocd-admin-password.yaml
```

| Recurso Kubernetes | Nombre |
|--------------------|--------|
| ArgoCD Application | `jeanos-shop-gitops` |
| Tekton Pipeline | `build-jeanos-shop` |
| PipelineRun (por defecto) | `jeanos-shop-build-run-1` |
| Secret Hub | `docker-credentials` (ns `tekton-pipelines`) |

---

## Troubleshooting

### PipelineRun falla en `build-and-push`

- Revisa `DOCKER_TOKEN` y que el usuario tenga permiso de push.
- Imagen destino debe coincidir con manifests (`DOCKER_BACKEND_IMAGE` / `DOCKER_FRONTEND_IMAGE`).
- Kaniko necesita red saliente al registry y a GitHub.

### `ImagePullBackOff` en jeanos-shop tras el pipeline

- La arquitectura de la imagen no coincide con el nodo (amd64 vs arm64).
- Reconstruye con la plataforma correcta o usa la rama de lab adecuada.

### ArgoCD OutOfSync / errores de sync

```bash
kubectl describe application jeanos-shop-gitops -n argocd
argocd app sync jeanos-shop-gitops   # con CLI argocd instalada
```

Comprueba `targetRevision` en `application.yaml` = rama que pusheaste.

### Puerto 30443 no abre

- `kubectl get svc argocd-server -n argocd` → debe ser NodePort **30443**.
- Firewall en el nodo donde pruebas el navegador.

### PipelineRun ya existe

```bash
kubectl delete pipelinerun jeanos-shop-build-run-1 -n tekton-pipelines
# o cambia PIPELINE_RUN_NAME en lab.env
```

### Tekton pods Pending

- PVC del workspace: StorageClass `nfs-client` y NFS con espacio.
- Namespace `tekton-pipelines` con PSA **privileged** (el script lo etiqueta).

### La tienda funciona pero ArgoCD no aparece

- Instalación tarda varios minutos: `kubectl get pods -n argocd -w`
- Reaplica solo ArgoCD: `./deploy-semana4.sh --yes --skip-tekton --skip-pipeline`

---

## Referencias rápidas

| Documento | Contenido |
|-----------|-----------|
| `docs/SEMANA-3-REPLICAR.md` | Monitoreo (prerequisito) |
| `docs/GUIA-EQUIPO-LAB.md` | Lab ARM completo |
| `docs/GUIA-X86-ALIOTHOSA.md` | Lab x86 + script build |
| `ansible-k8s/manifests/semana-4/README.md` | Resumen manifests |
| `examples/tekton-argocd/README.md` | Tutorial clase (demo aparte) |

---

## Resumen en una línea

Con **Semana 3 lista**: personaliza IPs → `lab.env` con token Hub → `./deploy-semana4.sh --yes` → valida Pipeline **Succeeded**, ArgoCD **jeanos-shop-gitops** Synced y tienda en **:30080**.
