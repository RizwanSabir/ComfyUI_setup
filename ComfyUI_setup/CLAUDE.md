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
- **GPU mode:** `./gpu_run.sh` — interactive menu: 1) Low VRAM, 2) Normal GPU (DynamicVRAM), 3) High VRAM (dedicated only)
- Both scripts listen on `0.0.0.0:3000`
- Both scripts auto-kill any existing process on port 3000 before starting
- Do NOT use `--enable-manager` flag — ComfyUI-Manager works by default without it

## Blackwell GPU / Shared VPS Notes

- **Must use `--disable-cuda-malloc`** — the default `cudaMallocAsync` allocator causes fake OOM errors on Blackwell GPUs
- **Must set `PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True`** — required for native allocator to work on shared VPS
- **Do NOT use `--highvram`** — shared VPS has ~9-10 GiB GPU quota per user (nvidia-smi shows 97GB total but most is used by other tenants). `--highvram` tries to load full models at once via `model.to(device)`, exceeding the quota. Use NORMAL_VRAM mode instead, which enables DynamicVRAM to stream weights on-demand within the quota
- `gpu_run.sh` already includes `--disable-cuda-malloc` and `expandable_segments:True`
- Option 3 (`--highvram`) is available in `gpu_run.sh` but confirmed to OOM on shared VPS — only use on dedicated GPU instances
- All custom node dependencies installed (`deepdiff`, `numba`) — all nodes load successfully

## Custom Nodes

- Add GitHub URLs to `custom_nodes.txt` (one per line)
- `install.sh` clones them in parallel into `ComfyUI/custom_nodes/`
- Each node's `requirements.txt` is installed automatically
- ComfyUI-Manager is just another entry in `custom_nodes.txt`

## Key Rules

- Never use `pip install comfyui` — always git clone
- Never use `--enable-manager` — manager is enabled by default
- Always activate `conda activate comfy` before running scripts
- PyTorch is installed with NVIDIA CUDA (cu130 nightly) for Blackwell GPU support — works for both GPU and CPU modes
