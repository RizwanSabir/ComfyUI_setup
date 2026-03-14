#!/bin/bash

PORT=3000

echo "Checking port $PORT..."

# Use /proc/net/tcp to find listening process (works without ss/lsof/fuser)
PID=$(python3 -c "
import os, glob
port_hex = format($PORT, 'X').upper().zfill(4)
for proto in ['/proc/net/tcp', '/proc/net/tcp6']:
    try:
        with open(proto) as f:
            for line in f.readlines()[1:]:
                parts = line.split()
                if len(parts) >= 10 and parts[1].split(':')[1] == port_hex and parts[3] == '0A':
                    inode = parts[9]
                    for fd in glob.glob('/proc/[0-9]*/fd/*'):
                        try:
                            if 'socket:[' + inode + ']' in os.readlink(fd):
                                print(fd.split('/')[2]); raise SystemExit
                        except (OSError, SystemExit) as e:
                            if isinstance(e, SystemExit): raise
    except FileNotFoundError:
        pass
" 2>/dev/null)

if [ -n "$PID" ]; then
    echo "Port in use by PID: $PID"
    echo "Killing process..."
    kill -9 $PID 2>/dev/null
    sleep 2
    echo "Port released."
else
    echo "Port is already free."
fi

# Fix PyTorch CUDA allocator for Blackwell GPUs
export PYTORCH_CUDA_ALLOC_CONF="expandable_segments:True"

# Change to Comfy directory
cd ComfyUI || { echo "Error: Comfy directory not found"; exit 1; }

# Display GPU options menu
echo ""
echo "==================================="
echo "  ComfyUI GPU Configuration Menu"
echo "==================================="
echo ""
echo "1. Low GPU  (4-6 GB VRAM)"
echo "   - Optimized for lower VRAM usage"
echo "   - Uses FP8 UNet weights"
echo "   - CPU VAE processing"
echo ""
echo "2. Normal GPU (shared/dedicated)"
echo "   - DynamicVRAM: streams weights on-demand"
echo "   - Works on shared VPS (~10GB quota)"
echo "   - Native CUDA allocator (Blackwell compatible)"
echo ""
echo "3. High VRAM (dedicated GPU only)"
echo "   - Maximum performance, models kept in GPU memory"
echo "   - Requires dedicated GPU (NOT shared VPS)"
echo "   - Will OOM on shared VPS with limited quota"
echo ""
echo -n "Select GPU mode (1, 2 or 3): "
read -r choice

case $choice in
    1)
        echo ""
        echo "Starting ComfyUI in LOW GPU mode..."
        echo "Flags: --disable-cuda-malloc --lowvram --fp8_e4m3fn-unet --cpu-vae --listen 0.0.0.0 --port 3000"
        python main.py --disable-cuda-malloc --lowvram --fp8_e4m3fn-unet --cpu-vae --listen 0.0.0.0 --port 3000
        ;;
    2)
        echo ""
        echo "Starting ComfyUI in NORMAL GPU mode (DynamicVRAM)..."
        echo "Flags: --disable-cuda-malloc --preview-method auto --listen 0.0.0.0 --port 3000"
        python main.py --disable-cuda-malloc --preview-method auto --listen 0.0.0.0 --port 3000
        ;;
    3)
        echo ""
        echo "Starting ComfyUI in HIGH VRAM mode..."
        echo "Flags: --disable-cuda-malloc --highvram --preview-method auto --listen 0.0.0.0 --port 3000"
        python main.py --disable-cuda-malloc --highvram --preview-method auto --listen 0.0.0.0 --port 3000
        ;;
    *)
        echo ""
        echo "Error: Invalid selection. Please choose 1, 2 or 3."
        exit 1
        ;;
esac
