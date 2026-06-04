# Clase 4 - Tekton + ArgoCD: GitOps CI/CD

## Objetivo

Implementar un pipeline GitOps completo: Tekton construye y publica la imagen de
contenedor, ArgoCD detecta los cambios en Git y despliega automáticamente.
Al terminar, un `git push` es el único comando necesario para llevar código a producción.

---

## Arquitectura

```
  Developer
     │
     │  git push
     ▼
  GitHub Repo
  ├── app/
  │   ├── index.html
  │   └── Dockerfile
  └── k8s/
      ├── deployment.yaml   ← ArgoCD lee esto
      └── service.yaml
     │
     │  PipelineRun (manual o webhook)
     ▼
  ┌──────────────────────────────────────────────────────┐
  │              Namespace: tekton-pipelines              │
  │                                                        │
  │  Task: git-clone          Task: build-push            │
  │  ┌──────────────┐         ┌──────────────────┐        │
  │  │ alpine/git   │────────►│ gcr.io/kaniko    │        │
  │  │ clona repo   │workspace│ build + push     │        │
  │  │ → /workspace │  NFS    │ → Docker Hub     │        │
  │  └──────────────┘  PVC    └──────────────────┘        │
  └──────────────────────────────────────────────────────┘
                                        │
                                        │ imagen:v1 pusheada
                                        ▼
  ┌──────────────────────────────────────────────────────┐
  │               Namespace: argocd                       │
  │                                                        │
  │  ArgoCD Application "mi-tienda"                       │
  │  ┌──────────────────────────────────────────────┐     │
  │  │ repoURL: github.com/usuario/mi-repo          │     │
  │  │ path: k8s/                                   │     │
  │  │ syncPolicy: automated + selfHeal + prune     │     │
  │  └──────────────────────────────────────────────┘     │
  │              │ sync automático cada ~3 min             │
  └──────────────┼───────────────────────────────────────┘
                 │ kubectl apply
                 ▼
          Namespace: demo
          Deployment "mi-tienda"
```

---

## Pre-requisitos

### Cluster
- StorageClass `nfs-csi` disponible (workspace del Pipeline)

```bash
kubectl get storageclass nfs-csi
```

### Puertos firewall (Rocky Linux 9)

```bash
# ArgoCD UI
ansible all -i /root/kubernetes/ansible-k8s/inventory/hosts.ini \
  -m firewalld -a "port=30443/tcp permanent=yes state=enabled immediate=yes" --become

# App desplegada
ansible all -i /root/kubernetes/ansible-k8s/inventory/hosts.ini \
  -m firewalld -a "port=31080/tcp permanent=yes state=enabled immediate=yes" --become
```

### Cuentas necesarias
- GitHub: repo público + Personal Access Token (PAT)
- Docker Hub: usuario + token de acceso

---

## Paso 1 — Instalar Tekton

```bash
kubectl apply -f https://storage.googleapis.com/tekton-releases/pipeline/latest/release.yaml

# Esperar a que todos los pods estén Running (~2 min)
kubectl get pods -n tekton-pipelines --watch
# Ctrl+C cuando todos estén Running
```

Instalar CLI:
```bash
curl -LO https://github.com/tektoncd/cli/releases/download/v0.35.0/tkn_0.35.0_Linux_x86_64.tar.gz
tar xzf tkn_0.35.0_Linux_x86_64.tar.gz -C /usr/local/bin tkn
tkn version
```

### ⚠️ CRÍTICO — Etiquetar namespace con PodSecurity privileged

Kubernetes 1.25+ bloquea los pods de Tekton por defecto. Sin este paso los pods
quedan en `Pending` con error `violates PodSecurity "restricted:latest"`.

```bash
kubectl label namespace tekton-pipelines \
  pod-security.kubernetes.io/enforce=privileged \
  pod-security.kubernetes.io/warn=privileged \
  pod-security.kubernetes.io/audit=privileged \
  --overwrite

# Verificar
kubectl get namespace tekton-pipelines --show-labels | grep pod-security
```

---

## Paso 2 — Crear Secret de Docker Hub

```bash
# Usar token de Docker Hub (NO la contraseña)
# Generar en: Docker Hub → Account Settings → Security → New Access Token
kubectl create secret docker-registry docker-credentials \
  --docker-server=https://index.docker.io/v1/ \
  --docker-username=<TU_USUARIO> \
  --docker-password=<TU_TOKEN> \
  -n tekton-pipelines

# Verificar
kubectl get secret docker-credentials -n tekton-pipelines
```

