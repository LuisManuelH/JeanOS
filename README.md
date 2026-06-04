# JeanOS
Tienda de Hardware &amp; Componentes de PC

## Lab del equipo (Semanas 2–4)

Rama **`lab/equipo`**: configuración probada del cluster, monitoreo y notas Tekton/ArgoCD.

1. `git checkout lab/equipo`
2. Leer **`docs/GUIA-EQUIPO-LAB.md`**
3. Personalizar IPs y Docker Hub: `./scripts/personalizar-lab.sh IP_MASTER IP_W1 IP_W2 TU_USUARIO_HUB`

## Despliegue en Kubernetes

```bash
./ansible-k8s/deploy-jeanos.sh --yes
./docs/evidencias/collect-evidence.sh
```

Ver `docs/evidencias/README.md` para el checklist completo y archivos de evidencia.
