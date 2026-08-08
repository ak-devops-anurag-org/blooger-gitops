# Blooger Helm Chart — Setup & Publishing Guide

> **OCI registry:** `oci://ghcr.io/githubak2002/charts/blooger`
> **Latest version:** `0.1.1`
> **Docker Hub images:** `akdevanurag/blooger:backend` · `akdevanurag/blooger:frontend`

---

## Folder structure

```
blooger/
├── .github/
│   └── workflows/
│       └── ci.yml               ← CI Pipeline 
├── charts/
│   └── blooger/                 ← chart root (Chart.yaml lives here)
│       ├── Chart.yaml
│       ├── values.yaml
│       ├── README.md            ← shown by `helm show readme`
│       ├── .helmignore
│       └── templates/
│           ├── _helpers.tpl     ← leading _ means Helm skips it as a manifest
│           ├── NOTES.txt        ← printed after helm install
│           ├── db-secret.yaml
│           ├── db-pvc.yaml
│           ├── db-deployment.yaml
│           ├── db-service.yaml
│           ├── backend-deployment.yaml
│           ├── backend-service.yaml
│           ├── frontend-deployment.yaml
│           ├── frontend-service.yaml
│           └── frontend-ingress.yaml
├── backend                      ← node js server - backend 
├── frontend                     ← react js - fronted
├── helm-readme.md               
├── README.md                    
└── .gitignore
```

Two rules that will silently break the chart if ignored:

- **`charts/blooger/` must be exactly two levels deep.** The workflow scans `charts/*/Chart.yaml`. A chart placed at the repo root won't be found.
- **`_helpers.tpl` must keep its leading underscore.** Without it Helm treats the file as a manifest and the install fails with a confusing parse error. Run `ls charts/blooger/templates/` after cloning to confirm.

---

## Phase 1 — Lint & render locally

No cluster needed. Do this before every push.

```bash
cd blooger-helm

# structural check
helm lint charts/blooger

# render all three storage modes and confirm no template errors
helm template blooger charts/blooger -n blooger
helm template blooger charts/blooger -n blooger --set db.persistence.mode=pvc
helm template blooger charts/blooger -n blooger --set db.persistence.mode=emptyDir

# render with ingress on
helm template blooger charts/blooger -n blooger --set frontend.ingress.enabled=true
```

---

## Phase 2 — Create a kind cluster with a port mapped through

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

kubectl cluster-info --context kind-blooger
```

`extraPortMappings` must be set at **creation time** — it cannot be added to a running cluster. It's what lets you reach the app at `http://localhost:3000` without a separate `port-forward` command.

---

## Phase 3 — Install from the local chart directory

```bash
helm install blooger ./charts/blooger \
  --namespace blooger --create-namespace \
  --set frontend.service.nodePort=30080

kubectl get pods -n blooger -w
```

Backend pods show `Init:0/1` for ~30 s while `wait-for-db` polls Postgres — expected, not a failure. Once all pods are `Running` open **http://localhost:3000**.

---

## Phase 4 — Verify correctness

```bash
# 1. Probes read creds from env — must print "accepting connections"
kubectl exec -n blooger deploy/blooger-db -- \
  sh -c 'pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB"'

# 2. Auto-generated password (note it — compare after upgrade)
kubectl get secret blooger-db-secret -n blooger \
  -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d; echo

# 3. hostPath mode creates no PVC or PV
kubectl get pvc,pv -n blooger        # expect: No resources found

# 4. Data is on the node
docker exec blooger-control-plane ls /var/lib/blooger/pgdata
```

Then verify the two behaviours most likely to regress:

```bash
# Password must survive an upgrade unchanged
helm upgrade blooger ./charts/blooger -n blooger --reuse-values
kubectl get secret blooger-db-secret -n blooger \
  -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d; echo

# Data must survive a pod restart
kubectl delete pod -n blooger -l app.kubernetes.io/name=blooger-db
kubectl rollout status deploy/blooger-db -n blooger
# reload http://localhost:3000 — posts still there
```

---

## Phase 5 — Test the packaged `.tgz`

