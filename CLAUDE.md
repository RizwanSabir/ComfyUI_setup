# ComfyUI Project

## Project Structure

```
ComfyUI/                  # Root project directory
├── ComfyUI/              # Cloned ComfyUI repo (git clone, NOT pip install)
│   ├── custom_nodes/     # All custom nodes go here
│   │   └── ComfyUI-Manager/
│   ├── main.py           # Entry point
│   └── requirements.txt
├── install.sh            # Automated installation script
├── custom_nodes.txt      # List of custom node GitHub URLs (one per line, # for comments)
├── cpu_run.sh            # Run ComfyUI in CPU mode (--cpu --listen 0.0.0.0 --port 3000)
├── gpu_run.sh            # Run ComfyUI in GPU mode (low/high VRAM menu, --listen 0.0.0.0 --port 3000)
└── docs/plans/           # Design and implementation plans
```

## Setup

- **Conda env:** `comfy` (Python 3.13) — always `conda activate comfy` before running
- **Install:** `./install.sh` (run inside activated conda env)
- ComfyUI is installed via `git clone`, NOT `pip install comfyui` or `comfyinstall`

## Running ComfyUI

- **CPU mode:** `./cpu_run.sh` — uses `--cpu` flag
- **GPU mode:** `./gpu_run.sh` — interactive menu for low VRAM (4-6GB) or high VRAM (12+GB)
- Both scripts listen on `0.0.0.0:3000`
- Both scripts auto-kill any existing process on port 3000 before starting
- Do NOT use `--enable-manager` flag — ComfyUI-Manager works by default without it

## Custom Nodes

- Add GitHub URLs to `custom_nodes.txt` (one per line)
- `install.sh` clones them in parallel into `ComfyUI/custom_nodes/`
- Each node's `requirements.txt` is installed automatically
- ComfyUI-Manager is just another entry in `custom_nodes.txt`

## Key Rules

- Never use `pip install comfyui` — always git clone
- Never use `--enable-manager` — manager is enabled by default
- Always activate `conda activate comfy` before running scripts
- PyTorch is installed with NVIDIA CUDA (cu124) — works for both GPU and CPU modes
