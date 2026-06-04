# Clase 3 - Prometheus & Grafana: Monitoreo del Cluster

## Objetivo

Desplegar un stack de observabilidad de infraestructura completo en el namespace `monitoring`. Al terminar tendrás métricas de CPU, RAM y disco de cada nodo físico (Node Exporter), métricas del estado de objetos Kubernetes (kube-state-metrics), todo centralizado en Prometheus y visualizado con Grafana.

---

## Arquitectura

```
  Nodo Master          Nodo Worker-1        Nodo Worker-2
  :9100                :9100                :9100
  ┌──────────────┐     ┌──────────────┐     ┌──────────────┐
  │Node Exporter │     │Node Exporter │     │Node Exporter │
  │  (DaemonSet) │     │  (DaemonSet) │     │  (DaemonSet) │
  └──────┬───────┘     └──────┬───────┘     └──────┬───────┘
         │ hostNetwork        │ hostNetwork        │ hostNetwork
         └────────────────────┼────────────────────┘
                              │ scrape :9100
                    ┌─────────▼──────────┐
                    │     Prometheus     │  ◄── también scrape:
                    │  NodePort :30900   │       kube-state-metrics
                    │  PVC NFS 5Gi       │       kubernetes API
                    └─────────┬──────────┘
                              │ PromQL
                    ┌─────────▼──────────┐     ┌──────────────────┐
                    │      Grafana       │     │ kube-state-metrics│
                    │  NodePort :30300   │     │  Deployment :8080 │
                    │  PVC NFS 1Gi       │     │  RBAC ClusterRole │
                    └────────────────────┘     └──────────────────┘
```

---

## Pre-requisitos

- Namespace `monitoring` creado
- StorageClass `nfs-csi` disponible
- NFS server accesible desde los nodos

```bash
kubectl create namespace monitoring
kubectl get storageclass nfs-csi
showmount -e 192.168.121.135
```

---

## Paso 1 — Actualizar IPs en el ConfigMap

Antes de aplicar nada, obtener las IPs reales de los nodos:

```bash
kubectl get nodes -o wide
```

Editar [`prometheus-configmap.yaml`](prometheus-configmap.yaml) y reemplazar las IPs bajo `node-exporter`:

```yaml
- targets:
    - '192.168.109.140:9100'   # master  ← tu IP real
    - '192.168.109.141:9100'   # worker-1 ← tu IP real
    - '192.168.109.142:9100'   # worker-2 ← tu IP real
```

---

## Paso 2 — Aplicar todo

```bash
# Opción A: archivo por archivo (orden recomendado para la clase)
kubectl apply -f node-exporter-daemonset.yaml
kubectl apply -f kube-state-metrics-rbac.yaml
kubectl apply -f kube-state-metrics-deployment.yaml
kubectl apply -f kube-state-metrics-service.yaml
kubectl apply -f prometheus-pvc.yaml
kubectl apply -f prometheus-configmap.yaml
kubectl apply -f prometheus-deployment.yaml
kubectl apply -f prometheus-service.yaml
kubectl apply -f grafana-pvc.yaml
kubectl apply -f grafana-deployment.yaml
kubectl apply -f grafana-service.yaml

# Opción B: de golpe
kubectl apply -f .
```

---

## Paso 3 — Verificar

```bash
# Todo debe estar Running
kubectl get all -n monitoring

# PVCs deben estar Bound
kubectl get pvc -n monitoring

# Node Exporter: 1 pod por nodo
kubectl get pods -n monitoring -l app=node-exporter -o wide

# Probar que Node Exporter expone métricas
curl http://192.168.109.140:9100/metrics | head -20
```

---

## Acceso a las interfaces

### Prometheus UI
```
http://<IP-NODO>:30900
```
Ir a **Status → Targets** — todos deben estar **UP** (verde).

### Grafana UI
```
http://<IP-NODO>:30300
Usuario: admin
Password: Admin123!
```

**Conectar datasource:**
1. Configuration → Data Sources → Add data source → Prometheus
2. URL: `http://prometheus.monitoring.svc:9090`
3. Save & Test → debe decir "Data source is working"

**Importar dashboard de nodos:**
1. Dashboards → Import → ID: `1860` → Load
2. Seleccionar datasource Prometheus → Import

---

## Queries PromQL útiles

```promql
# CPU idle por nodo
node_cpu_seconds_total{mode="idle"}

# % CPU USADO (la query útil)
100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# Memoria disponible en GB
node_memory_MemAvailable_bytes / 1024 / 1024 / 1024

# Pods corriendo ahora mismo
count(kube_pod_status_phase{phase="Running"})

# Deployments con réplicas no disponibles
kube_deployment_status_replicas_unavailable
```

---

## Troubleshooting

### Target DOWN en Prometheus

```bash
# Verificar que el pod del exporter está corriendo
kubectl get pods -n monitoring -l app=node-exporter

# Probar conectividad manual desde el master
curl http://<IP-NODO>:9100/metrics | head -5

# Si falla, revisar firewall en el nodo
ssh root@<IP-NODO> "firewall-cmd --list-ports"
ssh root@<IP-NODO> "firewall-cmd --add-port=9100/tcp --permanent && firewall-cmd --reload"
```

### PVC en estado Pending

```bash
kubectl describe pvc prometheus-pvc -n monitoring
showmount -e 192.168.121.135
kubectl get pods -n kube-system | grep nfs
```

### Grafana "Data source not working"

```bash
# URL correcta (interna al cluster):
#   http://prometheus.monitoring.svc:9090
# URL incorrecta:
#   http://localhost:9090
#   http://192.168.109.140:30900

# Probar desde dentro del pod de Grafana
kubectl exec -n monitoring deployment/grafana -- \
  wget -qO- http://prometheus.monitoring.svc:9090/-/healthy
```

### Error de permisos NFS en Grafana

```bash
# En el servidor NFS (UID 472 = proceso Grafana)
ssh root@192.168.121.135 "chown -R 472:472 /srv/nfs/k8s"
kubectl rollout restart deployment/grafana -n monitoring
```

### Reiniciar Prometheus tras cambio de ConfigMap

```bash
kubectl rollout restart deployment/prometheus -n monitoring
kubectl rollout status deployment/prometheus -n monitoring
```

---

## Limpieza

```bash
kubectl delete -f .
kubectl delete namespace monitoring
```

---

## Archivos

| Archivo | Recurso | Descripción |
|---------|---------|-------------|
| `node-exporter-daemonset.yaml` | DaemonSet | Un pod por nodo, expone métricas del SO en :9100 |
| `kube-state-metrics-rbac.yaml` | SA + ClusterRole + CRB | Permisos para leer estado de objetos K8s |
| `kube-state-metrics-deployment.yaml` | Deployment | Métricas de pods, deployments, PVCs, etc. |
| `kube-state-metrics-service.yaml` | Service (headless) | Expone :8080 internamente |
| `prometheus-pvc.yaml` | PVC 5Gi RWO | Almacenamiento persistente en NFS |
| `prometheus-configmap.yaml` | ConfigMap | `prometheus.yml` — editar IPs antes de aplicar |
| `prometheus-deployment.yaml` | SA + ClusterRole + CRB + Deployment | Prometheus con RBAC para K8s SD |
| `prometheus-service.yaml` | Service NodePort | UI en :30900 |
| `grafana-pvc.yaml` | PVC 1Gi RWO | Dashboards y datasources persistentes en NFS |
| `grafana-deployment.yaml` | Deployment | Grafana con fsGroup 472 para NFS |
| `grafana-service.yaml` | Service NodePort | UI en :30300 |
