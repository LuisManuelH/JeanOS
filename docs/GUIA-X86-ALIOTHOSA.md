# Lab x86_64 — rama `lab/x86-aliothosa`

Rama para clusters **amd64** (x86_64) con imágenes en **Docker Hub `aliothosa`**.

| Rama | Arquitectura | Imágenes por defecto |
|------|--------------|----------------------|
| `lab/equipo` | ARM64 (`aarch64`) | `emmanuelmal2/jeanos-*:v1` |
| **`lab/x86-aliothosa`** | **amd64** | **`aliothosa/jeanos-*:v1`** |

## IPs por defecto (lab JeanOS x86)

| Rol | IP |
|-----|-----|
| Master + NFS | 192.168.41.154 |
| Worker 1 | 192.168.41.157 |
| Worker 2 | 192.168.41.158 |

Personalizar: `./scripts/personalizar-lab.sh IP_MASTER IP_W1 IP_W2 aliothosa`

## Publicar imágenes amd64

Desde la raíz del repo (PC o CI con x86_64):

```bash
podman login docker.io
chmod +x scripts/build-push-x86-aliothosa.sh
./scripts/build-push-x86-aliothosa.sh
```

Variables opcionales: `REGISTRY=docker.io/aliothosa` `TAG=v1` `PLATFORM=linux/amd64`

## Despliegue

```bash
git checkout lab/x86-aliothosa
cd ansible-k8s && ./deploy-jeanos.sh --yes
```

Semana 3/4: mismas guías que `lab/equipo`, usando esta rama en `git pull` y `GITHUB_REVISION=lab/x86-aliothosa`.
