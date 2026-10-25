# Internal Developer Platform

This repository contains two distinct ways to use the platform:

- **Local development:** a lightweight k3d cluster for an 8 GB workstation, with
  Argo CD, Backstage, Traefik ingress, and one sample service. Start with
  [README.minimal.md](./README.minimal.md).
- **Production architecture:** the existing cloud-oriented platform, including
  Crossplane AWS provisioning, vCluster, Gatekeeper, OpenCost, and CI/CD
  workflows. See [README.production.md](./README.production.md).

The local profile is additive and does not replace or modify the existing
production configuration. Production manifests remain in their established
top-level directories so existing paths and references continue to work.
