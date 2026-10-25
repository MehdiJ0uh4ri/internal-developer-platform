$ErrorActionPreference = "Stop"

function Invoke-CheckedCommand {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    & $Name @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Name failed with exit code $LASTEXITCODE"
    }
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Push-Location $repoRoot
try {
    foreach ($tool in @("docker", "k3d", "kubectl", "helm")) {
        if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
            throw "Required command '$tool' was not found on PATH."
        }
    }

    Invoke-CheckedCommand -Name "docker" -Arguments @("info")

    $clusters = & k3d cluster list 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to list k3d clusters."
    }

    if ($clusters -notmatch "(?m)^idp-minimal\s") {
        Invoke-CheckedCommand -Name "k3d" -Arguments @(
            "cluster", "create", "idp-minimal", "--config", "minimal/k3d-config.yaml"
        )
    }
    else {
        Invoke-CheckedCommand -Name "kubectl" -Arguments @(
            "config", "use-context", "k3d-idp-minimal"
        )
    }

    Invoke-CheckedCommand -Name "kubectl" -Arguments @(
        "wait", "--for=condition=Ready", "nodes", "--all", "--timeout=180s"
    )
    Invoke-CheckedCommand -Name "helm" -Arguments @(
        "repo", "add", "argo", "https://argoproj.github.io/argo-helm", "--force-update"
    )
    Invoke-CheckedCommand -Name "helm" -Arguments @("repo", "update", "argo")
    Invoke-CheckedCommand -Name "helm" -Arguments @(
        "upgrade", "--install", "argocd", "argo/argo-cd",
        "--namespace", "argocd", "--create-namespace",
        "--values", "minimal/argocd/helm-values.yaml",
        "--wait", "--timeout", "10m"
    )
    Invoke-CheckedCommand -Name "kubectl" -Arguments @(
        "apply", "-f", "minimal/argocd/bootstrap/app-of-apps.yaml"
    )

    Write-Host ""
    Write-Host "Minimal IDP bootstrap submitted."
    Write-Host "Check sync with: kubectl get applications -n argocd"
    Write-Host "Backstage: http://idp.localhost:8080"
    Write-Host "Demo app:  http://demo.localhost:8080"
}
finally {
    Pop-Location
}
