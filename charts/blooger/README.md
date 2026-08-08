# Blooger — Helm Chart

A 3-tier demo blog app distributed as an **OCI artifact** on GitHub Container Registry. Installs on **any** Kubernetes cluster — kind, minikube, k3s, EKS, GKE, AKS, DigitalOcean — with:

- **one command, no `helm repo add`** — the registry *is* the repo
- **no cloud disk provisioned** — the database writes to a directory on its node
- **no cloud load balancer** — the frontend is exposed via NodePort / port-forward
- **no manual setup** — no StorageClass to create, no CSI driver to install, no secrets to pre-create

```
                       ┌──────────────────────────┐
   port-forward /      │  blooger-frontend        │
   NodePort  ────────▶ │  nginx, 2 replicas       │
                       │  Service: NodePort :80   │
                       └───────────┬──────────────┘
                                   │ /api → in-cluster
                       ┌───────────▼──────────────┐
                       │  blooger-backend         │
                       │  API, 2 replicas         │
                       │  Service: ClusterIP :8080│
                       └───────────┬──────────────┘
                                   │ postgres
                       ┌───────────▼──────────────┐
                       │  blooger-db              │
                       │  postgres:16-alpine, 1   │
                       │  Service: ClusterIP :5432│
                       │  data → node directory   │
                       └──────────────────────────┘
```

---

## Prerequisites

| | |
|---|---|
| A Kubernetes cluster | any distribution, cloud or local |
| `kubectl` | pointed at that cluster (`kubectl get nodes` works) |
| `helm` | **v3.8.0 or newer** — earlier versions cannot read `oci://` |

Check Helm first, because the failure mode on an old version is a confusing one:

```bash
helm version --short
```

---

## Install

```bash
helm install blooger \
  oci://ghcr.io/githubak2002/charts/blooger \
  --version 0.1.1 \
  --namespace blooger --create-namespace
```

Then open it:

```bash
kubectl port-forward -n blooger svc/blooger-frontend 3000:80
# → http://localhost:3000
```

That's the whole thing — no repo to add, no index to refresh. `helm install` prints access instructions and the generated DB password when it finishes.

**Always pass `--version`.** An OCI registry has no `index.yaml`, so there's no repo index for Helm to fall back on; pinning the version is the reliable, reproducible behaviour and avoids surprises when a new chart is published.

<details>
<summary>Inspect the chart before installing it</summary>

```bash
helm show chart   oci://ghcr.io/githubak2002/charts/blooger --version 0.1.1
helm show values  oci://ghcr.io/githubak2002/charts/blooger --version 0.1.1
helm show readme  oci://ghcr.io/githubak2002/charts/blooger --version 0.1.1

# render the manifests without installing anything
helm template blooger oci://ghcr.io/githubak2002/charts/blooger \
  --version 0.1.1 -n blooger
```

To see which versions exist, browse <https://github.com/githubak2002?tab=packages> — there's no `helm search` for OCI charts.
</details>

<details>
<summary>Watch it come up</summary>

```bash
kubectl get pods -n blooger -w
```

The backend pods sit in `Init:0/1` until Postgres is accepting connections — that's the `wait-for-db` init container doing its job, not a failure.
</details>

---

## Configuration

Everything is in [`charts/blooger/values.yaml`](charts/blooger/values.yaml), which is commented line by line. The values you're most likely to touch:

