# Accessing ArgoCD UI on a Private AKS Cluster

## Infrastructure Overview

The infrastructure consists of:

* A **Private AKS Cluster**
* **ArgoCD deployed inside the AKS cluster**
* A **Jump VM** deployed in the same VNet as the Private AKS cluster
* The Jump VM has **Public Access/Public IP** for administrative access

```text
Local Machine
      |
      | SSH
      v
Jump VM (Public Access)
      |
      | Private VNet
      v
Private AKS Cluster
      |
      v
ArgoCD Server
```

The AKS cluster and ArgoCD UI are not directly accessible from the internet.

---

# Accessing the ArgoCD UI

The ArgoCD UI can be accessed securely using:

1. `kubectl port-forward` on the Jump VM
2. An SSH tunnel from the local machine to the Jump VM

## Step 1: Connect to the Jump VM

From your local machine:

```bash
ssh <username>@<JUMPBOX-PUBLIC-IP>
```

The Jump VM should have access to the Private AKS cluster and `kubectl` should be configured.

---

## Step 2: Port Forward the ArgoCD Service

Run the following command on the Jump VM:

```bash
kubectl port-forward svc/argocd-server \
  -n argocd \
  8080:443
```

This makes the ArgoCD service available on the Jump VM at:

```text
https://localhost:8080
```

Keep this terminal session running.

---

## Step 3: Create an SSH Tunnel

Open another terminal on your local machine and run:

```bash
ssh -L 8080:localhost:8080 \
  <username>@<JUMPBOX-PUBLIC-IP> \
  -N
```

This creates the following connection:

```text
Local Machine:8080
        |
        | SSH Tunnel
        v
Jump VM:8080
```

---

## Step 4: Access ArgoCD UI

Open the following URL in your local browser:

```text
https://localhost:8080
```

You can now access the ArgoCD UI running inside the Private AKS cluster.

---

# Traffic Flow

```text
Local Browser
      |
      | https://localhost:8080
      v
Local Machine
      |
      | SSH Tunnel
      v
Jump VM
      |
      | kubectl port-forward
      v
Private AKS Cluster
      |
      v
argocd-server Service
      |
      v
ArgoCD UI
```

---

# Key Points

* The **AKS cluster remains private**.
* The **ArgoCD UI is not exposed directly to the internet**.
* The Jump VM acts as a secure access point to the private infrastructure.
* SSH tunneling encrypts traffic between the local machine and the Jump VM.
* `kubectl port-forward` provides temporary access to the ArgoCD service.
* Access is available only while the SSH tunnel and port-forward sessions are running.

## Architecture Summary

```text
Internet
   |
   | SSH
   v
Jump VM (Public IP)
   |
   | Private VNet Communication
   v
Private AKS Cluster
   |
   v
ArgoCD Server
```
