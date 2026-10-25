# Minimal local developer platform

This profile runs the core developer experience on one laptop or PC with 8 GB
RAM. It uses k3d (Kubernetes in Docker), Argo CD, the upstream Backstage demo
chart, Traefik (bundled with k3s), and one small NGINX sample service. It is for
local development and evaluation, not production use.

## Architecture and separation

```text
minimal/
  k3d-config.yaml                   # Single-node cluster and local HTTP port
  kustomization.yaml                # Root Kustomize build for the demo Application
  argocd/
    bootstrap/app-of-apps.yaml      # Root GitOps Application
    applications/                  # Backstage and demo app Applications
    helm-values.yaml                # Resource-conscious Argo CD install
  base/demo-app/                    # Reusable sample app Kubernetes resources
  overlays/demo-app/                # Local ingress and small resource patch
scripts/
  wsl-up.sh                         # WSL preflight, bootstrap, and readiness check
  bootstrap-minimal.ps1             # Windows bootstrap
  bootstrap-minimal.sh              # macOS/Linux bootstrap
  teardown-minimal.ps1              # Windows teardown
  teardown-minimal.sh               # macOS/Linux/WSL teardown
```

The production-oriented configuration remains in its existing top-level
directories (`argocd/`, `backstage/`, `crossplane/`, `kubernetes/`, `policies/`,
`opencost/`, and `pipelines/`). The local profile deploys none of Crossplane,
vCluster, Gatekeeper, OpenCost, AWS infrastructure, or the PR-environment
workflows.

## Prerequisites

- 8 GB RAM; close other memory-heavy workloads while starting the cluster.
- Docker Desktop (Windows/macOS) or Docker Engine (Linux), running.
- For WSL 2, Docker Desktop's WSL integration must be enabled for your
  distribution, or Docker Engine must be running inside WSL.
- `k3d` ([install](https://k3d.io/stable/#installation)), `kubectl`
  ([install](https://kubernetes.io/docs/tasks/tools/)), Helm 3
  ([install](https://helm.sh/docs/intro/install/)), and Git installed and on
  `PATH`.
- Network access to GitHub, the Helm chart repositories, and container
  registries.
- The `minimal` branch pushed to the configured GitHub repository. Argo CD
  reads the manifests from `https://github.com/MehdiJ0uh4ri/internal-developer-platform`,
  branch `minimal`. For a fork or private repository, update the `repoURL` and
  revision in the root Application and both child Application manifests,
  update the catalog URL in the Backstage Application, and configure Git
  credentials in Argo CD and Backstage as needed.

If this branch has not been pushed yet, publish it first:

```bash
git push -u origin minimal
```

## Resource profile

All applications use one replica. Backstage requests 512 MiB and is limited to
1 GiB; Argo CD component requests and limits are set individually in
`minimal/argocd/helm-values.yaml`; the demo app requests 32 MiB and is limited
to 64 MiB. The cluster also uses k3s' bundled Traefik ingress controller.

## Start the platform

From the repository root:

**Windows PowerShell**

```powershell
.\scripts\bootstrap-minimal.ps1
```

**WSL 2**

In Docker Desktop on Windows, enable **Settings → Resources → WSL Integration**
for your distribution, then verify Docker is available inside WSL:

```bash
docker info
```

Clone the branch inside the WSL filesystem for better performance (or `cd` to
an existing checkout):

```bash
mkdir -p ~/src
cd ~/src
git clone --branch minimal https://github.com/MehdiJ0uh4ri/internal-developer-platform.git
cd internal-developer-platform
```

Install `k3d`, `kubectl`, and Helm 3 if they are not already on your WSL `PATH`.
The official installation instructions are linked in the prerequisites above.
Then run:

```bash
bash scripts/wsl-up.sh
```

The WSL script checks Docker, required tools, and that the current `minimal`
branch is clean and pushed to GitHub; it then bootstraps the cluster, waits for
both Argo CD applications, and checks that both local URLs respond. On success
it prints the Argo CD port-forward command and initial admin password command.

**macOS or Linux**

```bash
bash scripts/bootstrap-minimal.sh
```

The scripts create or reuse the `idp-minimal` k3d cluster, install the
single-replica Argo CD chart with reduced resource requests, and apply the root
Application. The WSL entry point also waits for Backstage and the sample app to
be healthy and checks both local URLs. First-time image pulls can take several
minutes.

Track deployment:

```bash
kubectl get applications -n argocd
kubectl get pods -A
```

PowerShell users can run the same `kubectl` commands.

## Open the services

- Backstage: [http://idp.localhost:8080](http://idp.localhost:8080)
- Demo service: [http://demo.localhost:8080](http://demo.localhost:8080)
- Argo CD: start a local port-forward:

  ```bash
  kubectl port-forward -n argocd svc/argocd-server 8081:80
  ```

  Then open [http://localhost:8081](http://localhost:8081). Sign in as
  `admin`; retrieve the initial password with:

  On PowerShell, use:

  ```powershell
  kubectl -n argocd get secret argocd-initial-admin-secret `
    -o jsonpath="{.data.password}" |
    ForEach-Object { [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($_)) }
  ```

  On macOS, Linux, or WSL, use:

  ```bash
  kubectl -n argocd get secret argocd-initial-admin-secret \
    -o jsonpath='{.data.password}' | base64 --decode
  ```

The Argo CD port-forward command stays active in that terminal; press
`Ctrl+C` when finished. The local HTTP endpoints are intended for a trusted
machine only.

## Validation checklist

1. `kubectl get nodes` reports the local node as `Ready`.
2. `kubectl get applications -n argocd` shows `backstage` and `demo-app` as
   `Synced` and `Healthy`.
3. `kubectl get pods -A` shows the Backstage and demo pods as `Running` and
   ready.
4. Backstage loads at `http://idp.localhost:8080`; the sample service loads at
   `http://demo.localhost:8080`.
5. The Argo CD UI is reachable through the port-forward and shows the two
   managed applications.

If a workload is not ready, inspect it with
`kubectl describe pod -n <namespace> <pod>` and
`kubectl logs -n <namespace> <pod>`.

## Stop and remove the local cluster

To stop and remove the cluster and its local Kubernetes data:

**Windows PowerShell**

```powershell
.\scripts\teardown-minimal.ps1
```

**macOS, Linux, or WSL**

```bash
bash scripts/teardown-minimal.sh
```

This removes only the k3d cluster named `idp-minimal`. It does not alter the
production configuration or other clusters.
