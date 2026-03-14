# Claude Progress Log

## 2026-03-14: Fixed CUDA "no kernel image" error for Blackwell GPU

### Problem
ComfyUI crashed with `RuntimeError: CUDA error: no kernel image is available for execution on the device` during CLIP text encoding. The error occurred in `comfy/ops.py` at the `torch.nn.functional.embedding` call.

### Root Cause
- **GPU**: NVIDIA RTX PRO 6000 Blackwell Server Edition (compute capability 12.0, `sm_120`)
- **Installed PyTorch**: 2.6.0+cu124 — only supported up to `sm_90` (Hopper)
- PyTorch had no compiled kernels for the Blackwell architecture

### Fix
- Upgraded PyTorch in the `comfy` conda env from `2.6.0+cu124` to `2.12.0.dev20260314+cu128`
- The `cu128` nightly build includes `sm_120` (Blackwell) support
- Install command: `pip install --pre torch torchvision torchaudio --index-url https://download.pytorch.org/whl/nightly/cu128`
- Verified CUDA tensor operations work correctly on the Blackwell GPU

### Files Updated
- `install.sh` — changed PyTorch install line from `cu124` to `cu128` nightly
- `CLAUDE.md` — updated PyTorch CUDA version reference

### Notes
- The `comfy` conda env uses Python 3.12 at `/data/share78/conda/envs/comfy/bin/python`
- `conda activate comfy` currently resolves `python` to the base env (`/data/share78/conda/bin/python`) which has PyTorch 2.10.0+cu128 — the comfy env's own Python must be invoked directly or the PATH issue should be investigated
- The `cu126` nightly does NOT include Blackwell support — only `cu128` and above do

## 2026-03-14: Fixed CUDA OOM and VAE decode errors on Blackwell GPU

### Problem
Two errors when running ComfyUI with `--highvram` and `cudaMallocAsync` on Blackwell GPU:

1. **Fake OOM with cudaMallocAsync**: `torch.OutOfMemoryError: Allocation on device 0 would exceed allowed memory` — only 8.38 GiB allocated out of 94.97 GiB, trying to allocate just 75 MiB. The cudaMallocAsync memory pool wasn't scaling properly for Blackwell on PyTorch 2.12.0.dev+cu128.

2. **VAE CPU/GPU mismatch with --highvram**: After fixing OOM by disabling cudaMallocAsync, `--highvram` forced all models onto GPU. When diffusion model + VAE exceeded memory, VAE weights got offloaded to CPU, then tiled VAE decode failed with `RuntimeError: Input type (CUDABFloat16Type) and weight type (CPUBFloat16Type) should be the same`.

### Root Cause
- **cudaMallocAsync** allocator (set in `cuda_malloc.py`) has pool size limitations that don't auto-scale for Blackwell GPUs with large VRAM (97 GB)
- **--highvram** mode disables dynamic model offloading, so when the VAE can't fit alongside the diffusion model, it falls back incorrectly

### Fix
- Added `--disable-cuda-malloc` to both GPU run modes — uses native CUDA allocator which works correctly on Blackwell
- Removed `--highvram` from option 2 — uses NORMAL_VRAM mode with DynamicVRAM support, which intelligently manages model loading/offloading

### Files Updated
- `gpu_run.sh` — both options now use `--disable-cuda-malloc`; option 2 no longer uses `--highvram`
- `CLAUDE.md` — updated GPU mode documentation

### Key Diagnostics
- `cuda_malloc.py` sets `PYTORCH_CUDA_ALLOC_CONF=backend:cudaMallocAsync` by default for PyTorch 2.0+
- With native allocator + NORMAL_VRAM: `DynamicVRAM support detected and enabled`, models load/offload correctly
- GPU: NVIDIA RTX PRO 6000 Blackwell Server Edition, 97250 MB VRAM, compute capability 12.0

## 2026-03-14: Shared VPS GPU quota & PyTorch cu130 upgrade

