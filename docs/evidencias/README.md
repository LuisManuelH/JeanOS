# Evidencias de despliegue — JeanOS Shop

Carpeta para guardar salidas de `kubectl`, logs y pruebas HTTP tras desplegar la app en Kubernetes.

## Despliegue

Desde la raíz del repositorio:

```bash
chmod +x ansible-k8s/deploy-jeanos.sh
./ansible-k8s/deploy-jeanos.sh --yes
```

Opciones:

| Flag | Uso |
|------|-----|
| `--yes` | Sin confirmación interactiva |
| `--skip-nfs` | Si el provisioner NFS y `StorageClass nfs-client` ya existen |
| `--skip-seed` | Si la tabla `productos` ya tiene datos |

Requisitos previos: cluster Kubernetes operativo, NFS accesible según `nfs-subdir-provisioner.yaml` (`192.168.41.154`), `kubectl` configurado.

## Recoger evidencias

```bash
chmod +x docs/evidencias/collect-evidence.sh
./docs/evidencias/collect-evidence.sh
# o con IP explícita del NodePort:
./docs/evidencias/collect-evidence.sh --node-ip 192.168.41.157
```

Genera:

- `docs/evidencias/YYYYMMDD-HHMMSS/` — archivos de texto y YAML
- `docs/evidencias/jeanos-deploy-evidencia-YYYYMMDD-HHMMSS.tar.gz` — paquete para entregar

## Qué incluir en la entrega (Semana 2)

| Archivo | Demuestra |
|---------|-----------|
| `05-jeanos-shop-all.txt` | Pods Running (frontend, backend, redis, postgres) |
| `32-*-init-postgres.log` | Init Container esperando PostgreSQL / tabla |
| `33-*-init-redis.log` | Init Container esperando Redis |
| `34-*-backend.log` | Node.js conectado a PG y Redis |
| `35-backend-readyz.json` | Readiness probe (`/readyz`) |
| `50-curl-frontend.txt` | Catálogo y comparador vía Nginx NodePort |
| `13-productos-data.txt` | Datos en PostgreSQL |

## Git

Las carpetas con timestamp y los `.tar.gz` son artefactos locales. Añade al `.gitignore` si no quieres versionarlos:

```gitignore
docs/evidencias/20*/
docs/evidencias/*.tar.gz
```

Sí puedes commitear este `README.md`, `collect-evidence.sh` y el script de despliegue en `ansible-k8s/`.
