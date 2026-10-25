# Production Internal Developer Platform

This is the existing production-oriented IDP design. Its manifests and
configuration remain in their original top-level directories; the minimal
local profile is separate and does not change this configuration.

## What's included

| Layer | Tool | Purpose |
|---|---|---|
| Developer portal | Backstage | Self-service UI, software catalog, golden-path templates |
| Infrastructure API | Crossplane | Provision environments (VPC + EKS + RDS) via Kubernetes CRDs |
| GitOps | Argo CD | App-of-apps, sync waves, drift detection |
| Multi-tenancy | vCluster | Isolated virtual clusters per team |
| Policy enforcement | OPA Gatekeeper | No root, required labels, port-22 block |
| FinOps | OpenCost | Per-team chargeback + budget alerts |
| CI/CD | GitHub Actions | Golden path: build → SAST → test → push → deploy |
| Ephemeral environments | GitHub Actions + Crossplane | PR environments, auto-destroy on merge |

## Directory layout

```text
idp/
├── backstage/           # Portal config and self-service templates
├── crossplane/          # XRDs, Compositions, Claims
├── argocd/              # App-of-apps, Projects, ApplicationSets
├── kubernetes/          # Namespaces, RBAC, Quotas, vCluster
├── policies/            # OPA Gatekeeper ConstraintTemplates + Constraints
├── opencost/            # Helm values, Grafana dashboard, budget alerts
└── pipelines/           # Golden-path CI/CD and ephemeral-env workflows
```

## Bootstrap order

```text
1. Install Argo CD in the management cluster
   kubectl apply -n argocd -f argocd/bootstrap/app-of-apps.yaml

2. Argo CD syncs platform stack (Crossplane, Gatekeeper, OpenCost, vCluster operator)

3. Register Backstage templates in the software catalog

4. Teams create environments via Backstage -> Crossplane claim -> Argo CD app
```

## Prerequisites

| Tool | Minimum version | Install |
|---|---|---|
| kubectl | 1.29 | https://kubernetes.io/docs/tasks/tools/ |
| helm | 3.14 | https://helm.sh/docs/intro/install/ |
| argocd CLI | 2.10 | `brew install argocd` |
| crossplane CLI | 1.15 | `curl -sL https://raw.githubusercontent.com/crossplane/crossplane/master/install.sh \| sh` |
| cosign | 2.2 | `brew install cosign` |
| conftest | 0.50 | `brew install conftest` |

AWS credentials with permissions to create IAM roles, EKS clusters, VPCs, and
ECR repositories must be available where Crossplane runs (for example, through
IRSA on EKS).

## Key design decisions

- Crossplane provides an infrastructure API: teams request environments through
  Kubernetes CRDs rather than Terraform pipelines. Changes go through PRs and
  Argo CD applies them.
- Sync waves order platform infrastructure (wave 0), CRDs (wave 1), controllers
  (wave 2), and tenant workloads (wave 3) to avoid bootstrap races.
- vCluster provides stronger isolation than namespace-per-team without the
  overhead of a complete physical cluster per team.
- OPA Gatekeeper runs in audit and deny modes, with cluster-wide
  ConstraintTemplates and Constraints scoped to tenant namespaces.
- OpenCost uses team and environment labels for cost attribution through the
  OpenCost API and Grafana.

See [docs/PLATFORM_GUIDE.md](./docs/PLATFORM_GUIDE.md) for the platform guide.
