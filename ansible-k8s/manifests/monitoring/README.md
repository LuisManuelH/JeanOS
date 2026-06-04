# Monitoreo JeanOS Shop — Semana 3

Stack: **Prometheus**, **Grafana**, **Node Exporter**, **kube-state-metrics**, **Loki**, **Promtail**, **Tempo**.

- Namespace: `monitoring`
- PVCs: `storageClassName: nfs-client`
- Sin Tekton/ArgoCD
- Logs de todos los pods; filtrar `jeanos-shop` en Grafana/Loki

## Prerrequisitos

```bash
kubectl get storageclass nfs-client
kubectl get pods -n nfs-provisioner
# App jeanos-shop desplegada (backend expone /metrics)
```

Si cambiaron las IPs del cluster, editar `prometheus/configmap.yaml` (job `node-exporter`).

## Orden de despliegue

```bash
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
M="${REPO_ROOT}/ansible-k8s/manifests/monitoring"

# 1. Namespace (PSA privileged para Promtail)
kubectl apply -f "${M}/namespace.yaml"

# 2. Node Exporter (todos los nodos)
kubectl apply -f "${M}/node-exporter/daemonset.yaml"

# 3. kube-state-metrics
kubectl apply -f "${M}/prometheus/kube-state-metrics-rbac.yaml"
kubectl apply -f "${M}/prometheus/kube-state-metrics-deployment.yaml"
kubectl apply -f "${M}/prometheus/kube-state-metrics-service.yaml"

# 4. Loki (antes de Promtail)
kubectl apply -f "${M}/loki/configmap.yaml"
kubectl apply -f "${M}/loki/pvc.yaml"
kubectl apply -f "${M}/loki/deployment.yaml"
kubectl apply -f "${M}/loki/service.yaml"
kubectl wait --for=condition=available deployment/loki -n monitoring --timeout=300s

# 5. Tempo (trazas; correlación con Prometheus/Loki en Grafana)
kubectl apply -f "${M}/tempo/configmap.yaml"
kubectl apply -f "${M}/tempo/deployment.yaml"
kubectl apply -f "${M}/tempo/service.yaml"
kubectl wait --for=condition=available deployment/tempo -n monitoring --timeout=300s

# 6. Promtail
kubectl apply -f "${M}/promtail/rbac.yaml"
kubectl apply -f "${M}/promtail/configmap.yaml"
kubectl apply -f "${M}/promtail/daemonset.yaml"

# 7. Prometheus
kubectl apply -f "${M}/prometheus/rbac.yaml"
kubectl apply -f "${M}/prometheus/pvc.yaml"
kubectl apply -f "${M}/prometheus/configmap.yaml"
kubectl apply -f "${M}/prometheus/deployment.yaml"
kubectl apply -f "${M}/prometheus/service.yaml"
kubectl wait --for=condition=available deployment/prometheus -n monitoring --timeout=300s

# 8. Grafana
kubectl apply -f "${M}/grafana/pvc.yaml"
kubectl apply -f "${M}/grafana/datasources-configmap.yaml"
kubectl apply -f "${M}/grafana/deployment.yaml"
kubectl apply -f "${M}/grafana/service.yaml"
kubectl wait --for=condition=available deployment/grafana -n monitoring --timeout=300s
```

### Aplicar todo el directorio (mismo orden por prefijos de carpeta)

```bash
kubectl apply -f ansible-k8s/manifests/monitoring/namespace.yaml
kubectl apply -R -f ansible-k8s/manifests/monitoring/node-exporter/
kubectl apply -R -f ansible-k8s/manifests/monitoring/loki/
kubectl apply -R -f ansible-k8s/manifests/monitoring/tempo/
kubectl apply -R -f ansible-k8s/manifests/monitoring/promtail/
kubectl apply -R -f ansible-k8s/manifests/monitoring/prometheus/
kubectl apply -R -f ansible-k8s/manifests/monitoring/grafana/
```

> `kubectl apply -R` en la raíz de `monitoring/` puede mezclar orden; preferir el bloque secuencial de arriba.

## Acceso (NodePort)

| Servicio    | NodePort | URL ejemplo |
|-------------|----------|-------------|
| Prometheus  | 30900    | `http://<NODE_IP>:30900` |
| Grafana     | 30300    | `http://<NODE_IP>:30300` |
| JeanOS Shop | 30080    | `http://<NODE_IP>:30080` (namespace `jeanos-shop`) |

