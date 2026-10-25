#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

for tool in docker k3d kubectl helm; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    printf 'Required command not found on PATH: %s\n' "$tool" >&2
    exit 1
  fi
done

docker info >/dev/null

if ! k3d cluster list | awk 'NR > 1 && $1 == "idp-minimal" { found = 1 } END { exit !found }'; then
  k3d cluster create idp-minimal --config minimal/k3d-config.yaml
else
  kubectl config use-context k3d-idp-minimal
fi

kubectl wait --for=condition=Ready nodes --all --timeout=180s
helm repo add argo https://argoproj.github.io/argo-helm --force-update
helm repo update argo
helm upgrade --install argocd argo/argo-cd \
  --namespace argocd \
  --create-namespace \
  --values minimal/argocd/helm-values.yaml \
  --wait \
  --timeout 10m
kubectl apply -f minimal/argocd/bootstrap/app-of-apps.yaml

printf '\nMinimal IDP bootstrap submitted.\n'
printf 'Check sync with: kubectl get applications -n argocd\n'
printf 'Backstage: http://idp.localhost:8080\n'
printf 'Demo app:  http://demo.localhost:8080\n'
