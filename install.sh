#!/usr/bin/env bash
# =============================================================================
# pi-bundle installer (Linux / Zorin OS)
# Installs the pi coding agent from the monstrous-dev fork, then installs
# every monstrous-dev pi package (foreman, wikiman, intentman, revertman,
# showman, agentman) via `pi install`.
#
# Usage:
#   ./install.sh
#
# Options:
#   --bundle-dir <path>   where the fork is cloned (default: alongside this script)
#   --packages a,b,c      override the package list (default: discovered live
#                         from github.com/monstrous-dev, minus the `pi` repo)
# =============================================================================
set -euo pipefail

GITHUB_USER="monstrous-dev"
FORK_URL="https://github.com/${GITHUB_USER}/pi.git"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLE_DIR="$SCRIPT_DIR"
FORK_DIR="$BUNDLE_DIR/pi"
DEFAULT_PACKAGES=(agentman foreman intentman revertman showman wikiman)
PACKAGES=()

# --- parse args -------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --bundle-dir) BUNDLE_DIR="$2"; FORK_DIR="$BUNDLE_DIR/pi"; shift 2 ;;
        --packages)   IFS=',' read -r -a PACKAGES <<< "$2"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

step() { printf '\n\033[36m==> %s\033[0m\n' "$1"; }
ok()   { printf '    \033[32m[ok]\033[0m %s\n' "$1"; }
warn() { printf '    \033[33m[!!]\033[0m %s\n' "$1"; }
die()  { printf '\n\033[31mFATAL: %s\033[0m\n' "$1" >&2; exit 1; }

# =============================================================================
step "Checking prerequisites"

command -v git  >/dev/null 2>&1 || die "git not found. Install it:  sudo apt install git"
ok "git: $(git --version)"

command -v node >/dev/null 2>&1 || die "Node.js not found. pi needs Node >= 22.19:
  curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - && sudo apt install -y nodejs
  (or use nvm: https://github.com/nvm-sh/nvm)"
NODE_MAJOR=$(node -p 'process.versions.node.split(".")[0]')
NODE_MINOR=$(node -p 'process.versions.node.split(".")[1]')
if [ "$NODE_MAJOR" -lt 22 ] || { [ "$NODE_MAJOR" -eq 22 ] && [ "$NODE_MINOR" -lt 19 ]; }; then
    die "Node $(node -v) is too old. pi requires Node >= 22.19."
fi
ok "node: v$(node -v)"

command -v npm >/dev/null 2>&1 || die "npm not found (should ship with Node.js)."
ok "npm: v$(npm -v)"

# --- npm global prefix: must be user-writable for `npm link` ----------------
NPM_PREFIX="$(npm config get prefix)"
if [ ! -w "$NPM_PREFIX" ]; then
    step "npm prefix $NPM_PREFIX is not user-writable - switching to ~/.npm-global"
    mkdir -p "$HOME/.npm-global"
    npm config set prefix "$HOME/.npm-global"
    if ! grep -q '.npm-global/bin' "$HOME/.bashrc" 2>/dev/null; then
        printf '\n# npm user-global binaries (added by pi-bundle installer)\nexport PATH="$HOME/.npm-global/bin:$PATH"\n' >> "$HOME/.bashrc"
    fi
    export PATH="$HOME/.npm-global/bin:$PATH"
    warn "PATH updated in ~/.bashrc - new terminals get 'pi' automatically."
fi
ok "npm prefix: $(npm config get prefix)"

# =============================================================================
step "Discovering ${GITHUB_USER} packages"

if [ ${#PACKAGES[@]} -eq 0 ]; then
    if PACKAGES_JSON=$(curl -fsSL --max-time 15 -H "User-Agent: pi-bundle-installer" \
        "https://api.github.com/users/${GITHUB_USER}/repos?per_page=100" 2>/dev/null); then
        PACKAGES=($(echo "$PACKAGES_JSON" | node -e '
            let d=""; process.stdin.on("data", c => d += c).on("end", () => {
                const repos = JSON.parse(d).map(r => r.name).filter(n => n !== "pi");
                console.log(repos.join("\n"));
            })'))
        if [ ${#PACKAGES[@]} -eq 0 ]; then
            warn "GitHub API returned no repos - using fallback list."
            PACKAGES=("${DEFAULT_PACKAGES[@]}")
        else
            ok "Discovered ${#PACKAGES[@]} packages: ${PACKAGES[*]}"
        fi
    else
        warn "GitHub API unreachable - using fallback list."
        PACKAGES=("${DEFAULT_PACKAGES[@]}")
    fi
else
    ok "Using --packages override: ${PACKAGES[*]}"
fi

# =============================================================================
step "Fetching the pi fork into $FORK_DIR"

if [ -d "$FORK_DIR/.git" ]; then
    ok "Already cloned - resetting to origin/main"
    git -C "$FORK_DIR" fetch origin
    git -C "$FORK_DIR" reset --hard origin/main
else
    mkdir -p "$BUNDLE_DIR"
    git clone "$FORK_URL" "$FORK_DIR"
    ok "Cloned into $FORK_DIR"
fi

# =============================================================================
step "Building pi from source (this takes a few minutes)"

( cd "$FORK_DIR" && npm install --ignore-scripts && npm run build )
ok "Build complete"

# =============================================================================
step "Installing the pi CLI globally (npm link)"

# NOTE: this shadows any existing global `pi` (e.g. the official npm install).
# Revert later with:
#   npm uninstall -g @earendil-works/pi-coding-agent
#   npm install -g --ignore-scripts @earendil-works/pi-coding-agent

( cd "$FORK_DIR/packages/coding-agent" && npm link )

if ! command -v pi >/dev/null 2>&1; then
    hash -r 2>/dev/null || true
    command -v pi >/dev/null 2>&1 || die "pi is not on PATH after install.
  Open a NEW terminal, or add your npm bin dir to PATH, then run the package installs:
  pi install https://github.com/${GITHUB_USER}/<package>"
fi
ok "pi CLI installed: v$(pi --version)"

# =============================================================================
step "Installing ${#PACKAGES[@]} pi packages"

FAILED=()
for pkg in "${PACKAGES[@]}"; do
    printf '\n  -- %s\n' "$pkg"
    if pi install "https://github.com/${GITHUB_USER}/${pkg}"; then
        ok "installed: $pkg"
    else
        warn "pi install failed for '$pkg' - continuing with the rest."
        FAILED+=("$pkg")
    fi
done

# =============================================================================
step "Verifying"

printf '\n'
pi list || warn "pi list returned errors."

printf '\n\033[36m=============================================\033[0m\n'
printf '\033[36m pi-bundle install complete\033[0m\n'
printf '\033[36m=============================================\033[0m\n'
printf '\n pi:        fork clone at %s (global CLI linked to it)\n' "$FORK_DIR"
printf ' packages:  %s\n' "${PACKAGES[*]}"
[ ${#FAILED[@]} -gt 0 ] && printf ' FAILED:    %s (re-run: pi install https://github.com/%s/<name>)\n' "${FAILED[*]}" "$GITHUB_USER"
printf '\n Update everything later:\n'
printf '   git -C %s pull\n' "$FORK_DIR"
printf '   cd %s && npm install --ignore-scripts && npm run build\n' "$FORK_DIR"
printf '   pi update --extensions\n'
printf '\n Start pi in any project:  pi\n\n'
