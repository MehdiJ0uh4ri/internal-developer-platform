# Internal Developer Platform (IDP)

A production-ready IDP built on open-source cloud-native tooling.

## What's included

| Layer | Tool | Purpose |
|---|---|---|
| Developer portal | Backstage | Self-service UI, software catalog, golden-path templates |
| Infrastructure API | Crossplane | Provision environments (VPC + EKS + RDS) via K8s CRDs |
| GitOps | ArgoCD | App-of-apps, sync waves, drift detection |
| Multi-tenancy | vCluster | Isolated virtual clusters per team |
| Policy enforcement | OPA Gatekeeper | No root, required labels, port-22 block |
| FinOps | OpenCost | Per-team chargeback + budget alerts |
| CI/CD | GitHub Actions | Golden path: build→SAST→test→push→deploy |
| Ephemeral envs | GitHub Actions + Crossplane | PR environments, auto-destroy on merge |

## Directory layout

```
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

```
1. Install ArgoCD in the management cluster
   kubectl apply -n argocd -f argocd/bootstrap/app-of-apps.yaml

2. ArgoCD syncs platform stack (Crossplane, Gatekeeper, OpenCost, vCluster operator)

3. Register Backstage templates in the software catalog

4. Teams create environments via Backstage -> Crossplane claim -> ArgoCD app
```

## Key design decisions

- Crossplane as the infrastructure API: teams request environments via K8s CRDs, not
  Terraform pipelines. Changes go through PRs; ArgoCD applies them.
- Sync waves: platform infra (wave 0) -> CRDs (wave 1) -> controllers (wave 2)
  -> tenant workloads (wave 3). Prevents race conditions during bootstrap.
- vCluster for isolation: stronger than namespace-per-team without full cluster overhead.
  Each team's vCluster runs its own API server and scheduler.
- OPA Gatekeeper in audit + deny mode: ConstraintTemplates cluster-wide; Constraints
  scoped to tenant namespaces.
- OpenCost label-driven chargeback: team and env labels on every resource enable
  per-team cost attribution via the OpenCost API and Grafana.