| Value | Default | What it does |
|---|---|---|
| `db.persistence.mode` | `hostPath` | `hostPath` \| `pvc` \| `emptyDir` — see [Storage](#storage) |
| `db.persistence.hostPath.path` | `/var/lib/blooger/pgdata` | directory created on the node |
| `db.persistence.hostPath.nodeName` | `""` | pin the DB pod to one node (do this on multi-node clusters) |
| `db.auth.username` | `blooger_user` | |
| `db.auth.database` | `blooger_db` | |
| `db.auth.password` | `""` | empty ⇒ auto-generated on first install, reused on upgrade |
| `db.auth.existingSecret` | `""` | use your own Secret instead |
| `backend.replicaCount` | `2` | |
| `backend.image.repository` / `.tag` | `akdevanurag/blooger` / `backend` | |
| `frontend.replicaCount` | `2` | |
| `frontend.service.type` | `NodePort` | `NodePort` \| `ClusterIP` \| `LoadBalancer` |
| `frontend.service.nodePort` | `""` | pin a port in 30000–32767 |
| `frontend.ingress.enabled` | `false` | see [Exposing the app](#exposing-the-app) |

Override inline or with a file:

```bash
helm install blooger oci://ghcr.io/githubak2002/charts/blooger \
  --version 0.1.1 -n blooger --create-namespace \
  --set backend.replicaCount=3 \
  --set frontend.service.nodePort=30080
```

```bash
helm install blooger oci://ghcr.io/githubak2002/charts/blooger \
  --version 0.1.1 -n blooger --create-namespace \
  -f my-values.yaml
```

---

## Storage

### Default: `hostPath` — nothing to provision, nothing to pay for

Postgres writes to `/var/lib/blooger/pgdata` on whichever node its pod lands on. No StorageClass, no PVC, no CSI driver, no cloud disk. Data survives pod restarts and `helm upgrade`.

**On a multi-node cluster, pin the DB pod.** Without a pin, if the pod is ever rescheduled it lands on a different node and finds an empty directory:

```bash
kubectl get nodes
helm upgrade blooger oci://ghcr.io/githubak2002/charts/blooger \
  --version 0.1.1 -n blooger --reuse-values \
  --set db.persistence.hostPath.nodeName=<node-name>
```

Single-node clusters (kind, minikube, k3s) need no pin.

**Caveats, so there are no surprises:**
- `helm uninstall` cannot delete a node directory. Remove it by hand on the node if you want a clean slate.
- If the node is deleted or replaced, the data goes with it. This is a demo app, not a production database.
- Some hardened clusters block `hostPath` volumes (GKE Autopilot always does; any namespace with Pod Security Admission set to `baseline` or `restricted` does). If your DB pod is rejected with a message about hostPath volumes, use `pvc` mode below or `--set db.persistence.mode=emptyDir`.

### `emptyDir` — throwaway

```bash
--set db.persistence.mode=emptyDir
```

Zero setup, works literally anywhere, and **wipes the database on every pod restart**. Fine for a 10-minute demo.

### `pvc` — real cloud storage, cost-optimised

Switch on dynamic provisioning when you actually want the data to outlive the node:

```bash
helm upgrade --install blooger oci://ghcr.io/githubak2002/charts/blooger \
  --version 0.1.1 -n blooger --create-namespace \
  --set db.persistence.mode=pvc \
  --set db.persistence.pvc.size=1Gi \
  --set db.persistence.pvc.storageClassName=blooger-cheap
```

Leave `storageClassName` empty to use the cluster default — but the default is usually the *expensive* class (SSD, provisioned IOPS). Create a cheap one first. Pick your provider:

<details open>
<summary><strong>AWS EKS</strong> — gp3</summary>

```bash
# 1. One-time: the EBS CSI driver is not installed on EKS by default.
eksctl utils associate-iam-oidc-provider --cluster <CLUSTER> --approve

eksctl create iamserviceaccount \
  --name ebs-csi-controller-sa \
  --namespace kube-system \
  --cluster <CLUSTER> \
  --role-name AmazonEKS_EBS_CSI_DriverRole \
  --role-only \
  --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
  --approve

eksctl create addon --name aws-ebs-csi-driver --cluster <CLUSTER> \
  --service-account-role-arn arn:aws:iam::<ACCOUNT_ID>:role/AmazonEKS_EBS_CSI_DriverRole --force

# 2. A cost-optimised StorageClass.
cat <<'EOF' | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: blooger-cheap
provisioner: ebs.csi.aws.com
parameters:
  type: gp3          # cheaper per GiB than gp2, and 3000 baseline IOPS is free
  encrypted: "true"
reclaimPolicy: Delete            # disk is destroyed with the PVC — no orphan billing
allowVolumeExpansion: true
volumeBindingMode: WaitForFirstConsumer   # creates the disk in the pod's AZ
EOF
```

Notes: gp3 bills per GiB-month plus anything above the free 3000 IOPS / 125 MB/s baseline — don't set `iops` or `throughput` parameters and you stay at baseline. Minimum billable volume is 1 GiB, so `size: 1Gi` is genuinely 1 GiB.
</details>

<details>
<summary><strong>GKE</strong> — pd-standard</summary>

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: blooger-cheap
provisioner: pd.csi.storage.gke.io
parameters:
  type: pd-standard   # spinning disk; cheapest PD type. pd-balanced if you need SSD
reclaimPolicy: Delete
allowVolumeExpansion: true
volumeBindingMode: WaitForFirstConsumer
EOF
```

Then use `--set db.persistence.pvc.size=10Gi`. Persistent Disks have a 10 GiB floor, so a smaller request just gets rounded up and billed at 10 GiB anyway.

GKE Autopilot blocks `hostPath`, so on Autopilot `pvc` mode is your only persistent option.
</details>

<details>
<summary><strong>AKS</strong> — Standard HDD</summary>

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: blooger-cheap
provisioner: disk.csi.azure.com
parameters:
  skuName: Standard_LRS   # HDD; cheapest tier. StandardSSD_LRS is the AKS default
reclaimPolicy: Delete
allowVolumeExpansion: true
volumeBindingMode: WaitForFirstConsumer
EOF
```

Azure bills managed disks in fixed tiers, and the smallest Standard HDD tier is 32 GiB — a 1 GiB request still costs you a 32 GiB disk. Ask for `--set db.persistence.pvc.size=32Gi` so the numbers at least match reality.
</details>

<details>
<summary><strong>DigitalOcean / others</strong></summary>

```bash
kubectl get storageclass          # find what's available
```

DOKS ships `do-block-storage` (1 GiB minimum). Most managed providers only offer one class, in which case just leave `storageClassName` empty.
</details>

**Cost safety:** the PVC belongs to the Helm release, so `helm uninstall` deletes it, and with `reclaimPolicy: Delete` the underlying disk goes too. Nothing keeps billing after you tear the demo down. If you'd rather keep the data:

```bash
--set db.persistence.pvc.retainOnDelete=true    # then delete the PVC manually later
```

---

## Exposing the app

No cloud load balancer is created under any default. Three options, cheapest first:

### 1. Port-forward — works everywhere, costs nothing

```bash
kubectl port-forward -n blooger svc/blooger-frontend 3000:80
```

### 2. NodePort — the default

```bash
NODE_PORT=$(kubectl get svc blooger-frontend -n blooger -o jsonpath='{.spec.ports[0].nodePort}')
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}')
echo "http://$NODE_IP:$NODE_PORT"
```

On a cloud cluster you must open that port to your IP in the node security group / firewall rule first. Pin the port for a stable URL:

```bash
--set frontend.service.nodePort=30080
```

### 3. Ingress — one shared load balancer for the whole cluster

If you want a real hostname, install an ingress controller **once** and every app in the cluster reuses its single L4 load balancer. That's far cheaper than an application load balancer per service.

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm install ingress-nginx ingress-nginx/ingress-nginx \
  -n ingress-nginx --create-namespace

helm upgrade blooger oci://ghcr.io/githubak2002/charts/blooger \
  --version 0.1.1 -n blooger --reuse-values \
  --set frontend.ingress.enabled=true \
  --set frontend.ingress.hosts[0].host=blog.example.com \
  --set frontend.ingress.hosts[0].paths[0].path=/ \
  --set frontend.ingress.hosts[0].paths[0].pathType=Prefix
```

Add `--set controller.service.type=NodePort` to the ingress-nginx install to avoid even that one load balancer. (ingress-nginx is only published as a classic Helm repo, hence `helm repo add` there.)

---

## Running locally on kind

```bash
cat <<'EOF' | kind create cluster --name blooger --config -
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    extraPortMappings:
      - containerPort: 30080
        hostPort: 3000
        protocol: TCP
EOF

helm install blooger oci://ghcr.io/githubak2002/charts/blooger \
  --version 0.1.1 -n blooger --create-namespace \
  --set frontend.service.nodePort=30080

# → http://localhost:3000
```

kind nodes are containers, so the hostPath data lives inside the node container. It survives pod restarts but not `kind delete cluster`.

---

## Upgrade, rollback, uninstall

```bash
# bump --version to the release you want; there is no `helm repo update` step
helm upgrade blooger oci://ghcr.io/githubak2002/charts/blooger \
  --version 0.2.0 -n blooger --reuse-values

helm history blooger -n blooger
helm rollback blooger 1 -n blooger

helm uninstall blooger -n blooger
kubectl delete namespace blooger
```

The auto-generated DB password is read back out of the cluster on every upgrade, so upgrades never break the backend's connection.

---

## Publishing the chart

The chart is published to GHCR as an OCI artifact by [`.github/workflows/release.yml`](.github/workflows/release.yml). Unlike a classic Helm repo, there is **no `gh-pages` branch, no `index.yaml` and no GitHub Pages** to configure.

### One-time setup

**1.** Push this repo to GitHub:

```bash
git init -b main
git add .
git commit -m "Blooger Helm chart v0.1.0"
gh repo create blooger-helm --public --source=. --push
```

**2.** **Settings → Actions → General → Workflow permissions** → *Read and write permissions*.

That's the only setting to change. The workflow requests `packages: write`, which needs this enabled.

**3.** Trigger the workflow — **Actions → Publish Helm Chart to GHCR → Run workflow**. (Your first push may have run before step 2 took effect, which is why the workflow has `workflow_dispatch`.)

**4. Make the package public.** This is the step everyone misses: GHCR packages are **private by default**, and a private chart gives strangers an `unauthorized` error rather than a helpful one.

> Your profile → **Packages** → `charts/blooger` → **Package settings** → **Change visibility** → **Public**

While you're there, use **Connect repository** to link the package to `blooger-helm` so it shows up on the repo page.

**5.** Verify as an anonymous consumer:

```bash
helm registry logout ghcr.io 2>/dev/null || true
helm show chart oci://ghcr.io/githubak2002/charts/blooger --version 0.1.1
```

If that works without credentials, so will anyone else's install.

### Cutting a new release

Bump `version:` in `charts/blooger/Chart.yaml`, commit, push. The workflow lints, renders the chart in three configurations, then pushes.

If the version already exists in GHCR the workflow **skips the push and logs a warning** rather than overwriting the tag — so a forgotten version bump shows up in the Actions log instead of silently replacing a published release.

<details>
<summary>Publishing by hand, without Actions</summary>

You need a classic PAT with the `write:packages` scope:

```bash
export CR_PAT=ghp_xxxxxxxxxxxx
echo "$CR_PAT" | helm registry login ghcr.io -u githubak2002 --password-stdin

helm package charts/blooger -d /tmp/cr
helm push /tmp/cr/blooger-0.1.0.tgz oci://ghcr.io/githubak2002/charts
```

`helm push` appends the chart name to the path, so pushing to `.../charts` produces `.../charts/blooger`. Don't include `blooger` in the push URL or you'll get `charts/blooger/blooger`.
</details>

<details>
<summary>What you give up versus a classic Helm repo</summary>

| | OCI (GHCR) | Classic repo (GitHub Pages) |
|---|---|---|
| Install | one command | `helm repo add` first |
| Hosting setup | none | gh-pages branch + Pages config |
| Minimum Helm | 3.8.0 | any Helm 3 |
| `helm search repo` | not supported | works |
| Browse versions | Packages UI or `oras repo tags` | `index.yaml` |
| Artifact Hub listing | supported, needs extra config | straightforward |
| Default visibility | **private** — must be flipped | public |

If you later want both, keep this workflow and add a second one that runs `helm package` + `helm repo index` against a `gh-pages` branch. The chart itself doesn't change.
</details>

> **Handles used in this repo, so a blind find-and-replace doesn't break things:**
> - `githubak2002` — GitHub account, used for the GHCR path and repo URLs
> - `akdevanurag` — Docker Hub account, used for `backend.image.repository` and `frontend.image.repository` in `values.yaml`
>
> These are deliberately different. Changing one does not imply changing the other.

---

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `unsupported protocol scheme "oci"` or `unknown command "registry"` | Helm older than 3.8.0. Upgrade Helm. |
| `unauthorized` / `denied` pulling the chart | The GHCR package is still private. Flip it to Public (publishing step 4), or `helm registry login ghcr.io` first. |
| `helm search repo blooger` finds nothing | Expected — OCI charts aren't indexed. Use `helm show chart oci://...` or the Packages page. |
| Backend stuck in `Init:0/1` | Normal for the first ~30s. If it persists: `kubectl logs -n blooger <pod> -c wait-for-db` and check the DB pod. |
| DB pod `CrashLoopBackOff`, logs mention the data directory isn't empty or has wrong ownership | Stale data from an earlier install in the node directory. Delete `/var/lib/blooger/pgdata` on the node, or `--set db.persistence.hostPath.path=/var/lib/blooger/pgdata2`. |
| DB pod rejected, message mentions hostPath volumes | Pod Security Admission or GKE Autopilot. Use `--set db.persistence.mode=pvc` or `emptyDir`. |
| Database is empty after a while | The DB pod moved to a different node. Pin it with `db.persistence.hostPath.nodeName`. |
| Frontend loads but the API 502s | The frontend's nginx proxies to the hostname `blooger-backend`. If you changed `naming.backend`, change it back — see the note in `values.yaml`. |
| PVC stuck `Pending` | No default StorageClass, or `WaitForFirstConsumer` waiting on the pod. `kubectl describe pvc -n blooger` will say which. |
| `helm install` says the namespace is missing | Add `--create-namespace`. |
| Workflow succeeded but nothing published | The version in `Chart.yaml` already exists in GHCR. Check the Actions log for the warning, then bump it. |
| Two releases in one namespace collide | By design — names are fixed so the frontend's baked-in hostname keeps working. Use a separate namespace per release. |

---

## Changes from the original `blooger.yaml`

| | |
|---|---|
| **Probes fixed** | `pg_isready` referenced `blooger_user` / `blooger_db` while the Secret defined `jerney_user` / `jerney_db`. It never failed loudly because `pg_isready` reports healthy whenever the server answers a connection attempt, regardless of whether that user exists. The probes now read `$POSTGRES_USER` / `$POSTGRES_DB` from the container environment, so they cannot drift from the Secret. |
| **Password removed from source** | `jerney_pass_2026` was in plaintext. It's now auto-generated at install time, persisted in the Secret, and read back on upgrade — or supply your own via `db.auth.password` / `db.auth.existingSecret`. |
| **Namespace object dropped** | Helm manages namespaces poorly (it won't clean them up, and it fights other releases for ownership). Use `--create-namespace` instead. |
| **PVC is now optional** | Default `hostPath` mode creates no PVC and no cloud disk. |
| **Named ports** | Services target `http` / `postgres` by name rather than by number, so changing a container port in `values.yaml` doesn't silently break its Service. |
| **`failureThreshold` added** | Postgres cold-starting on a slow node no longer gets killed by the liveness probe mid-`initdb`. |
| **Resource names kept fixed** | Not prefixed with the release name, because the frontend image likely has `blooger-backend` compiled into its nginx config. |