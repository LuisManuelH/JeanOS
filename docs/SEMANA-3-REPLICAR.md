# Semana 3 — Monitoreo + dashboard Grafana (jeanOS)

Guía paso a paso para que **cada compañero** replique lo mismo en su lab.

- **Rama del equipo:** `lab/equipo`
- **Resumen general:** `docs/GUIA-EQUIPO-LAB.md`
- **Detalle largo (troubleshooting):** `docs/semana-3-monitoring.md`
- **Manifiestos:** `ansible-k8s/manifests/monitoring/`

---

## ¿Solo tienes las VMs del lab? (sin Mac ni laptop)

La mayoría del equipo trabaja **solo con SSH al master**. Usa la **Ruta A** (todo en `k8s-master01`).

Si tienes un PC con Windows o Linux y quieres editar ahí, usa la **Ruta B** (opcional).

| Ruta | Dónde preparas el repo | Dónde aplicas `kubectl` |
|------|------------------------|-------------------------|
| **A — Recomendada** | En el **master** (`git clone` + `personalizar-lab.sh`) | En el **master** |
| **B — Opcional** | En tu PC (luego `scp` al master) | En el **master** |

En ambos casos el **navegador** puede ser cualquier equipo (Windows incluido) que llegue a la IP del worker: `http://IP_WORKER:30300`.

---

## Quién ejecuta qué

| Dónde | Qué haces | Herramientas |
|-------|-----------|--------------|
| **k8s-master01** | Clonar repo, personalizar IPs, `kubectl apply` | `git`, `bash`, `kubectl` |
| **Tu PC (opcional)** | Clonar/editar y copiar al master | `git`, `scp` / WinSCP / WSL |
| **Navegador (cualquier SO)** | Ver Grafana, Prometheus, tienda | Chrome, Edge, Firefox… |

> `kubectl` del cluster va **en el master**. No hace falta tener Mac ni instalar Kubernetes en tu casa.

---

## Antes de empezar (checklist)

- [ ] Cluster con nodos **Ready**: `kubectl get nodes` (en el master)
- [ ] StorageClass **`nfs-client`** y NFS funcionando
- [ ] **Semana 2** hecha: tienda en `jeanos-shop` (`./deploy-jeanos.sh --yes`)
- [ ] Backend con `/metrics` (imagen con `prom-client` desplegada)
- [ ] Conoces tus 3 IPs: master, worker1, worker2

---

## Paso 1 — Código y personalización

Sustituye las IPs por las de **tu** lab:

```bash
export IP_MASTER=172.16.50.135    # k8s-master01
export IP_WORKER1=172.16.50.136   # worker (para abrir :30300 en el navegador)
export IP_WORKER2=172.16.50.137
export DOCKERHUB=tu_usuario_dockerhub
```

### Ruta A — Todo en el master (sin PC)

Conéctate por SSH y deja el repo en `/root/JeanOS`:

```bash
ssh root@${IP_MASTER}

# Primera vez
cd /root
git clone https://github.com/aliothosa/JeanOS.git
cd JeanOS
git fetch origin
git checkout lab/equipo
git pull origin lab/equipo

# Si ya existía el clone
cd /root/JeanOS && git fetch origin && git checkout lab/equipo && git pull origin lab/equipo

chmod +x scripts/personalizar-lab.sh
./scripts/personalizar-lab.sh ${IP_MASTER} ${IP_WORKER1} ${IP_WORKER2} ${DOCKERHUB}
```

El script necesita **bash** (viene en Rocky/Alma del master). Actualiza `prometheus/configmap.yaml` con tus IPs `:9100`; si no, el dashboard de hardware sale vacío.

**Sin bash / sin git en el master:** edita a mano la lista de la sección 2 de `docs/GUIA-EQUIPO-LAB.md` (Opción B manual), sobre todo `prometheus/configmap.yaml`.

### Ruta B — Desde tu PC (Windows o Linux) y copiar al master

En **Linux** o **WSL / Git Bash** (Windows):

```bash
git clone https://github.com/aliothosa/JeanOS.git
cd JeanOS
git checkout lab/equipo && git pull origin lab/equipo
chmod +x scripts/personalizar-lab.sh
./scripts/personalizar-lab.sh IP_MASTER IP_WORKER1 IP_WORKER2 TU_USUARIO_DOCKERHUB
```

Subir al master:

```bash
# Linux / macOS / PowerShell con OpenSSH
scp -r . root@${IP_MASTER}:/root/JeanOS

# Solo monitoreo (si el resto del repo ya está en el master)
scp -r ansible-k8s/manifests/monitoring \
  root@${IP_MASTER}:/root/JeanOS/ansible-k8s/manifests/
```

