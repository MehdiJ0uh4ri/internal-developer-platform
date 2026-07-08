# Developer Platform — Team Guide

This document explains what the platform does, why it exists, and how to use it day-to-day.
No infrastructure knowledge required to get started.

---

## Why this platform exists

Before this platform, spinning up a new environment meant opening a ticket, waiting for an ops
engineer, and hoping the resulting setup matched what you expected. Deploying a service meant
writing CI pipelines from scratch, configuring RBAC manually, and figuring out cost attribution
yourself.

This platform removes all of that friction. You describe what you want (an environment, a service,
a preview deployment) and the platform provisions it automatically, consistently, and within
guardrails that keep the cluster safe and costs visible.

---

## Who does what

| Role | What the platform does for you |
|---|---|
| **Developer** | Self-service environments, preview URLs per PR, standard CI/CD pipeline |
| **Tech lead** | Cost dashboards per team, budget alerts, namespace quotas |
| **New joiner** | One Backstage template → repo + pipeline + environment, no ops ticket needed |
| **Platform team** | Manages the platform itself; you don't need to touch infra for day-to-day work |

---

## The big picture

```
You open Backstage
       │
       ▼
Fill in a form (team name, environment type, resource size)
       │
       ▼
Backstage opens a Pull Request in the GitOps repo
       │
       ▼
Platform team reviews + merges  (or auto-merges for dev environments)
       │
       ▼
ArgoCD detects the new file and applies it to the cluster
       │
       ▼
Crossplane reads the request and provisions the infrastructure (VPC, EKS, namespace)
       │
       ▼
Your environment is ready — RBAC, quotas, and cost labels all set up automatically
```

Everything is driven by Git. There is no clicking in the AWS console, no manual `kubectl apply`,
and no configuration that lives only on someone's laptop.

---

## Core concepts (plain language)

### Backstage — the front door
Backstage is the web portal you use to interact with the platform. Think of it as an internal
app store. From Backstage you can:

- Browse the **software catalog** — every service, its owner, its deployment status, its docs
- Use **templates** to provision environments or scaffold new services in a few clicks
- See **ArgoCD sync status** for your apps without leaving the portal
- Read **TechDocs** for every service that keeps documentation next to its code

### Crossplane — infrastructure as code, but simpler
Instead of writing Terraform and running pipelines, you write a short YAML file describing
what you need. Crossplane reads that file and creates the real AWS resources (VPC, EKS node
group, RDS, S3 — whatever is in the composition).

From your perspective: fill in the Backstage form → a YAML file appears in Git → your
environment exists. You never touch AWS directly.

### ArgoCD — the deploy engine
ArgoCD watches this Git repository. When a file changes, it applies the change to the cluster.
When you delete a file, it removes the corresponding resources. This is called GitOps: Git is
the single source of truth for what should be running.

ArgoCD also does **drift detection** — if someone manually changes something in the cluster,
ArgoCD detects the difference and either alerts you or reverts it, depending on the environment.

### vCluster — your own cluster, without the cost
For teams that need strong isolation (staging, compliance-sensitive workloads), the platform
can give you a **virtual cluster** — your own Kubernetes API server and scheduler, running
as pods inside the shared cluster. You get full `kubectl` access as if it were a real cluster,
without the cost of running one.

For most dev environments a plain namespace is sufficient and is the default.

### OPA Gatekeeper — the safety net
Every resource you create passes through three automatic checks:

1. **No root containers** — your containers must not run as root (uid 0) or request privileged
   mode. This prevents a compromised container from affecting the host node.
2. **Required labels** — every namespace and deployment must carry `team`, `env`, and
   `cost-center` labels. Without them, costs cannot be attributed and alerts cannot route.
3. **No port 22** — containers and services may not expose port 22 (SSH). Use `kubectl exec`
   to get a shell into a running container instead.

If your resource violates a policy, the API server rejects it immediately with a clear message
explaining which rule failed. Policies are also checked in your CI pipeline via Conftest before
anything reaches the cluster.

