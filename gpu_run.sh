#!/bin/bash

# Kill any process running on port 3000
echo "Checking for processes on port 3000..."
lsof -ti:3000 | xargs kill -9 2>/dev/null || echo "No process found on port 3000"

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
echo "2. High GPU (12+ GB VRAM)"
echo "   - Maximum performance"
echo "   - Models kept in GPU memory"
echo "   - Flash Attention enabled"
echo ""
echo -n "Select GPU mode (1 or 2): "
read -r choice

case $choice in
    1)
        echo ""
        echo "Starting ComfyUI in LOW GPU mode..."
        echo "Flags: --lowvram --fp8_e4m3fn-unet --cpu-vae --listen 0.0.0.0 --port 3000"
        python main.py --lowvram --fp8_e4m3fn-unet --cpu-vae --listen 0.0.0.0 --port 3000
        ;;
    2)
        echo ""
        echo "Starting ComfyUI in HIGH GPU mode..."
        echo "Flags: --highvram --preview-method auto --listen 0.0.0.0 --port 3000"
        python main.py --highvram --preview-method auto --listen 0.0.0.0 --port 3000
        ;;
    *)
        echo ""
        echo "Error: Invalid selection. Please choose 1 or 2."
        exit 1
        ;;
esac

