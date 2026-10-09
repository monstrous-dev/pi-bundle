# =============================================================================
# pi-bundle installer
# Installs the pi coding agent from the monstrous-dev fork, then installs
# every monstrous-dev pi package (foreman, wikiman, intentman, revertman,
# showman, agentman) via `pi install`.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File E:\pi-bundle\install.ps1
#
# Optional:
#   -BundleDir <path>    where the fork is cloned   (default: E:\pi-bundle\pi)
#   -Packages a,b,c      override the package list  (default: discovered live
#                        from github.com/monstrous-dev, minus the `pi` repo)
# =============================================================================

param(
    [string]$BundleDir = "E:\pi-bundle",
    [string[]]$Packages = @()
)

$ErrorActionPreference = "Stop"
$GitHubUser = "monstrous-dev"
$ForkDir = Join-Path $BundleDir "pi"
$ForkUrl = "https://github.com/$GitHubUser/pi.git"

# Fallback package list, used when the GitHub API is unreachable.
$DefaultPackages = @("agentman", "foreman", "intentman", "revertman", "showman", "wikiman")

function Step($msg)  { Write-Host ""
                      Write-Host "==> $msg" -ForegroundColor Cyan }
function Ok($msg)    { Write-Host "    [ok] $msg" -ForegroundColor Green }
function Warn($msg)  { Write-Host "    [!!] $msg" -ForegroundColor Yellow }
function Die($msg)   { Write-Host ""
                      Write-Host "FATAL: $msg" -ForegroundColor Red
                      exit 1 }

# Run an external command, propagating failure.
function Run([string]$exe, [string[]]$exeArgs, [string]$what) {
    & $exe @exeArgs
    if ($LASTEXITCODE -ne 0) { Die "$what failed (exit $LASTEXITCODE)." }
}

# =============================================================================
Step "Checking prerequisites"

# git
$git = Get-Command git -ErrorAction SilentlyContinue
if (-not $git) { Die "git not found on PATH. Install from https://git-scm.com first." }
Ok "git: $((git --version))"

# node >= 22.19
$node = Get-Command node -ErrorAction SilentlyContinue
if (-not $node) { Die "Node.js not found on PATH. Install Node 22.19+ from https://nodejs.org first." }
$nodeVersion = (node -v) -replace '^v', ''
try {
    $nodeSem = [version]$nodeVersion
    $minSem  = [version]"22.19.0"
    if ($nodeSem -lt $minSem) { Die "Node $nodeVersion is too old. pi requires Node >= 22.19." }
    Ok "node: v$nodeVersion"
} catch {
    Die "Could not parse node version '$nodeVersion'."
}

# npm
$npm = Get-Command npm -ErrorAction SilentlyContinue
if (-not $npm) { Die "npm not found on PATH (should ship with Node.js)." }
Ok "npm: v$(npm -v)"

# =============================================================================
Step "Discovering $GitHubUser packages"

if ($Packages.Count -gt 0) {
    Ok "Using -Packages override: $($Packages -join ', ')"
} else {
    try {
        $resp = Invoke-RestMethod -Uri "https://api.github.com/users/$GitHubUser/repos?per_page=100" `
                                  -Headers @{ "User-Agent" = "pi-bundle-installer" } `
                                  -TimeoutSec 15
        $Packages = @($resp | Where-Object { $_.name -ne "pi" } | ForEach-Object { $_.name })
        if ($Packages.Count -eq 0) { throw "API returned no repos" }
        Ok "Discovered $($Packages.Count) packages: $($Packages -join ', ')"
    } catch {
        $Packages = $DefaultPackages
        Warn "GitHub API unreachable ($($_.Exception.Message)). Using fallback list: $($Packages -join ', ')"
    }
}

# =============================================================================
Step "Fetching the pi fork into $ForkDir"

if (Test-Path (Join-Path $ForkDir ".git")) {
    Ok "Already cloned - pulling latest"
    Push-Location $ForkDir
    Run git @("fetch", "origin") "git fetch"
    Run git @("reset", "--hard", "origin/main") "git reset to origin/main"
    Pop-Location
} else {
    if (-not (Test-Path $BundleDir)) {
        New-Item -ItemType Directory -Path $BundleDir -Force | Out-Null
    }
    Run git @("clone", $ForkUrl, $ForkDir) "git clone $ForkUrl"
    Ok "Cloned into $ForkDir"
}

# =============================================================================
Step "Building pi from source (this takes a few minutes)"

Push-Location $ForkDir
Run npm @("install", "--ignore-scripts") "npm install"
Run npm @("run", "build") "npm run build"
Pop-Location
Ok "Build complete"

# =============================================================================
Step "Installing the pi CLI globally (npm link)"

# NOTE: this shadows any existing global `pi` (e.g. the official npm install).
# Revert later with:
#   npm uninstall -g @earendil-works/pi-coding-agent
#   npm install -g --ignore-scripts @earendil-works/pi-coding-agent

Push-Location (Join-Path $ForkDir "packages\coding-agent")
Run npm @("link") "npm link"
Pop-Location

$piVersion = & pi --version 2>$null
if ($LASTEXITCODE -ne 0 -or -not $piVersion) {
    Die "pi is not on PATH after install. Open a NEW terminal and re-run the package-install step:"
    Write-Host "      pi install https://github.com/$GitHubUser/<package>" -ForegroundColor Gray
}
Ok "pi CLI installed: v$piVersion"

# =============================================================================
Step "Installing $($Packages.Count) pi packages"

foreach ($pkg in $Packages) {
    Write-Host ""
    Write-Host "  -- $pkg" -ForegroundColor White
    pi install "https://github.com/$GitHubUser/$pkg"
    if ($LASTEXITCODE -ne 0) {
        Warn "pi install failed for '$pkg' - continuing with the rest."
    } else {
        Ok "installed: $pkg"
    }
}

# =============================================================================
Step "Verifying"

Write-Host ""
pi list
if ($LASTEXITCODE -ne 0) { Warn "pi list returned errors." }

Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host " pi-bundle install complete" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host " pi:        fork clone at $ForkDir (global CLI linked to it)"
Write-Host " packages:  $($Packages -join ', ')"
Write-Host ""
Write-Host " Update everything later:" -ForegroundColor Gray
Write-Host "   git -C $ForkDir pull" -ForegroundColor Gray
Write-Host "   cd $ForkDir; npm install --ignore-scripts; npm run build" -ForegroundColor Gray
Write-Host "   pi update --extensions" -ForegroundColor Gray
Write-Host ""
Write-Host " Start pi in any project:  pi" -ForegroundColor Gray
Write-Host ""
