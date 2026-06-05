# Semana 3 — Monitoreo JeanOS Shop (desde el master)

Guía para desplegar y validar el stack de observabilidad **desde `k8s-master01`**, replicando el laboratorio de forma ordenada.

**Para el equipo (todo en el master, sin Mac):** usa primero **`docs/SEMANA-3-REPLICAR.md`** (Ruta A).

**Incluye:** Prometheus, Grafana, Node Exporter, kube-state-metrics, Loki, Promtail, métricas del backend (`/metrics`) y dashboard provisionado **jeanOS — Hardware del cluster**.

**No incluye:** Tekton, ArgoCD, `nfs-csi` (se usa `nfs-client`).

---

## 1. Qué debes tener antes de empezar

| Componente | Namespace | Comprobación |
|------------|-----------|--------------|
| Cluster Kubernetes operativo | — | `kubectl get nodes` → todos **Ready** |
| NFS + StorageClass `nfs-client` | `nfs-provisioner` | `kubectl get sc nfs-client` |
| JeanOS Shop desplegada | `jeanos-shop` | `kubectl get pods -n jeanos-shop` |
| Backend con `prom-client` y `/metrics` | `jeanos-shop` | Imagen reconstruida y desplegada |
| `kubectl` configurado en el master | — | `kubectl cluster-info` |

IPs de referencia del inventario (`ansible-k8s/inventory/hosts.ini`):

| Nodo | IP |
|------|-----|
| k8s-master01 | 192.168.41.154 |
| k8s-worker01 | 192.168.41.157 |
| k8s-worker02 | 192.168.41.158 |

---

## 2. Preparar el master

Conéctate al master y sitúate en el repositorio.

```bash
ssh root@IP_MASTER   # IP de tu k8s-master01 (ej. 172.16.50.135)

cd /root/JeanOS   # ajusta la ruta donde tengas el clone
git fetch origin && git checkout lab/equipo && git pull origin lab/equipo
```

Si personalizaste en un PC y no en el master, sube el repo antes de aplicar: **`docs/SEMANA-3-REPLICAR.md`** (Ruta B, Paso 2).

Si aún no clonaste el repo en el master:

```bash
cd /root
git clone https://github.com/<tu-usuario>/JeanOS.git
cd JeanOS
```

Variables útiles para el resto de la guía:

```bash
export REPO_ROOT="$(pwd)"
export M="${REPO_ROOT}/ansible-k8s/manifests/monitoring"
export NODE_IP=192.168.41.154   # IP del master (o cualquier nodo para NodePort)
```

---

## 3. Verificar prerequisitos (obligatorio)

Ejecuta todo desde el master.

### 3.1 Cluster y almacenamiento

```bash
kubectl get nodes -o wide

kubectl get storageclass nfs-client
kubectl get pods -n nfs-provisioner
kubectl get pvc -n jeanos-shop
```

Si `nfs-client` no existe, despliega primero el provisioner (Semana 1/2):

```bash
kubectl apply -f "${REPO_ROOT}/ansible-k8s/manifests/storage/nfs-subdir-provisioner.yaml"
```

### 3.2 Aplicación JeanOS Shop

```bash
kubectl get namespace jeanos-shop
kubectl get pods,svc -n jeanos-shop
```

Si la app no está arriba:

```bash
chmod +x "${REPO_ROOT}/ansible-k8s/deploy-jeanos.sh"
"${REPO_ROOT}/ansible-k8s/deploy-jeanos.sh" --yes --skip-nfs
# usa --skip-nfs si el provisioner NFS ya está instalado
```

### 3.3 Backend con métricas Prometheus

El target `jeanos-backend` en Prometheus necesita `GET /metrics` en el contenedor.

```bash
kubectl run curl-metrics --rm -it --restart=Never -n jeanos-shop \
  --image=curlimages/curl:latest -- \
  curl -s -o /dev/null -w "HTTP %{http_code}\n" http://jeanos-backend-service:3000/metrics
```

- **200** → OK, sigue con el stack de monitoreo.
- **404** → la imagen del backend es antigua; reconstruye y vuelve a desplegar:

```bash
cd "${REPO_ROOT}/app/backend"
docker build -t <tu-usuario>/jeanos-backend:v1 .
docker push <tu-usuario>/jeanos-backend:v1

# Asegúrate de que backend-deployment.yaml usa la misma imagen en:
#   - contenedor backend
#   - init preload-redis (si aplica)
kubectl apply -f "${REPO_ROOT}/ansible-k8s/manifests/backend/backend-deployment.yaml"
kubectl rollout status deployment/jeanos-backend -n jeanos-shop --timeout=300s
```