This is what users actually download, so test it rather than the directory.

```bash
helm package charts/blooger -d /tmp/cr

helm install blooger2 /tmp/cr/blooger-0.1.1.tgz \
  -n blooger2 --create-namespace

kubectl get pods -n blooger2

# clean up
helm uninstall blooger2 -n blooger2
kubectl delete namespace blooger2
```

---

## Phase 6 — Push to GitHub

```bash
git init -b main
git add .
git commit -m "Blooger Helm chart v0.1.1"

# gh CLI (recommended)
gh repo create blooger-helm --public --source=. --push

# or manually
git remote add origin https://github.com/githubak2002/blooger-helm.git
git push -u origin main
```

**One-time GitHub setting — do this before the first push or re-trigger the workflow after:**

> **Settings → Actions → General → Workflow permissions → Read and write permissions**

This is the only setting needed. No Pages branch, no `index.yaml`, no extra GitHub Pages config — the GHCR registry *is* the repo.

---

## Phase 7 — Publish to GHCR

The workflow in `.github/workflows/release.yml` does this automatically on every push to `main` that changes a file under `charts/`. To trigger it manually:

> **Actions → Publish Helm Chart to GHCR → Run workflow**

### Manual publish (without Actions)

```bash
# Login — requires a PAT with write:packages scope,
# or use GITHUB_TOKEN if running inside Actions
echo "$CR_PAT" | helm registry login ghcr.io -u githubak2002 --password-stdin

helm package charts/blooger -d /tmp/cr

# push to .../charts — helm appends the chart name automatically,
# producing .../charts/blooger. Do NOT include /blooger in the URL.
helm push /tmp/cr/blooger-0.1.1.tgz oci://ghcr.io/githubak2002/charts
```

---

## Phase 8 — Make the package public (one-time, easy to miss)

GHCR packages are **private by default**. A private chart gives consumers a bare `unauthorized` error. Flip it once:

> GitHub profile → **Packages** → `charts/blooger` → **Package settings** → **Change visibility → Public**

While there, use **Connect repository** to link the package to `blooger-helm` so it appears on the repo's front page.

---

## Phase 9 — Confirm end-to-end as an anonymous user

```bash
# log out to simulate an anonymous consumer
helm registry logout ghcr.io

# must work without credentials
helm show chart oci://ghcr.io/githubak2002/charts/blooger --version 0.1.1
```

Then do a clean install from a fresh cluster:

```bash
kind delete cluster --name blooger

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

helm install blooger \
  oci://ghcr.io/githubak2002/charts/blooger \
  --version 0.1.1 \
  --namespace blooger --create-namespace \
  --set frontend.service.nodePort=30080

kubectl get pods -n blooger -w
# → http://localhost:3000
```

If that works without credentials, so will anyone else's install.

---

## Cutting a new release

1. Bump `version:` in `charts/blooger/Chart.yaml` (e.g. `0.1.1` → `0.1.2`).
2. Commit and push to `main`.
3. The workflow lints, renders, packages, and pushes automatically.

> **If the version already exists in GHCR the workflow skips the push and logs a warning** instead of silently overwriting the tag. A forgotten version bump shows up in the Actions log.

There is no `helm repo update` step for consumers — they pin `--version` explicitly, so they get exactly what they asked for regardless of when you publish.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| `unsupported protocol scheme "oci"` | Helm < 3.8.0 — upgrade Helm |
| `unauthorized` pulling the chart | Package is still private — see Phase 8 |
| `helm search repo blooger` finds nothing | Expected — OCI charts aren't indexed. Use `helm show chart oci://...` |
| Backend stuck in `Init:0/1` beyond 2 min | `kubectl logs -n blooger <pod> -c wait-for-db` — DB pod likely crashing |
| `password authentication failed` | Stale hostPath data dir — see NOTES.txt REINSTALL section |
| Workflow ran but nothing published | Version already exists in GHCR — bump `version:` in `Chart.yaml` |
| `helm package` produces wrong version | `version:` in `Chart.yaml` must be bumped before packaging |