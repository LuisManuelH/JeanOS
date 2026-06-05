# Semana 4 — Replicar Tekton + ArgoCD (equipo)

Guía única para repetir el lab. Manifests en **`ansible-k8s/manifests/semana-4/`**, script **`ansible-k8s/deploy-semana4.sh`**.

Lab completo (Semanas 2–4, IPs, firewall): **`docs/GUIA-EQUIPO-LAB.md`**.

## Obtener el código

```bash
git fetch origin
git checkout lab/equipo
git pull origin lab/equipo
```

Si tu equipo usa `main` y aún no tiene Semana 4:

```bash
git checkout main && git pull
git fetch origin lab/equipo
git checkout origin/lab/equipo -- ansible-k8s/manifests/semana-4 ansible-k8s/deploy-semana4.sh ansible-k8s/lab.env.example docs/SEMANA-4-REPLICAR.md
```

## Checklist antes de Semana 4

- [ ] Semana 2 OK (`kubectl get pods -n jeanos-shop`)
- [ ] `kubectl get storageclass nfs-client`
- [ ] Cuenta Docker Hub + **Access Token**
- [ ] Repo GitHub público con carpeta **`app/`** para Tekton (ej. `aliothosa/page-public-demo`)
- [ ] Semana 2 y 3 hechas (NFS, tienda, monitoreo opcional pero recomendado)
- [ ] Nodos **ARM64**: la demo ArgoCD usa manifests en este repo (`demo/`), no el `k8s/` del curso (imagen amd64)

## Personalizar (cada alumno)

```bash
# Desde la raíz del repo
./scripts/personalizar-lab.sh IP_MASTER IP_WORKER1 IP_WORKER2 TU_USUARIO_DOCKERHUB

cd ansible-k8s
cp lab.env.example lab.env
```

Editar **`ansible-k8s/lab.env`**:

```bash
GITHUB_REPO_URL=https://github.com/TU_USUARIO/page-public-demo
DOCKER_IMAGE=TU_USUARIO/mi-tienda:v1
DOCKER_USERNAME=TU_USUARIO
DOCKER_TOKEN=tu_token_de_docker_hub
PIPELINE_RUN_NAME=build-and-deploy-run-1
ARGOCD_ADMIN_PASSWORD=jeanos2026
```

**No commitear `lab.env`** (contiene el token).

## Desplegar (solo en el master, con kubectl)

```bash
# Copiar repo al master si trabajas desde Mac
scp -r ansible-k8s root@IP_MASTER:/root/JeanOS/

ssh root@IP_MASTER
cd /root/JeanOS/ansible-k8s
chmod +x deploy-semana4.sh
./deploy-semana4.sh --yes
```

Seguir logs Tekton:

```bash
tkn pipelinerun logs build-and-deploy-run-1 -f -n tekton-pipelines
```

## Validar

| Qué | Cómo |
|-----|------|
| Pipeline OK | `tkn pipelinerun describe build-and-deploy-run-1 -n tekton-pipelines` → Succeeded |
| Imagen en Hub | Ver repositorio `TU_USUARIO/mi-tienda` tag `v1` |
| ArgoCD | `kubectl get application -n argocd` → Synced, Healthy |
| App | http://IP_WORKER:31080 |
| UI ArgoCD | https://IP_WORKER:30443 |

Login ArgoCD (definido en manifest del lab, no aleatorio):

| Campo | Valor |
|-------|--------|
| Usuario | `admin` |
| Contraseña | `jeanos2026` (o `ARGOCD_ADMIN_PASSWORD` en `lab.env`) |

Manifest: `ansible-k8s/manifests/semana-4/argocd/argocd-admin-password.yaml` (hash bcrypt, no texto plano).

Si instalaste ArgoCD a mano sin el script, aplica ese YAML o saca la aleatoria:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d; echo
```

## Relanzar pipeline

```bash
kubectl delete pipelinerun build-and-deploy-run-1 -n tekton-pipelines
# En lab.env: PIPELINE_RUN_NAME=build-and-deploy-run-2
./deploy-semana4.sh --yes --skip-tekton --skip-argocd
```

## Firewall (3 nodos)

```bash
for port in 30443 31080; do
  firewall-cmd --add-port=${port}/tcp --permanent
done
firewall-cmd --reload
```

## Cluster ARM64

Los nodos del lab son **aarch64**. El repo demo debe poder construir imagen ARM (Kaniko en nodo ARM genera arm64). JeanOS ya usa `podman build --platform linux/arm64`.

## URLs del lab (cambiar IP por la de tu worker)

| Servicio | URL |
|----------|-----|
| Tienda JeanOS | http://IP_WORKER:30080 |
| Demo GitOps | http://IP_WORKER:31080 |
| ArgoCD | https://IP_WORKER:30443 |
| Grafana | http://IP_WORKER:30300 |
| Prometheus | http://IP_WORKER:30900 |

## Archivos del equipo (referencia)

```
ansible-k8s/
├── lab.env.example
├── deploy-semana4.sh
└── manifests/semana-4/
    ├── tekton/                         # CI: clone + Kaniko
    ├── argocd/
    │   ├── application.yaml            # GitOps → namespace demo
    │   └── argocd-admin-password.yaml  # admin / jeanos2026 (bcrypt)
    └── demo/                           # Deployment + Service :31080 (ARM)
```

## Problemas frecuentes

| Síntoma | Qué revisar |
|---------|-------------|
| Demo CrashLoop `exec format error` | Imagen amd64; usar `demo/` de JeanOS + imagen de Tekton en Hub |
| ArgoCD login falla | Usar **https**, usuario `admin`, contraseña `jeanos2026`; o aplicar `argocd-admin-password.yaml` |
| PipelineRun falla push | `DOCKER_TOKEN` en `lab.env`, secret `docker-credentials` en `tekton-pipelines` |
| PVC pendiente | `kubectl get sc` → debe existir **nfs-client** (Semana 2) |
| ArgoCD install CRD error | El script usa `kubectl apply --server-side`; no aplicar install.yaml a mano sin eso |