---

## Paso 3 — Aplicar Tasks y Pipeline

```bash
kubectl apply -f task-git-clone.yaml
kubectl apply -f task-build-push.yaml
kubectl apply -f pipeline-build-deploy.yaml

# Verificar
kubectl get tasks -n tekton-pipelines
kubectl get pipelines -n tekton-pipelines
```

---

## Paso 4 — Lanzar el primer PipelineRun

Editar `pipelinerun-demo.yaml` con **sed** (no vi) y reemplazar los valores:

```bash
# Cambiar repo URL
sed -i 's|https://github.com/USUARIO/mi-repo|https://github.com/TU_USUARIO/TU_REPO|g' pipelinerun-demo.yaml

# Cambiar imagen
sed -i 's|USUARIO/mi-tienda:v1|TU_USUARIO/mi-tienda:v1|g' pipelinerun-demo.yaml

# Verificar
grep -E "repo-url|image" pipelinerun-demo.yaml -A1
```

```bash
# Lanzar
kubectl apply -f pipelinerun-demo.yaml

# Ver logs en tiempo real
tkn pipelinerun logs --last -f -n tekton-pipelines
```

### ⚠️ CRÍTICO — Nombre fijo en PipelineRun

El archivo usa `metadata.name` fijo. **No uses `generateName`** — da error con `kubectl apply`:

```
error: from build-and-deploy-run-: cannot use generate name with apply
```

Para relanzar el pipeline, borra el anterior primero:

```bash
kubectl delete pipelinerun build-and-deploy-run-1 -n tekton-pipelines
kubectl apply -f pipelinerun-demo.yaml
```

---

## Paso 5 — Instalar ArgoCD

```bash
kubectl create namespace argocd

kubectl apply -n argocd -f \
  https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Esperar ~3-4 min
kubectl get pods -n argocd --watch
# Ctrl+C cuando todos estén Running
```

Exponer con NodePort:
```bash
kubectl patch svc argocd-server -n argocd \
  -p '{"spec":{"type":"NodePort","ports":[{"port":443,"nodePort":30443,"targetPort":8080,"protocol":"TCP","name":"https"}]}}'
```

Obtener contraseña inicial:
```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d && echo
```

UI: `https://<IP-NODO>:30443` | User: `admin` | Pass: (la del comando anterior)

### Instalar CLI de ArgoCD

```bash
curl -sSL -o /usr/local/bin/argocd \
  https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x /usr/local/bin/argocd

# Login (necesario antes de cualquier comando argocd)
argocd login localhost:30443 --insecure --username admin --password <PASSWORD>
```

---

## Paso 6 — Crear la Application

Editar `argocd-application.yaml` con **sed**:

```bash
sed -i 's|https://github.com/USUARIO/mi-repo|https://github.com/TU_USUARIO/TU_REPO|g' argocd-application.yaml

# Verificar
grep repoURL argocd-application.yaml
```

```bash
kubectl apply -f argocd-application.yaml

# Verificar sincronización
kubectl get application -n argocd
# SYNC STATUS: Synced  |  HEALTH STATUS: Healthy
```

---

## Demo: commit → deploy automático (v1 → v2)

### Paso 1 — Modificar la app con sed (no vi)

```bash
# Cambiar versión y color visible
sed -i 's/v1\.0\.0/v2.0.0/g' app/index.html
sed -i 's/#238636/#1f6feb/g' app/index.html

grep -E "v2.0.0|1f6feb" app/index.html
```

### Paso 2 — Actualizar el tag en el manifiesto K8s

```bash
sed -i 's|mi-tienda:v1|mi-tienda:v2|g' k8s/deployment.yaml
grep image k8s/deployment.yaml
```

### Paso 3 — Commit y push

```bash
git add app/index.html k8s/deployment.yaml
git commit -m "feat: update to v2 - new color and version"
git push
```

### Paso 4 — Lanzar Pipeline v2

```bash
# Borrar run anterior y relanzar con nuevo tag
kubectl delete pipelinerun build-and-deploy-run-1 -n tekton-pipelines
sed -i 's|mi-tienda:v1|mi-tienda:v2|g' pipelinerun-demo.yaml
kubectl apply -f pipelinerun-demo.yaml
tkn pipelinerun logs --last -f -n tekton-pipelines
```

