[CmdletBinding(SupportsShouldProcess = $true)]
param(
  [ValidateSet("backend", "frontend", "all")]
  [string]$Service = "all",
  [string]$BackendDigest,
  [string]$FrontendDigest
)

# Fleet-side digest pinner for Clean Mail (deploy authority lives here; the
# app repos' scripts/update-deploy-image.ps1 is retired). Edits
# clusters/themachine/apps/clean-mail/*.yaml in place; commit/push/PR stay
# explicit manual steps.

$ErrorActionPreference = "Stop"

# Digests are resolved on themachine via crictl, reusing the cluster's
# existing GHCR pull credential — avoids a separate local GHCR login.
$RemoteHost = "mzakhar@192.168.1.3"

$repoRoot = Split-Path -Parent $PSScriptRoot
$branch = (git -C $repoRoot branch --show-current).Trim()
if ($LASTEXITCODE -ne 0) {
  throw "Could not determine the current Git branch."
}
if ($branch -in @("main", "master")) {
  throw "Create a deployment branch before pinning images; refusing to edit $branch."
}

$manifestDir = Join-Path $repoRoot "clusters/themachine/apps/clean-mail"

$services = @{
  backend  = @{
    ImageName      = "ghcr.io/mzakhar/clean-mail-backend"
    ImageRef       = "ghcr.io/mzakhar/clean-mail-backend:main"
    DeploymentPath = Join-Path $manifestDir "backend.yaml"
    Digest         = $BackendDigest
  }
  frontend = @{
    ImageName      = "ghcr.io/mzakhar/clean-mail-frontend"
    ImageRef       = "ghcr.io/mzakhar/clean-mail-frontend:main"
    DeploymentPath = Join-Path $manifestDir "frontend.yaml"
    Digest         = $FrontendDigest
  }
}

function Resolve-ImageDigest {
  param([string]$Ref)

  # Runs entirely on themachine: decodes the GHCR pull secret (post-cutover
  # clean-mail/clean-mail-ghcr-pull, pre-cutover fallback gmail-app/ghcr-pull),
  # pulls by tag via crictl using that credential, then reads back the digest.
  # The token itself never crosses back over SSH — only the digest line does.
  $remoteScript = @'
set -euo pipefail
ref="$1"
cfg=$(kubectl get secret clean-mail-ghcr-pull -n clean-mail -o jsonpath='{.data.\.dockerconfigjson}' 2>/dev/null | base64 -d) \
  || cfg=$(kubectl get secret ghcr-pull -n gmail-app -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d)
auth_b64=$(echo "$cfg" | jq -r '.auths["ghcr.io"].auth')
auth=$(echo "$auth_b64" | base64 -d)
user="${auth%%:*}"
token="${auth#*:}"
sudo crictl pull --creds "${user}:${token}" "$ref" >/dev/null
sudo crictl inspecti -o json "$ref" | jq -r '.status.repoDigests[0]'
'@

  $remoteScriptUnix = ($remoteScript -replace "`r`n", "`n").TrimStart([char]0xFEFF)
  $remoteScriptB64 = [Convert]::ToBase64String([System.Text.UTF8Encoding]::new($false).GetBytes($remoteScriptUnix))
  $result = ssh $RemoteHost "printf '%s' '$remoteScriptB64' | base64 -d | bash -s -- '$Ref'" 2>&1
  if ($LASTEXITCODE -ne 0) {
    throw "Remote digest resolution failed for $Ref via themachine ($RemoteHost):`n$result"
  }

  $digestMatch = $result | Select-String -Pattern 'sha256:[a-f0-9]{64}' | Select-Object -Last 1
  if (-not $digestMatch) {
    throw "Could not parse digest for $Ref from themachine output:`n$result"
  }
  return $digestMatch.Matches[0].Value
}

$targets = if ($Service -eq "all") { @("backend", "frontend") } else { @($Service) }
foreach ($svc in $targets) {
  $s = $services[$svc]
  $deployPath = $s.DeploymentPath

  if (-not (Test-Path -LiteralPath $deployPath)) {
    throw "Deployment manifest not found: $deployPath"
  }

  $digest = $s.Digest
  if (-not $digest) {
    $digest = Resolve-ImageDigest -Ref $s.ImageRef
  }

  if ($digest -notmatch '^sha256:[a-f0-9]{64}$') {
    throw "Invalid digest for $svc`: $digest"
  }

  $pinnedImage = "$($s.ImageName)@$digest"
  $content = Get-Content -Raw -LiteralPath $deployPath
  $updated = $content -replace "image:\s+$([regex]::Escape($s.ImageName))(?:[:@][^\s]+)?", "image: $pinnedImage"

  if ($updated -eq $content) {
    Write-Host "$svc image is already pinned to $digest"
    continue
  }

  if ($PSCmdlet.ShouldProcess($deployPath, "Pin $svc image to $pinnedImage")) {
    [System.IO.File]::WriteAllText(
      $deployPath,
      $updated,
      [System.Text.UTF8Encoding]::new($false)
    )

    Write-Host "Pinned $svc image:"
    Write-Host "  $pinnedImage"
  }
}
