#!/usr/bin/env bash
set -euo pipefail

if ! command -v k3d >/dev/null 2>&1; then
  printf "Required command not found on PATH: k3d\n" >&2
  exit 1
fi

if k3d cluster list | awk 'NR > 1 && $1 == "idp-minimal" { found = 1 } END { exit !found }'; then
  k3d cluster delete idp-minimal
else
  printf 'The idp-minimal cluster does not exist; nothing to remove.\n'
fi