### Paso 5 — Forzar sync en ArgoCD

```bash
# Con CLI
argocd app sync mi-tienda

# Sin CLI (via kubectl)
kubectl annotate application mi-tienda -n argocd \
  argocd.argoproj.io/refresh=normal --overwrite
```

### Paso 6 — Verificar

```bash
kubectl get pods -n demo
kubectl get deployment mi-tienda -n demo \
  -o jsonpath='{.spec.template.spec.containers[0].image}'
# debe mostrar: USUARIO/mi-tienda:v2
```

**Rollback desde ArgoCD UI:**
```
ArgoCD → mi-tienda → HISTORY AND ROLLBACK → seleccionar revisión anterior → Rollback
```

---

## Troubleshooting

### ❌ Pods en Pending — PodSecurity violation

**Síntoma:**
```
violates PodSecurity "restricted:latest": allowPrivilegeEscalation != false
```

**Solución:**
```bash
kubectl label namespace tekton-pipelines \
  pod-security.kubernetes.io/enforce=privileged --overwrite
```

---

### ❌ `cannot use generate name with apply`

**Síntoma:**
```
error: from build-and-deploy-run-: cannot use generate name with apply
```

**Causa:** El YAML usa `generateName` en vez de `name`.

**Solución:** Usar `metadata.name` fijo (ya corregido en este repo).
Para relanzar: borrar el pipelinerun anterior con `kubectl delete pipelinerun`.

---

### ❌ `git clone` falla — "could not read Username"

**Síntoma:**
```
fatal: could not read Username for 'https://github.com': No such device or address
```

**Causa:** El repo es privado o no existe en GitHub.

**Solución A** — Usar repo público.
**Solución B** — Incluir token en la URL:
```bash
sed -i 's|https://github.com/USUARIO|https://USUARIO:TOKEN@github.com/USUARIO|g' pipelinerun-demo.yaml
```

---

### ❌ `argocd app sync` falla — "no session information"

**Síntoma:**
```
rpc error: code = Unauthenticated desc = no session information
```

**Solución:** Hacer login primero:
```bash
argocd login localhost:30443 --insecure --username admin --password <PASSWORD>
```

---

### ❌ App no se actualiza tras reconstruir la misma imagen

**Causa:** Kubernetes no hace pull si el tag no cambió.

**Solución:**
```bash
kubectl rollout restart deployment/mi-tienda -n demo
```

---

### ❌ Kaniko no puede hacer push

```bash
# Verificar que el Secret existe y tiene el formato correcto
kubectl get secret docker-credentials -n tekton-pipelines
kubectl get secret docker-credentials -n tekton-pipelines \
  -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d
```

---

## Limpieza

```bash
# Borrar app y namespaces
kubectl delete application mi-tienda -n argocd 2>/dev/null; true
kubectl delete namespace demo argocd 2>/dev/null; true

# Borrar PipelineRuns (libera PVCs NFS)
kubectl delete pipelineruns --all -n tekton-pipelines 2>/dev/null; true

# Borrar Tasks, Pipeline y Secret
kubectl delete -f pipeline-build-deploy.yaml
kubectl delete -f task-git-clone.yaml
kubectl delete -f task-build-push.yaml
kubectl delete secret docker-credentials -n tekton-pipelines 2>/dev/null; true

# Desinstalar Tekton completo
kubectl delete -f https://storage.googleapis.com/tekton-releases/pipeline/latest/release.yaml 2>/dev/null; true

# Verificar limpieza
kubectl get pvc -n tekton-pipelines
kubectl get pods -n tekton-pipelines
```

---

## Archivos

| Archivo | Recurso | Descripción |
|---------|---------|-------------|
| `task-git-clone.yaml` | Task | Clona un repo Git en el workspace compartido |
| `task-build-push.yaml` | Task | Usa Kaniko para build + push de la imagen |
| `pipeline-build-deploy.yaml` | Pipeline | Encadena clone → build con workspace NFS |
| `pipelinerun-demo.yaml` | PipelineRun | Lanza el pipeline — editar USUARIO antes de usar |
| `argocd-application.yaml` | Application | Declara la app en ArgoCD — editar USUARIO antes de usar |

> `docker-credentials` Secret no está en el repo (contiene credenciales).
> Crear con `kubectl create secret docker-registry`.
