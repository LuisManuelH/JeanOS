# Lab 11 - StorageClass y NFS CSI Driver

## Concepto

StorageClass = automatiza la creación de PVs (aprovisionamiento dinámico).

```
Static Provisioning:
  Admin → crea PV manual → Developer crea PVC → Binding

Dynamic Provisioning (CSI):
  Developer → crea PVC con storageClassName
                    ↓
              StorageClass → llama al NFS CSI Driver
                                      ↓
                              Crea subdirectorio NFS
                              Crea PV automáticamente
                                      ↓
                              PVC pasa a Bound
```

## Instalación del NFS CSI Driver

```bash
# Prerequisito: Helm instalado
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Instalar el driver
bash 00-instalar-nfs-csi.sh

# Verificar pods (1 controller + 1 node por nodo = DaemonSet)
kubectl get pods -n kube-system | grep nfs
# csi-nfs-controller-xxx   3/3   Running
# csi-nfs-node-xxx         3/3   Running   ← en cada nodo

# Verificar que se registró el CSI driver
kubectl get csidrivers
# NAME              ATTACHREQUIRED   PODINFOONMOUNT
# nfs.csi.k8s.io   false            false
```

## Flujo de aprovisionamiento dinámico

```
kubectl apply -f 02-pvc-dinamico.yaml
    ↓
Kubernetes detecta: storageClassName: nfs-csi
    ↓
NFS CSI Driver recibe la solicitud
    ↓
Driver crea subdirectorio: /srv/nfs/k8s-storage/bootcamp/pvc-dinamico/
    ↓
Driver crea PV automáticamente con la referencia al subdirectorio
    ↓
PVC pasa a estado: Bound
    ↓
Pod puede montar el PVC
```

## Comandos

```bash
# Ver StorageClasses
kubectl get storageclass
kubectl describe storageclass nfs-csi

# Crear PVC y observar el PV que se crea automáticamente
kubectl apply -f 02-pvc-dinamico.yaml
kubectl get pvc pvc-dinamico --watch   # Pending → Bound
kubectl get pv                          # ver PV creado automáticamente

# Ver el subdirectorio creado en el NFS
ssh root@192.168.109.210 "find /srv/nfs/k8s-storage -type d"

# Logs del CSI Driver (para troubleshooting)
kubectl logs -n kube-system -l app=csi-nfs-controller -c nfs
```

## Ejercicios

### Ejercicio 1 — Aprovisionamiento dinámico
1. Instala el driver: `bash 00-instalar-nfs-csi.sh`
2. Aplica la StorageClass: `kubectl apply -f 01-storageclass-nfs.yaml`
3. Crea el PVC: `kubectl apply -f 02-pvc-dinamico.yaml`
4. Observa el PV creado automáticamente: `kubectl get pv --watch`
5. Verifica en el NFS: `ssh root@192.168.109.210 "ls /srv/nfs/k8s-storage/"`

### Ejercicio 2 — Comparar Static vs Dynamic
```bash
kubectl get pv -o custom-columns=\
NAME:.metadata.name,\
STORAGECLASS:.spec.storageClassName,\
STATUS:.status.phase,\
RECLAIM:.spec.persistentVolumeReclaimPolicy
```
¿Cuál diferencia ves entre el PV del lab 10 y el de este lab?

### Ejercicio 3 — reclaimPolicy Delete en acción
```bash
# Ver el PV actual
kubectl get pv

# Borrar el PVC
kubectl delete pvc pvc-dinamico

# ¿El PV sigue existiendo?
kubectl get pv

# ¿El directorio sigue en NFS?
ssh root@192.168.109.210 "ls /srv/nfs/k8s-storage/"
```

## Limpieza

```bash
kubectl delete pod pod-pvc-dinamico --ignore-not-found
kubectl delete pvc pvc-dinamico --ignore-not-found
# El PV se borra automáticamente (reclaimPolicy: Delete)
kubectl get pv   # verificar que no queda ninguno
```