Credenciales Grafana: `admin` / `jeanos2026`

### Port-forward (alternativa)

```bash
kubectl port-forward -n monitoring svc/prometheus 9090:9090
kubectl port-forward -n monitoring svc/grafana 3000:3000
```

## Validación

```bash
# Pods y PVCs
kubectl get all,pvc -n monitoring

# Node Exporter en cada nodo
kubectl get pods -n monitoring -l app=node-exporter -o wide

# Targets Prometheus (jeanos-backend UP si la app está desplegada)
kubectl port-forward -n monitoring svc/prometheus 9090:9090 &
curl -s http://localhost:9090/api/v1/targets | grep -E '"health"|"job"'

# Métricas backend desde el cluster
kubectl run curl-metrics --rm -it --restart=Never -n jeanos-shop \
  --image=curlimages/curl:latest -- \
  curl -s http://jeanos-backend-service:3000/metrics | head -20

# Loki listo
kubectl exec -n monitoring deploy/loki -- wget -qO- http://localhost:3100/ready

# Promtail
kubectl get pods -n monitoring -l app=promtail -o wide
kubectl logs -n monitoring -l app=promtail --tail=20

# Logs jeanos-shop en Loki (Grafana Explore → Loki)
# Query: {namespace="jeanos-shop"}
# Query backend: {namespace="jeanos-shop", container="backend"}
# Query init preload: {namespace="jeanos-shop", container="preload-redis"}
```

### Grafana

1. Login `http://<NODE_IP>:30300`
2. **Explore → Prometheus**: `up{job="jeanos-backend"}`
3. **Explore → Loki**: `{namespace="jeanos-shop"}`
4. **Explore → Tempo** — Search; correlación **traces → metrics** (Prometheus) y **traces → logs** (Loki)
5. Importar dashboard nodos: **Dashboards → Import → ID `1860`** (Node Exporter Full)

## Scrape configurado (Prometheus)

| Job               | Target |
|-------------------|--------|
| `prometheus`      | localhost:9090 |
| `node-exporter`   | IPs nodos :9100 (inventory `192.168.41.x`) |
| `kube-state-metrics` | `kube-state-metrics.monitoring.svc:8080` |
| `jeanos-backend`  | `jeanos-backend-service.jeanos-shop.svc:3000` `/metrics` |
| `tempo`           | `tempo.monitoring.svc:3200` `/metrics` |

## Troubleshooting

### PVC Pending

```bash
kubectl describe pvc -n monitoring
kubectl get storageclass nfs-client
kubectl get pods -n nfs-provisioner
```

### Target node-exporter DOWN

```bash
curl http://192.168.41.154:9100/metrics | head -5
# Actualizar IPs en prometheus/configmap.yaml y:
kubectl rollout restart deployment/prometheus -n monitoring
```

### jeanos-backend DOWN en Prometheus

```bash
kubectl get pods -n jeanos-shop -l app=jeanos-backend
kubectl run t --rm -it --restart=Never -n jeanos-shop --image=curlimages/curl:latest -- \
  curl -s -o /dev/null -w "%{http_code}\n" http://jeanos-backend-service:3000/metrics
```

Rebuild de imagen backend si falta `prom-client` en el contenedor.

### Promtail sin logs

```bash
kubectl describe pod -n monitoring -l app=promtail
kubectl get namespace monitoring --show-labels | grep pod-security
```

### Grafana sin datasource

```bash
kubectl logs -n monitoring deploy/grafana --tail=50
kubectl get configmap grafana-datasources -n monitoring -o yaml
```

## Estructura

```
monitoring/
├── namespace.yaml
├── README.md
├── node-exporter/
├── prometheus/          # incluye kube-state-metrics
├── grafana/
├── loki/
├── tempo/
└── promtail/
```

## Referencia

Manifiestos basados en `examples/monitoring/`, `examples/00-namespace.yaml`, `examples/05-loki.yaml`, `examples/06-promtail.yaml`, `examples/07-tempo.yaml` (sin Tekton/ArgoCD).

### Tempo y trazas de la app

Tempo acepta OTLP en `tempo.monitoring.svc:4317` (gRPC) y `:4318` (HTTP). Sin instrumentación OpenTelemetry en el backend, Explore → Tempo puede estar vacío; las métricas de la tienda siguen en Prometheus (`jeanos_*`). Para enviar trazas desde Node.js, apunta el exporter OTLP a ese servicio.
