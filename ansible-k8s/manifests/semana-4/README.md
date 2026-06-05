# Semana 4 — CI/CD del proyecto jeanOS Shop

Tekton + ArgoCD aplicados a **esta tienda** (requerimiento R6/R7 y Semana 4 del G-09).

`examples/tekton-argocd/` es solo el tutorial con `page-public-demo`; el proyecto usa este directorio.

```bash
cd ansible-k8s
cp lab.env.example lab.env
./deploy-semana4.sh --yes
```

| Recurso | Nombre |
|---------|--------|
| ArgoCD Application | `jeanos-shop-gitops` (sync `backend/` + `frontend/`) |
| Namespace | `jeanos-shop` |
| Pipeline | `build-jeanos-shop` |
| URL tienda | http://\<IP-NODO\>:30080 |

Ver `docs/SEMANA-4-REPLICAR.md`.