---

## 4. Ajustar IPs de Node Exporter (si tu lab no es 192.168.41.x)

Prometheus hace scrape por IP en el puerto **9100** (hostPort del DaemonSet).

```bash
kubectl get nodes -o wide
```

Edita el ConfigMap antes de aplicar Prometheus:

```bash
vi "${M}/prometheus/configmap.yaml"
```

Bloque `node-exporter` → `targets`:

```yaml
- '192.168.41.154:9100'   # master
- '192.168.41.157:9100'   # worker01
- '192.168.41.158:9100'   # worker02
```

Si Prometheus ya estaba desplegado y cambiaste IPs:

```bash
kubectl apply -f "${M}/prometheus/configmap.yaml"
kubectl rollout restart deployment/prometheus -n monitoring
```

---

## 5. Orden de despliegue — Semana 3 (desde el master)

Aplica en este orden. Todos los PVC usan **`storageClassName: nfs-client`**.

### Paso 1 — Namespace `monitoring`

PSA **privileged** (necesario para Promtail y `/var/log` del host).

```bash
kubectl apply -f "${M}/namespace.yaml"
kubectl get namespace monitoring --show-labels
```

### Paso 2 — Node Exporter (todos los nodos)

```bash
kubectl apply -f "${M}/node-exporter/daemonset.yaml"
kubectl get pods -n monitoring -l app=node-exporter -o wide
# Debe haber 1 pod por nodo (master + workers)
```

Comprobar métricas desde el master:

```bash
curl -s http://192.168.41.154:9100/metrics | head -5
```

Si no responde, abre el puerto en firewalld en cada nodo:

```bash
firewall-cmd --add-port=9100/tcp --permanent && firewall-cmd --reload
```

### Paso 3 — kube-state-metrics

```bash
kubectl apply -f "${M}/prometheus/kube-state-metrics-rbac.yaml"
kubectl apply -f "${M}/prometheus/kube-state-metrics-deployment.yaml"
kubectl apply -f "${M}/prometheus/kube-state-metrics-service.yaml"
kubectl wait --for=condition=available deployment/kube-state-metrics -n monitoring --timeout=120s
```

### Paso 4 — Loki (antes que Promtail)

```bash
kubectl apply -f "${M}/loki/configmap.yaml"
kubectl apply -f "${M}/loki/pvc.yaml"
kubectl apply -f "${M}/loki/deployment.yaml"
kubectl apply -f "${M}/loki/service.yaml"
kubectl wait --for=condition=available deployment/loki -n monitoring --timeout=300s
kubectl get pvc -n monitoring | grep loki
# loki-pvc debe estar Bound
```

### Paso 5 — Promtail

```bash
kubectl apply -f "${M}/promtail/rbac.yaml"
kubectl apply -f "${M}/promtail/configmap.yaml"
kubectl apply -f "${M}/promtail/daemonset.yaml"
kubectl get pods -n monitoring -l app=promtail -o wide
```

### Paso 6 — Prometheus

```bash
kubectl apply -f "${M}/prometheus/rbac.yaml"
kubectl apply -f "${M}/prometheus/pvc.yaml"
kubectl apply -f "${M}/prometheus/configmap.yaml"
kubectl apply -f "${M}/prometheus/deployment.yaml"
kubectl apply -f "${M}/prometheus/service.yaml"
kubectl wait --for=condition=available deployment/prometheus -n monitoring --timeout=300s
kubectl get pvc -n monitoring | grep prometheus
```

### Paso 7 — Grafana

```bash
kubectl apply -f "${M}/grafana/pvc.yaml"
kubectl apply -f "${M}/grafana/datasources-configmap.yaml"
kubectl apply -f "${M}/grafana/dashboards-provider-configmap.yaml"
kubectl apply -f "${M}/grafana/dashboards-configmap.yaml"
kubectl apply -f "${M}/grafana/deployment.yaml"
kubectl apply -f "${M}/grafana/service.yaml"
kubectl wait --for=condition=available deployment/grafana -n monitoring --timeout=300s
```

---

## 6. Validación completa

### 6.1 Estado general

```bash
kubectl get all,pvc -n monitoring
```

