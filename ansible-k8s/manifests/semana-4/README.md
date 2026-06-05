# Semana 4 — Tekton + ArgoCD (manifests del equipo)

Despliegue automatizado desde el **master** del cluster:

```bash
cd ansible-k8s
cp lab.env.example lab.env    # editar repo GitHub, imagen Docker Hub, usuario
./deploy-semana4.sh --yes
```

## Contenido

| Carpeta / archivo | Qué despliega |
|-------------------|---------------|
| `tekton/` | Tasks, Pipeline y PipelineRun (CI: clone + build Kaniko + push) |
| `argocd/application.yaml` | Application `semana4-gitops-landing` |
| `gitops-landing/` | Deployment + Service (ns `semana4-gitops`, :31080) |
| `argocd/argocd-admin-password.yaml` | Hash bcrypt admin (`jeanos2026` por defecto en el lab) |
| `lab.env.example` | Variables del lab (copiar a `lab.env`) |

## Requisitos

- Cluster con **Semana 2** OK (`StorageClass` **`nfs-client`**, namespace `jeanos-shop` opcional pero recomendado).
- Nodos **aarch64**: Kaniko/Tekton usan imágenes multi-arch; app demo debe buildear para `linux/arm64` si el cluster es ARM.
- Cuenta **Docker Hub** (usuario + Access Token).
- Repo GitHub **público** con `app/` para Tekton (ej. `aliothosa/page-public-demo`)
- ArgoCD despliega **`gitops-landing/`** (ns `semana4-gitops`, imagen `__DOCKER_IMAGE__` arm64), no el `k8s/` del curso (amd64)

## URLs tras el despliegue

| Servicio | NodePort |
|----------|----------|
| ArgoCD UI | https://\<IP-NODO\>:30443 |
| Landing GitOps (Semana 4) | http://\<IP-NODO\>:31080 |
| JeanOS Shop (S2) | http://\<IP-NODO\>:30080 |

## Personalizar IPs / usuario

Desde la raíz del repo:

```bash
./scripts/personalizar-lab.sh IP_MASTER IP_W1 IP_W2 USUARIO_DOCKERHUB
```

Ver también `docs/SEMANA-4-REPLICAR.md` y `docs/GUIA-EQUIPO-LAB.md`.