### OpenCost — where is the money going?
OpenCost measures what every pod, namespace, and team costs in real time. Costs are broken
down by CPU, memory, storage, and network. The Grafana dashboard shows:

- Monthly spend per team
- Budget utilisation (how close you are to your limit)
- Daily trend — useful for spotting runaway workloads
- Top 10 most expensive pods

If your team's projected monthly spend crosses **80% of the budget**, you get a Slack alert.
At **100%** it escalates to a critical alert. Budgets are set when you provision an environment
and can be updated via a PR.

---

## How to provision a new environment

1. Open [Backstage](https://backstage.company.com) and go to **Create → Provision a Team Environment**
2. Fill in:
   - **Team name** — lowercase slug, e.g. `payments`
   - **Environment** — `dev`, `staging`, or `prod`
   - **Isolation** — `namespace` (default) or `vcluster` (for staging/prod or compliance needs)
   - **Resource sizing** — CPU/memory limits and monthly budget
3. Click **Create** — Backstage opens a PR in the environments repo
4. For `dev`: the PR is auto-merged. For `staging`/`prod`: a platform engineer reviews it.
5. Once merged, ArgoCD syncs within ~60 seconds. Your namespace (or vCluster) is ready.

You will receive a comment on the PR with your namespace name and the ArgoCD application URL.

---

## How to scaffold a new service

1. Open Backstage → **Create → New Service (Golden Path)**
2. Fill in: service name, description, owning team, language, target namespace
3. Backstage creates:
   - A new GitHub repository with a Dockerfile and Helm chart skeleton
   - A golden-path CI/CD pipeline (`.github/workflows/ci.yaml`) already wired up
   - A Backstage catalog entry so the service appears in the portal immediately
   - An ArgoCD Application pointing to your namespace

From the first commit, your service has: automated builds, SAST scanning, dependency
vulnerability scanning, container image signing, and deployment to your dev environment.

---

## The CI/CD pipeline explained

Every service scaffolded by the platform uses the same pipeline. Here is what runs on every PR:

```
Push / PR
   │
   ├── Build
   │     Docker image built and pushed to ghcr.io with the commit SHA as tag
   │
   ├── SAST (static analysis)
   │     CodeQL scans for security issues in your source code
   │     Semgrep checks for OWASP Top 10 patterns and hardcoded secrets
   │
   ├── SCA (dependency scan)
   │     Trivy scans your dependencies and the built image for known CVEs
   │     HIGH and CRITICAL findings block the pipeline
   │
   ├── Tests
   │     Unit tests and integration tests run against a docker-compose stack
   │     Coverage is posted as a PR comment
   │
   └── Policy check
         Conftest renders your Helm chart and validates it against platform policies
         (same rules as Gatekeeper, caught before the cluster ever sees the manifest)

On merge to main:
   └── Deploy
         ArgoCD Image Updater picks up the new image tag and rolls it out
         Pipeline waits for the rollout to complete before marking the job green
```

Security scan results appear in the GitHub **Security** tab of your repository. You do not
need to configure any of this — it comes with every service from day one.

---

## Ephemeral PR environments

If you add the label **`deploy-preview`** to a Pull Request, the platform automatically:

1. Creates a temporary namespace `pr-<number>` with a ResourceQuota (capped at 2 CPU / 2 GB)
2. Deploys your service at the PR's commit SHA with image tag `pr-<number>`
3. Posts a preview URL and ArgoCD link as a comment on the PR

When the PR is closed or merged, the namespace is destroyed automatically. No cleanup needed.

This is useful for:
- Showing a feature to a stakeholder before it merges
- Running QA or manual testing against a real deployment
- Catching environment-specific issues that unit tests cannot catch

---

## Accessing your environment

```bash
# Get kubeconfig for your namespace
kubectl config set-context --current --namespace=<team>-ns

# List your pods
kubectl get pods

# Get a shell in a running container (replaces SSH)
kubectl exec -it <pod-name> -- /bin/sh

# View logs
kubectl logs -f <pod-name>

# Port-forward a service to your laptop
kubectl port-forward svc/<service-name> 8080:8080
```

For vCluster environments, the platform team provides a separate kubeconfig file.

---

## Cost and budget management

### Viewing your team's costs
Open [Grafana → IDP Chargeback](https://grafana.company.com/d/idp-chargeback). Filter by your
team name to see:
- Current month spend and trend
- Breakdown by CPU / memory / storage / network
- Which pods are the most expensive

### Staying within budget
- **80% threshold** → Slack warning in `#platform-alerts` (and your team channel)
- **100% threshold** → Critical alert, platform team is notified

To increase your budget, open a PR changing the `budgetUSD` field in your environment claim
file (`crossplane/claims/<your-claim>.yaml`). It takes effect after the PR merges.

### Keeping costs low
The biggest cost drivers are typically:
- Pods with no resource requests (scheduler over-provisions the node)
- Test databases left running overnight
- Forgotten PR environments (these self-destruct, but check occasionally)

Every resource must carry `team` and `env` labels (enforced by Gatekeeper). Anything without
labels shows up in the **Unattributed Cost** panel and triggers a platform alert.

---

## Common problems and fixes

**My deployment is stuck in `Progressing`**
Check `kubectl describe deployment <name> -n <namespace>` for resource quota violations.
If you hit a CPU or memory limit, open a PR to increase the quota in your environment claim.

**Gatekeeper is blocking my resource with "Missing required labels"**
Add `team`, `env`, and `cost-center` labels to your Deployment metadata and its pod template.
Example:
```yaml
metadata:
  labels:
    team: payments
    env: dev
    app: checkout-api
    cost-center: payments
```

**Gatekeeper is blocking "must not run as root"**
Add a `securityContext` to your container:
```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  allowPrivilegeEscalation: false
  capabilities:
    drop: [ALL]
```

**ArgoCD shows `OutOfSync` on my app**
Click **Sync** in the ArgoCD UI, or run:
```bash
argocd app sync <app-name> --server argocd.company.com
```
If the app keeps drifting, check whether something outside of Git is modifying the resource
(e.g., an HPA changing replica counts — this is expected and is already in the ignore list).

**My PR environment was not created**
Make sure the PR has the `deploy-preview` label. The pipeline only runs when that label is present.

---

## Getting help

| Need | Where to go |
|---|---|
| Portal / templates | `#platform-support` on Slack |
| Budget / cost questions | `#finops` on Slack |
| Security scan failures | Check the **Security** tab in your repo; ask in `#security` |
| Platform outage | `#platform-alerts` — the on-call SRE is paged automatically |
| New feature request | Open an issue in the `idp` repo with the `enhancement` label |

---

## Glossary

| Term | Meaning |
|---|---|
| **Claim** | A YAML file that requests infrastructure from Crossplane |
| **Composition** | The Crossplane blueprint that defines what gets created when a claim is submitted |
| **XRD** | Composite Resource Definition — the schema for a Claim |
| **App of Apps** | An ArgoCD pattern where one root Application manages all other Applications |
| **Sync wave** | An ordering mechanism in ArgoCD — lower waves deploy before higher waves |
| **vCluster** | A virtual Kubernetes cluster running inside the shared cluster |
| **ConstraintTemplate** | An OPA Gatekeeper policy definition written in Rego |
| **Constraint** | An instance of a ConstraintTemplate applied to specific resources or namespaces |
| **Chargeback** | Attributing real infrastructure cost back to the team that consumed it |
| **Golden path** | The opinionated, pre-configured route through the platform that works for most teams |
| **SAST** | Static Application Security Testing — scans your source code |
| **SCA** | Software Composition Analysis — scans your dependencies for known vulnerabilities |
| **Ephemeral env** | A temporary environment tied to a PR lifetime, destroyed on close/merge |