En **Windows sin terminal Unix:** WinSCP o FileZilla (SFTP a `root@IP_MASTER`, carpeta `/root/JeanOS`) y edita IPs en los YAML con el bloc de notas o VS Code; luego aplica desde el master (Paso 3).

---

## Paso 2 — Ruta B únicamente: comprobar archivos en el master

Si usaste **Ruta A**, ya estás en el master con el repo listo → pasa al **Paso 3**.

Si usaste **Ruta B**, entra al master y verifica:

```bash
ssh root@${IP_MASTER}
ls /root/JeanOS/ansible-k8s/manifests/monitoring/grafana/dashboards-configmap.yaml
```

---

## Paso 3 — En el master: desplegar monitoreo completo

Conéctate al master:

```bash
ssh root@${IP_MASTER}
cd /root/JeanOS
export REPO_ROOT="$(pwd)"
export M="${REPO_ROOT}/ansible-k8s/manifests/monitoring"
```

### 3.1 Comprobar prerequisitos

```bash
kubectl get nodes
kubectl get storageclass nfs-client
kubectl get pods -n jeanos-shop
kubectl get pods -n nfs-provisioner
```

### 3.2 Aplicar manifiestos (orden fijo)

Copia y pega **todo este bloque** en el master:

```bash
cd /root/JeanOS
export M="/root/JeanOS/ansible-k8s/manifests/monitoring"

kubectl apply -f "${M}/namespace.yaml"
kubectl apply -f "${M}/node-exporter/daemonset.yaml"

kubectl apply -f "${M}/prometheus/kube-state-metrics-rbac.yaml"
kubectl apply -f "${M}/prometheus/kube-state-metrics-deployment.yaml"
kubectl apply -f "${M}/prometheus/kube-state-metrics-service.yaml"

kubectl apply -f "${M}/loki/configmap.yaml"
kubectl apply -f "${M}/loki/pvc.yaml"
kubectl apply -f "${M}/loki/deployment.yaml"
kubectl apply -f "${M}/loki/service.yaml"
kubectl wait --for=condition=available deployment/loki -n monitoring --timeout=300s

kubectl apply -f "${M}/promtail/rbac.yaml"
kubectl apply -f "${M}/promtail/configmap.yaml"
kubectl apply -f "${M}/promtail/daemonset.yaml"

kubectl apply -f "${M}/prometheus/rbac.yaml"
kubectl apply -f "${M}/prometheus/pvc.yaml"
kubectl apply -f "${M}/prometheus/configmap.yaml"
kubectl apply -f "${M}/prometheus/deployment.yaml"
kubectl apply -f "${M}/prometheus/service.yaml"
kubectl wait --for=condition=available deployment/prometheus -n monitoring --timeout=300s

# Grafana + dashboard provisionado (carpeta JeanOS en la UI)
kubectl apply -f "${M}/grafana/pvc.yaml"
kubectl apply -f "${M}/grafana/datasources-configmap.yaml"
kubectl apply -f "${M}/grafana/dashboards-provider-configmap.yaml"
kubectl apply -f "${M}/grafana/dashboards-configmap.yaml"
kubectl apply -f "${M}/grafana/deployment.yaml"
kubectl apply -f "${M}/grafana/service.yaml"
kubectl wait --for=condition=available deployment/grafana -n monitoring --timeout=300s
```

### 3.3 Firewall (en **cada** nodo si usas firewalld)

```bash
for port in 9100 30080 30300 30900; do
  firewall-cmd --add-port=${port}/tcp --permanent
done
firewall-cmd --permanent --zone=trusted --add-source=10.244.0.0/16
firewall-cmd --reload
```

---

## Paso 4 — Solo dashboard Grafana (cluster ya tenía Grafana antigua)

Si ya desplegaste monitoreo **antes** de que existiera el dashboard en el repo, no hace falta repetir todo: aplica solo Grafana dashboards + deployment y reinicia.

**Ruta A (recomendada):** en el master, tras `git pull` en `/root/JeanOS`:

```bash
cd /root/JeanOS
git pull origin lab/equipo
M=ansible-k8s/manifests/monitoring/grafana
kubectl apply -f "${M}/dashboards-provider-configmap.yaml"
kubectl apply -f "${M}/dashboards-configmap.yaml"
kubectl apply -f "${M}/deployment.yaml"
kubectl rollout restart deployment/grafana -n monitoring
kubectl rollout status deployment/grafana -n monitoring --timeout=180s
```

**Ruta B:** copia los 3 YAML con `scp` o WinSCP a `/tmp/grafana-lab/` en el master y ejecuta el mismo `kubectl apply` apuntando a `/tmp/grafana-lab/`.

En ambas rutas, al final:

```bash
kubectl rollout status deployment/grafana -n monitoring --timeout=180s
```

---

## Paso 5 — Validar (master + navegador)

