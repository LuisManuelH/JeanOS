# JeanOS
Tienda de Hardware &amp; Componentes de PC

## Lab del equipo (Semanas 2–4)

Rama **`lab/equipo`**: configuración probada del cluster, monitoreo y notas Tekton/ArgoCD.

1. `git checkout lab/equipo`
2. Leer **`docs/GUIA-EQUIPO-LAB.md`** (Semana 3: **`docs/SEMANA-3-REPLICAR.md`** · Semana 4: **`docs/SEMANA-4-REPLICAR.md`**)
3. Personalizar IPs y Docker Hub: `./scripts/personalizar-lab.sh IP_MASTER IP_W1 IP_W2 TU_USUARIO_HUB`

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
