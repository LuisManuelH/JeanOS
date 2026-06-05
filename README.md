# JeanOS
Tienda de Hardware &amp; Componentes de PC

## Lab del equipo (Semanas 2–4)

| Rama | Uso |
|------|-----|
| **`lab/equipo`** | Cluster **ARM64** — ver `docs/GUIA-EQUIPO-LAB.md` |
| **`lab/x86-aliothosa`** | Cluster **x86_64** — imágenes `aliothosa/jeanos-*:v1` — ver `docs/GUIA-X86-ALIOTHOSA.md` |

1. `git checkout lab/equipo` o `lab/x86-aliothosa`
2. Semana 3: **`docs/SEMANA-3-REPLICAR.md`** · Semana 4: **`docs/SEMANA-4-REPLICAR.md`**
3. Personalizar IPs y Docker Hub: `./scripts/personalizar-lab.sh IP_MASTER IP_W1 IP_W2 TU_USUARIO_HUB`
4. x86: publicar imágenes con `./scripts/build-push-x86-aliothosa.sh`

## Despliegue en Kubernetes

```bash
./ansible-k8s/deploy-jeanos.sh --yes          # Semana 2 — tienda
# Semana 3 — monitoreo + dashboard Grafana: docs/SEMANA-3-REPLICAR.md
# Semana 4 — CI/CD jeanOS Shop (Tekton + ArgoCD): docs/SEMANA-4-REPLICAR.md
cp ansible-k8s/lab.env.example ansible-k8s/lab.env
./ansible-k8s/deploy-semana4.sh --yes
./docs/evidencias/collect-evidence.sh
```

Ver `docs/evidencias/README.md` para el checklist completo y archivos de evidencia.
