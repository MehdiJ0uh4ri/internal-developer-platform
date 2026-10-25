$ErrorActionPreference = "Stop"

if (-not (Get-Command "k3d" -ErrorAction SilentlyContinue)) {
    throw "Required command 'k3d' was not found on PATH."
}

$clusters = & k3d cluster list 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) {
    throw "Unable to list k3d clusters."
}

if ($clusters -match "(?m)^idp-minimal\s") {
    & k3d cluster delete idp-minimal
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to delete the idp-minimal cluster."
    }
}
else {
    Write-Host "The idp-minimal cluster does not exist; nothing to remove."
}