### 5.1 En el master (CLI)

```bash
kubectl get pods -n monitoring
kubectl get cm -n monitoring | grep grafana
# Debes ver: grafana-dashboards y grafana-dashboards-provider

kubectl get deploy grafana -n monitoring -o jsonpath='{.spec.template.spec.containers[0].volumeMounts[*].name}{"\n"}'
# Debe incluir: dashboards-provider dashboards

# Prometheus: 3 nodos node-exporter + backend
kubectl run prom-check --rm -i --restart=Never -n monitoring --image=curlimages/curl:8.5.0 -- \
  sh -c 'curl -sG http://prometheus.monitoring.svc:9090/api/v1/query \
    --data-urlencode "query=count(up{job=\"node-exporter\"} == 1)"; echo'
# Esperado: "3" si tienes 3 nodos

# Dashboard registrado en Grafana
kubectl run grafana-check --rm -i --restart=Never -n monitoring --image=curlimages/curl:8.5.0 -- \
  curl -s -u admin:jeanos2026 "http://grafana.monitoring.svc:3000/api/search?type=dash-db"
# Debe aparecer: "jeanOS — Hardware del cluster"
```

### 5.2 En el navegador (Windows, Linux o el propio master)

| Qué | URL | Credenciales |
|-----|-----|--------------|
| Grafana | `http://IP_WORKER1:30300` | `admin` / `jeanos2026` |
| Prometheus | `http://IP_WORKER1:30900` | — |
| Tienda | `http://IP_WORKER1:30080` | — |

En Grafana:

1. **Dashboards → JeanOS → jeanOS — Hardware del cluster**
2. Si las gráficas de CPU/RAM están vacías → revisa IPs en `prometheus/configmap.yaml` y reinicia Prometheus:
   ```bash
   kubectl rollout restart deployment/prometheus -n monitoring
   ```
3. Para ver tráfico Redis vs Postgres en el dashboard, genera requests en la tienda:
   ```bash
   curl -s "http://IP_WORKER1:30080/api/products" > /dev/null
   curl -s "http://IP_WORKER1:30080/api/products" > /dev/null
   ```

---

## Paso 6 — Actualizar después de un `git pull` del equipo

Cuando `lab/equipo` traiga cambios de monitoreo:

```bash
# Master (Ruta A)
cd /root/JeanOS && git checkout lab/equipo && git pull origin lab/equipo
./scripts/personalizar-lab.sh IP_MASTER IP_W1 IP_W2 TU_DOCKERHUB

# O desde PC (Ruta B): git pull + personalizar + scp .../monitoring/grafana al master

# Master — si cambió solo el JSON del dashboard:
cd /root/JeanOS
M=ansible-k8s/manifests/monitoring/grafana
kubectl apply -f "${M}/dashboards-configmap.yaml"
kubectl rollout restart deployment/grafana -n monitoring
```

Si cambiaron IPs de nodos en Prometheus:

```bash
kubectl apply -f /root/JeanOS/ansible-k8s/manifests/monitoring/prometheus/configmap.yaml
kubectl rollout restart deployment/prometheus -n monitoring
```

---

## Archivos del dashboard (referencia)

```
ansible-k8s/manifests/monitoring/grafana/
├── datasources-configmap.yaml          # Prometheus + Loki
├── dashboards-provider-configmap.yaml  # carpeta "JeanOS" en UI
├── dashboards-configmap.yaml           # JSON: jeanOS — Hardware del cluster
├── deployment.yaml                     # monta provisioning + dashboards
├── pvc.yaml
└── service.yaml                        # NodePort 30300
```

No hace falta **importar** el dashboard 1860 a mano; viene del ConfigMap al arrancar Grafana.

---

## Problemas frecuentes

| Síntoma | Qué revisar |
|---------|-------------|
| No aparece carpeta **JeanOS** | ¿Aplicaste `dashboards-*` y `deployment.yaml`? `kubectl rollout restart deployment/grafana -n monitoring` |
| Dashboard vacío en CPU/RAM | IPs incorrectas en `prometheus/configmap.yaml` → `personalizar-lab.sh` + restart Prometheus |
| `jeanos-backend` DOWN en dashboard | Semana 2: `kubectl get pods -n jeanos-shop` y `/metrics` |
| No abre `:30300` | Firewall en nodos; prueba otro worker |
| Grafana login falla | `admin` / `jeanos2026` (ver `grafana/deployment.yaml`) |

Más detalle: `docs/semana-3-monitoring.md` y `ansible-k8s/manifests/monitoring/README.md`.

---

## Siguiente paso — Semana 4

Con monitoreo y tienda OK, continúa con CI/CD (Tekton + ArgoCD): **`docs/SEMANA-4-REPLICAR.md`**.