Todo relevante debe estar **Running** y PVCs **Bound**.

### 6.2 Prometheus — targets

UI: `http://${NODE_IP}:30900` → **Status → Targets**

Desde CLI:

```bash
kubectl port-forward -n monitoring svc/prometheus 9090:9090 &
sleep 2
curl -s http://localhost:9090/api/v1/targets | grep -o '"job":"[^"]*"' | sort -u
curl -s 'http://localhost:9090/api/v1/query?query=up{job="jeanos-backend"}'
kill %1 2>/dev/null || true
```

Targets esperados **UP**:

| Job | Destino |
|-----|---------|
| `prometheus` | localhost:9090 |
| `node-exporter` | IPs nodos :9100 |
| `kube-state-metrics` | servicio interno |
| `jeanos-backend` | `jeanos-backend-service.jeanos-shop.svc:3000` |
| `kubernetes-pods-annotated` | pods con anotación scrape (backend) |

### 6.3 Métricas JeanOS en `/metrics`

```bash
kubectl run curl-jeanos-metrics --rm -it --restart=Never -n jeanos-shop \
  --image=curlimages/curl:latest -- \
  sh -c "curl -s http://jeanos-backend-service:3000/metrics | grep -E '^jeanos_' | head -20"
```

Debes ver, entre otras:

- `jeanos_http_requests_total`
- `jeanos_http_request_duration_seconds`
- `jeanos_cache_hits_total` / `jeanos_cache_misses_total`
- `jeanos_comparator_requests_total`

Genera tráfico de prueba:

```bash
NODE_IP=192.168.41.154
curl -s "http://${NODE_IP}:30080/api/products" > /dev/null
curl -s "http://${NODE_IP}:30080/api/products" > /dev/null
curl -s -X POST "http://${NODE_IP}:30080/api/compare" \
  -H "Content-Type: application/json" -d '{"ids":[1,2]}' > /dev/null
```

### 6.4 Loki y logs de `jeanos-shop`

```bash
kubectl exec -n monitoring deploy/loki -- wget -qO- http://localhost:3100/ready
kubectl logs -n monitoring -l app=promtail --tail=10
```

En Grafana → **Explore → Loki**:

```logql
{namespace="jeanos-shop"}
{namespace="jeanos-shop", container="backend"}
{namespace="jeanos-shop", container="preload-redis"}
```

### 6.5 Grafana

| Campo | Valor |
|-------|--------|
| URL | `http://${NODE_IP}:30300` |
| Usuario | `admin` |
| Contraseña | `jeanos2026` |

Datasources provisionados: **Prometheus** y **Loki**.

**Explore → Prometheus:**

```promql
up{job="jeanos-backend"}
sum(rate(jeanos_http_requests_total[5m])) by (route)
```

**Dashboard hardware:** **Dashboards → JeanOS → jeanOS — Hardware del cluster** (provisionado en `grafana/dashboards-configmap.yaml`). Alternativa manual: Import → ID **1860**.

---

## 7. Puertos NodePort y firewall

| Servicio | NodePort | Uso |
|----------|----------|-----|
| Grafana | 30300 | UI métricas/logs |
| Prometheus | 30900 | UI targets y PromQL |
| JeanOS frontend | 30080 | Tienda (namespace `jeanos-shop`) |
| Node Exporter | 9100/tcp | hostPort en cada nodo (no NodePort) |

En los nodos (si usas firewalld):

```bash
for port in 30300 30900 30080 9100; do
  firewall-cmd --add-port=${port}/tcp --permanent
done
firewall-cmd --reload
```

---

## 8. Troubleshooting rápido

### PVC en Pending

```bash
kubectl describe pvc -n monitoring
kubectl get pods -n nfs-provisioner
kubectl get storageclass nfs-client
```

Causa habitual: provisioner NFS caído o export incorrecto en `192.168.41.154:/srv/nfs/dynamic`.

### Target `node-exporter` DOWN

- Pod Running en cada nodo: `kubectl get pods -n monitoring -l app=node-exporter -o wide`
- `curl http://<IP-NODO>:9100/metrics` desde el master
- IPs correctas en `prometheus/configmap.yaml`

### Target `jeanos-backend` DOWN

- Pods backend Running: `kubectl get pods -n jeanos-shop -l app=jeanos-backend`
- `/metrics` responde 200 (sección 3.3)
- Service existe: `kubectl get svc jeanos-backend-service -n jeanos-shop`