### Problem
After attaching drive to new VPS instance, OOM errors persisted even with `--disable-cuda-malloc` and native allocator. Both cu128 and cu130 showed the same error: `CUDA out of memory. Tried to allocate 76 MiB` with 93.47 GiB reported "free" and only 8.45 GiB allocated.

### Root Cause
- **Shared VPS GPU quota**: `nvidia-smi` shows 87GB used with "no running processes" — memory is consumed by other tenants on the same physical GPU
- `torch.cuda.mem_get_info()` reports physical GPU free memory (~93 GiB), NOT the per-tenant quota (~9-10 GiB)
- `--highvram` calls `model.to(device)` to load the full diffusion model at once, exceeding the ~9-10 GiB tenant quota
- This is NOT a PyTorch allocator bug — it's a hard limit imposed by the VPS GPU virtualization layer

### What was tried
1. `--disable-cuda-malloc` (native allocator) — still OOM with `--highvram`
2. `PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True` — still OOM with `--highvram`
3. Upgraded PyTorch from cu128 to cu130 — still OOM with `--highvram`
4. **NORMAL_VRAM mode (no `--highvram`) + `expandable_segments:True`** — WORKS. DynamicVRAM streams weights in small chunks within the tenant quota

### Fix
- Use NORMAL_VRAM (default, no `--highvram`) — DynamicVRAM streams model weights on-demand
- Set `PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True` in `gpu_run.sh`
- Keep `--disable-cuda-malloc` for Blackwell compatibility
- Upgraded PyTorch to cu130 for optimized Blackwell CUDA operations

### Files Updated
- `gpu_run.sh` — option 2 renamed to "Normal GPU", added `expandable_segments:True` env var, no `--highvram`
- `install.sh` — PyTorch install changed from cu128 to cu130
- `CLAUDE.md` — updated Blackwell/shared VPS notes and PyTorch version
- `claude-progress.md` — this entry

### Performance Note
DynamicVRAM is slower than `--highvram` because it streams weights on-demand instead of pre-loading. This is the only option on shared GPU VPS. For full `--highvram` performance, a dedicated GPU instance is needed.

### Final confirmation (cu130 + highvram)
Tested `--highvram` one last time with cu130 installed — same OOM. Confirmed `--highvram` cannot work on this shared VPS regardless of PyTorch version. The GPU quota is a hard virtualization limit, not a software issue.

## 2026-03-14: Fixed missing custom node dependencies

### Problem
Two custom nodes failed to load due to missing Python packages:
- **ComfyUI-Crystools** — `ModuleNotFoundError: No module named 'deepdiff'`
- **was-node-suite-comfyui** — `ModuleNotFoundError: No module named 'numba'`

### Fix
- Installed missing packages: `pip install deepdiff numba`
- Both nodes now load successfully (Crystools 1.27.4, WAS Node Suite 220 nodes)

### Notes
- These packages are listed in the custom nodes' `requirements.txt` files but were not installed during initial setup (likely due to `set -e` in `install.sh` causing early exit on a prior error)

## 2026-03-14: Summary of working configuration

### Environment
- **GPU**: NVIDIA RTX PRO 6000 Blackwell Server Edition (shared VPS, ~9-10 GiB quota)
- **PyTorch**: 2.12.0.dev20260314+cu130
- **Python**: 3.12.12 (conda env `comfy`)
- **ComfyUI**: v0.17.0

### Working launch command
```bash
export PYTORCH_CUDA_ALLOC_CONF="expandable_segments:True"
python main.py --disable-cuda-malloc --preview-method auto --listen 0.0.0.0 --port 3000
```

### gpu_run.sh options
1. **Low GPU** — `--lowvram --fp8_e4m3fn-unet --cpu-vae` (4-6 GB VRAM)
2. **Normal GPU** — DynamicVRAM, streams weights on-demand (recommended for shared VPS)
3. **High VRAM** — `--highvram` (dedicated GPU only, OOMs on shared VPS)

### Required flags for Blackwell on shared VPS
- `--disable-cuda-malloc` — avoids cudaMallocAsync allocator bugs
- `PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True` — enables expandable memory segments
- No `--highvram` — exceeds shared VPS GPU quota
