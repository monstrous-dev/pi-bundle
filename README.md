# pi-bundle

One-shot installer for the **monstrous-dev pi stack**: the [pi coding agent](https://github.com/monstrous-dev/pi) fork plus every pi package published under [github.com/monstrous-dev](https://github.com/monstrous-dev?tab=repositories).

Two flavors, identical behavior:

- **Windows** → `install.ps1` (PowerShell 5.1+)
- **Linux / Zorin OS** → `install.sh` (bash)

## What it installs

| Component | Source | How |
|---|---|---|
| pi CLI (fork) | `github.com/monstrous-dev/pi` | clone into `E:\pi-bundle\pi` → build → `npm link` (global `pi` runs the fork) |
| foreman | `github.com/monstrous-dev/foreman` | `pi install https://github.com/monstrous-dev/foreman` |
| wikiman | `github.com/monstrous-dev/wikiman` | `pi install https://...` |
| intentman | `github.com/monstrous-dev/intentman` | `pi install https://...` |
| revertman | `github.com/monstrous-dev/revertman` | `pi install https://...` |
| showman | `github.com/monstrous-dev/showman` | `pi install https://...` |
| agentman | `github.com/monstrous-dev/agentman` | `pi install https://...` |

The package list is discovered **live** from the GitHub API (every repo except `pi` itself), with a hardcoded fallback list when offline.

## Requirements

- Windows with PowerShell 5.1+ (built in)
- git — https://git-scm.com
- Node.js **>= 22.19** — https://nodejs.org

## Run it

Windows (PowerShell):

```powershell
powershell -ExecutionPolicy Bypass -File E:\pi-bundle\install.ps1
```

Linux / Zorin (bash):

```bash
cd ~/pi-bundle && chmod +x install.sh && ./install.sh
```

Options (both flavors):

```powershell
# Windows
-BundleDir D:\somewhere          # clone location (default: alongside the script)
-Packages foreman,wikiman        # install only these, skip discovery
```

```bash
# Linux
./install.sh --bundle-dir /somewhere       # clone location (default: alongside the script)
./install.sh --packages foreman,wikiman    # install only these, skip discovery
```

## Linux notes

- If the npm global prefix is not user-writable (typical with system Node from apt/NodeSource), the script automatically switches npm to `~/.npm-global`, adds it to `~/.bashrc`, and warns you to open a new terminal so `pi` lands on PATH.
- Missing Node? The script prints the exact NodeSource 22.x one-liner (Zorin is Ubuntu-based) or points at nvm for a user-local install.

## Notes

- `npm link` **shadows any existing global `pi`** (e.g. the official npm install). Revert with:

  ```powershell
  npm uninstall -g @earendil-works/pi-coding-agent
  npm install -g --ignore-scripts @earendil-works/pi-coding-agent
  ```

- The script is **re-runnable**: an existing clone is hard-reset to `origin/main` and rebuilt; already-installed packages are overwritten by `pi install`.
- Update everything later:

  ```powershell
  git -C E:\pi-bundle\pi pull
  cd E:\pi-bundle\pi; npm install --ignore-scripts; npm run build
  pi update --extensions
  ```

- Packages install **per-user** into `~/.pi/agent/settings.json` (global for all your projects). Use `pi list` to verify, `pi remove <source>` to drop one.
