#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

if ! grep -qi microsoft /proc/version 2>/dev/null; then
  printf 'This entry point is for WSL. Use scripts/bootstrap-minimal.sh on Linux or macOS.\n' >&2
  exit 1
fi

for tool in docker k3d kubectl helm git curl; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    printf 'Required command not found on PATH: %s\n' "$tool" >&2
    printf 'Install the missing tools, then run this script again.\n' >&2
    printf 'WSL setup: https://learn.microsoft.com/windows/wsl/tutorials/wsl-containers\n' >&2
    exit 1
  fi
done

if ! docker info >/dev/null 2>&1; then
  printf 'Docker is installed but the daemon is not reachable from this WSL distribution.\n' >&2
  printf "Start Docker Desktop and enable Settings > Resources > WSL Integration for this distribution,\n" >&2
  printf 'or start the Docker Engine service inside WSL, then retry.\n' >&2
  exit 1
fi

branch="$(git branch --show-current)"
if [[ "$branch" != "minimal" ]]; then
  printf 'Expected to run from the minimal branch; current branch is %s.\n' "${branch:-detached HEAD}" >&2
  exit 1
fi

if [[ -n "$(git status --porcelain -- minimal)" ]]; then
  printf 'The minimal profile has uncommitted changes. Commit and push them before bootstrapping.\n' >&2
  exit 1
fi

remote_commit="$(git ls-remote origin refs/heads/minimal | awk 'NR == 1 { print $1 }')"
local_commit="$(git rev-parse HEAD)"
if [[ -z "$remote_commit" ]]; then
  printf 'Could not find origin/minimal on GitHub. Push the branch first:\n  git push -u origin minimal\n' >&2
  exit 1
fi
if [[ "$remote_commit" != "$local_commit" ]]; then
  printf 'Local HEAD does not match origin/minimal. Push the current commit before bootstrapping:\n' >&2
  printf '  git push origin minimal\n' >&2
  exit 1
fi

bash scripts/bootstrap-minimal.sh

wait_for_application() {
  local name="$1"
  local deadline=$((SECONDS + 1800))
  local state=""

  printf '\nWaiting for Argo CD application %s to become Synced and Healthy' "$name"
  while (( SECONDS < deadline )); do
    if state="$(kubectl get application "$name" -n argocd \
      -o jsonpath='{.status.sync.status} {.status.health.status}' 2>/dev/null)" \
      && [[ "$state" == "Synced Healthy" ]]; then
      printf ' ... ready\n'
      return 0
    fi
    printf '.'
    sleep 10
  done

  printf '\nTimed out waiting for application %s. Current Argo CD applications:\n' "$name" >&2
  kubectl get applications -n argocd >&2
  kubectl describe application "$name" -n argocd >&2
  return 1
}

wait_for_http() {
  local name="$1"
  local url="$2"
  local deadline=$((SECONDS + 180))

  printf 'Checking %s at %s' "$name" "$url"
  while (( SECONDS < deadline )); do
    if curl --fail --silent --output /dev/null "$url"; then
      printf ' ... ready\n'
      return 0
    fi
    printf '.'
    sleep 5
  done

  printf '\n%s did not respond at %s. Check WSL localhost forwarding and the ingress pod.\n' \
    "$name" "$url" >&2
  return 1
}

wait_for_application backstage
wait_for_application demo-app
wait_for_http Backstage http://idp.localhost:8080/
wait_for_http "Demo service" http://demo.localhost:8080/

printf '\nMinimal IDP is ready.\n'
printf 'Backstage:  http://idp.localhost:8080\n'
printf 'Demo app:   http://demo.localhost:8080\n'
printf 'Argo CD UI: http://localhost:8081 (after starting the port-forward below)\n\n'
printf 'kubectl port-forward -n argocd svc/argocd-server 8081:80\n\n'
printf 'Argo CD initial admin password:\n'
printf "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 --decode\n"
