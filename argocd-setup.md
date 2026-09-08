# Argo CD Setup on Kind

## Prerequisites

* **Docker**
* **Kind**
* **kubectl**
* **Helm**

---

## 1. Create Kind Cluster

Create `kind-config.yaml`:

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4

nodes:
  - role: control-plane
    image: kindest/node:v1.33.1
  - role: worker
    image: kindest/node:v1.33.1
  - role: worker
    image: kindest/node:v1.33.1

```

Create the cluster:

```bash
kind create cluster --config kind-config.yaml

```

Verify the cluster:

```bash
kubectl get nodes

```

---

## 2. Argo CD Setup

Add the Argo CD Helm repository:

```bash
helm repo add argo [https://argoproj.github.io/argo-helm](https://argoproj.github.io/argo-helm)
helm repo update

```

Create the namespace:

```bash
kubectl create namespace argocd

```

Install Argo CD:

```bash
helm install argocd argo/argo-cd -n argocd

```

Verify the installation:

```bash
kubectl get pods -n argocd

```

---

## 3. Access Argo CD UI

Start port forwarding:

```bash
kubectl port-forward svc/argocd-server -n argocd 8090:443

```

Open your browser and navigate to:
[https://localhost:8090](https://localhost:8090)

---

## 4. Get Admin Password

Retrieve the initial admin password:

```bash
kubectl get secret argocd-initial-admin-secret \
  -n argocd \
  -o jsonpath="{.data.password}" | base64 -d && echo

```

Log in with the following credentials:

* **Username:** `admin`
* **Password:** `<initial-password>` *(from the output of the command above)*

> **Note:** After logging in, update your password by navigating to **User Info → Update Password**.