### Promtail sin logs en Loki

```bash
kubectl get namespace monitoring --show-labels | grep pod-security
# debe incluir enforce=privileged
kubectl describe pod -n monitoring -l app=promtail | tail -30
```

### Grafana sin datasource

```bash
kubectl get configmap grafana-datasources -n monitoring
kubectl logs -n monitoring deploy/grafana --tail=30
kubectl rollout restart deployment/grafana -n monitoring
```

---

## 9. Consultas PromQL útiles (entrega Semana 3)

```promql
# Disponibilidad backend
up{job="jeanos-backend"}

# RPS por ruta
sum(rate(jeanos_http_requests_total[5m])) by (route, method)

# Latencia p95
histogram_quantile(0.95,
  sum(rate(jeanos_http_request_duration_seconds_bucket[5m])) by (le, route)
)

# Ratio cache hits catálogo
sum(rate(jeanos_cache_hits_total{route="/api/products"}[5m]))
/
(
  sum(rate(jeanos_cache_hits_total{route="/api/products"}[5m]))
  + sum(rate(jeanos_cache_misses_total{route="/api/products"}[5m]))
)

# Comparador por fuente (Redis vs PostgreSQL)
sum(rate(jeanos_comparator_requests_total[5m])) by (source, status_code)
```

---

## 10. Checklist de entrega Semana 3

- [ ] Namespace `monitoring` creado con PSA privileged
- [ ] Node Exporter: 1 pod por nodo, puerto 9100 accesible
- [ ] kube-state-metrics Running
- [ ] Prometheus Running, PVC Bound, targets UP
- [ ] Grafana accesible en :30300, datasources OK
- [ ] Loki + Promtail Running, logs `{namespace="jeanos-shop"}`
- [ ] Backend `/metrics` con métricas `jeanos_*`
- [ ] Dashboard **jeanOS — Hardware del cluster** visible en Grafana (carpeta JeanOS)
- [ ] Capturas o evidencias en `docs/evidencias/` (opcional: `./docs/evidencias/collect-evidence.sh`)

---

## 11. Referencias en el repo

| Ruta | Contenido |
|------|-----------|
| `ansible-k8s/manifests/monitoring/` | Manifiestos Semana 3 |
| `ansible-k8s/manifests/monitoring/README.md` | Resumen técnico del stack |
| `ansible-k8s/deploy-jeanos.sh` | Despliegue app `jeanos-shop` |
| `examples/monitoring/` | Material de referencia del bootcamp (no borrar) |
| `app/backend/index.js` | Instrumentación `prom-client` |

---

## 12. Orden resumido (copiar/pegar en el master)

```bash
export REPO_ROOT=/root/JeanOS
export M=$REPO_ROOT/ansible-k8s/manifests/monitoring

kubectl apply -f $M/namespace.yaml
kubectl apply -f $M/node-exporter/daemonset.yaml
kubectl apply -f $M/prometheus/kube-state-metrics-rbac.yaml
kubectl apply -f $M/prometheus/kube-state-metrics-deployment.yaml
kubectl apply -f $M/prometheus/kube-state-metrics-service.yaml
kubectl apply -f $M/loki/configmap.yaml -f $M/loki/pvc.yaml -f $M/loki/deployment.yaml -f $M/loki/service.yaml
kubectl wait -n monitoring --for=condition=available deployment/loki --timeout=300s
kubectl apply -f $M/promtail/rbac.yaml -f $M/promtail/configmap.yaml -f $M/promtail/daemonset.yaml
kubectl apply -f $M/prometheus/rbac.yaml -f $M/prometheus/pvc.yaml -f $M/prometheus/configmap.yaml
kubectl apply -f $M/prometheus/deployment.yaml -f $M/prometheus/service.yaml
kubectl wait -n monitoring --for=condition=available deployment/prometheus --timeout=300s
kubectl apply -f $M/grafana/pvc.yaml -f $M/grafana/datasources-configmap.yaml
kubectl apply -f $M/grafana/deployment.yaml -f $M/grafana/service.yaml
kubectl wait -n monitoring --for=condition=available deployment/grafana --timeout=300s

kubectl get all,pvc -n monitoring
echo "Grafana:    http://192.168.41.154:30300"
echo "Prometheus: http://192.168.41.154:30900"
echo "Tienda:     http://192.168.41.154:30080"
```
