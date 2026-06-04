# Semana 4 — Replicar Tekton + ArgoCD (equipo)

Manifests listos en **`ansible-k8s/manifests/semana-4/`** y script **`ansible-k8s/deploy-semana4.sh`**.

## Para compañeros en rama `main`

```bash
git checkout main
git pull origin main
# Si Semana 4 aún no está en main, traer desde lab/equipo:
# git fetch origin lab/equipo && git checkout origin/lab/equipo -- ansible-k8s/manifests/semana-4 ansible-k8s/deploy-semana4.sh ansible-k8s/lab.env.example docs/SEMANA-4-REPLICAR.md
```

## Checklist antes de Semana 4

- [ ] Semana 2 OK (`kubectl get pods -n jeanos-shop`)
- [ ] `kubectl get storageclass nfs-client`
- [ ] Cuenta Docker Hub + **Access Token**
- [ ] Repo GitHub público con `app/` + `k8s/` (ej. `aliothosa/page-public-demo`)

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

Contraseña ArgoCD inicial:

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

## Archivos del equipo (referencia)

```
ansible-k8s/
├── lab.env.example          # plantilla (sin secretos)
├── deploy-semana4.sh        # orquesta Tekton + ArgoCD
└── manifests/semana-4/
    ├── tekton/              # Tasks, Pipeline, PipelineRun
    └── argocd/              # Application GitOps
```
