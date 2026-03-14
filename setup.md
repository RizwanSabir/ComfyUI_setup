# Portable VPS Environment Setup

## Quick Start (New VPS)

1. Mount the shared drive at `/data/share78`
2. Run the setup script (once per VPS):
   ```bash
   bash /data/share78/setup-vps.sh
   ```
3. Activate conda (every new terminal session):
   ```bash
   source /data/share78/activate.sh
   ```
4. Activate your environment:
   ```bash
   conda activate comfy
   ```

## What Each Script Does

### `setup-vps.sh` — Run Once Per VPS

Installs everything needed on a fresh VPS (in this order):

1. Symlinks `~/.claude` to the shared drive (done first so Claude Code finds existing credentials)
2. Git
3. Node.js v22 (via NodeSource apt repo)
4. Claude Code CLI on the shared drive (first VPS only — persists across VPSes)
5. Miniconda on the shared drive (first VPS only)

Safe to run multiple times — skips anything already installed.

### `activate.sh` — Run Every Session

Adds Claude Code and conda to your PATH. Source it, don't execute it:

```bash
# Correct
source /data/share78/activate.sh

# Wrong (won't affect your current shell)
bash /data/share78/activate.sh
```

### `.env-config` — Configuration

Edit this file if the mount point changes:

```bash
SHARE_DIR="/data/share78"
CONDA_DIR="/data/share78/conda"
CLAUDE_CREDS_DIR="/data/share78/claude-credentials"
NODE_VERSION="22"
```

## What Lives Where

| Location | Contents | Persistent? |
|----------|----------|-------------|
| `/data/share78/conda/` | Miniconda + all conda environments | Yes (shared drive) |
| `/data/share78/claude-credentials/` | Claude Code auth tokens + config | Yes (shared drive) |
| `/data/share78/claude-code/` | Claude Code CLI | Yes (shared drive) |
| `/data/share78/.env-config` | Path configuration | Yes (shared drive) |
| VPS `/usr/bin/git` | Git | No (per VPS) |
| VPS `/usr/bin/node` | Node.js runtime | No (per VPS) |
| VPS `~/.claude` | Symlink to shared drive | No (created by setup) |

## Common Tasks

### Create a new conda environment
```bash
source /data/share78/activate.sh
conda create -n myenv python=3.12 -y
conda activate myenv
```

### Re-authenticate Claude Code
```bash
claude login
```
Credentials are saved to the shared drive automatically via the symlink.

### Run ComfyUI
```bash
source /data/share78/activate.sh
conda activate comfy
cd /data/share78/ComfyUI_setup
./gpu_run.sh    # or ./cpu_run.sh
```

## Troubleshooting

**"Conda not found" after sourcing activate.sh:**
Run `bash /data/share78/setup-vps.sh` first.

**Permission denied on shared drive:**
The setup script uses `sudo` for creating directories on the drive. Make sure you have sudo access.

**Claude Code says "not authenticated":**
Check that the symlink exists: `ls -la ~/.claude`
It should point to `/data/share78/claude-credentials`. If not, re-run `setup-vps.sh`.
