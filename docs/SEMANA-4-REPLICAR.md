# Semana 4 — CI/CD jeanOS Shop (proyecto final G-09)

Alineado con **R6/R7** del documento del curso: Tekton + ArgoCD sobre **tu tienda**, no una app aparte.

- **Tutorial de clase** (solo referencia): `examples/tekton-argocd/` + repo `page-public-demo`
- **Proyecto jeanOS**: este repo + `ansible-k8s/manifests/semana-4/`

Lab completo: **`docs/GUIA-EQUIPO-LAB.md`**

## Qué hace Semana 4 en jeanOS

| Pieza | Función |
|-------|---------|
| **Tekton** | Clona **JeanOS**, construye `app/backend` y `app/frontend`, push a Docker Hub |
| **ArgoCD** | Sincroniza **backend + frontend** en `jeanos-shop` desde Git |
| **Demo en clase (G-09)** | Latencia comparador Redis vs PostgreSQL en **:30080** |

## Obtener código

```bash
git fetch origin && git checkout lab/equipo && git pull
```

## Checklist

- [ ] Semana 2: tienda en `jeanos-shop` (`deploy-jeanos.sh`)
- [ ] `nfs-client`, Postgres, Redis OK
- [ ] Docker Hub + `DOCKER_TOKEN` en `lab.env`
- [ ] Nodos **ARM64** (`podman build --platform linux/arm64`)

## Personalizar

```bash
./scripts/personalizar-lab.sh IP_MASTER IP_W1 IP_W2 USUARIO_DOCKERHUB
cd ansible-k8s && cp lab.env.example lab.env
```

`lab.env`:

```bash
GITHUB_REPO_URL=https://github.com/aliothosa/JeanOS
GITHUB_REVISION=lab/equipo
DOCKER_BACKEND_IMAGE=TU_USUARIO/jeanos-backend:v1
DOCKER_FRONTEND_IMAGE=TU_USUARIO/jeanos-frontend:v1
DOCKER_USERNAME=TU_USUARIO
DOCKER_TOKEN=...
PIPELINE_RUN_NAME=jeanos-shop-build-run-1
ARGOCD_ADMIN_PASSWORD=jeanos2026
```

## Desplegar (master)

```bash
scp -r ansible-k8s root@IP_MASTER:/root/JeanOS/
ssh root@IP_MASTER
cd /root/JeanOS/ansible-k8s
./deploy-semana4.sh --yes
tkn pipelinerun logs jeanos-shop-build-run-1 -f -n tekton-pipelines
```

## Validar (proyecto final)

| Qué | Cómo |
|-----|------|
| Pipeline | `tkn pipelinerun describe jeanos-shop-build-run-1 -n tekton-pipelines` → Succeeded |
| ArgoCD | App **`jeanos-shop-gitops`** → Synced, Healthy |
| Tienda | http://IP_WORKER:30080 — comparador, productos |
| WOW G-09 | DevTools: comparador &lt;5ms (Redis); matar pod Redis → init recarga |
| ArgoCD UI | https://IP_WORKER:30443 (`admin` / `jeanos2026`) |

## WOW moment (commit → deploy)

1. Cambio en `app/backend` o tag en manifests → commit/push a `lab/equipo`
2. PipelineRun (o webhook) construye imágenes
3. ArgoCD sincroniza → rollout en `jeanos-shop`
4. Mostrar en ArgoCD UI + tienda :30080

## Relanzar pipeline

```bash
kubectl delete pipelinerun jeanos-shop-build-run-1 -n tekton-pipelines
# PIPELINE_RUN_NAME=jeanos-shop-build-run-2 en lab.env
./deploy-semana4.sh --yes --skip-tekton --skip-argocd
```

## Estructura manifests

```
ansible-k8s/manifests/semana-4/
├── tekton/                    # clone + build backend + frontend
├── argocd/
│   ├── application.yaml       # jeanos-shop-gitops
│   └── argocd-admin-password.yaml
    # Application incluye solo backend/* y frontend/* en jeanos-shop
```

Postgres/Redis/NFS siguen con `deploy-jeanos.sh` (Semana 2); ArgoCD no los borra.

## Firewall

Puertos: `30080`, `30443` (+ monitoreo si aplica).
