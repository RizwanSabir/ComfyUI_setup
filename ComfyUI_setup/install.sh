#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# 1. Clone ComfyUI if not already present
if [ -d "ComfyUI" ]; then
    echo "ComfyUI directory already exists, skipping clone."
else
    echo "Cloning ComfyUI..."
    git clone https://github.com/comfyanonymous/ComfyUI.git
fi

# 2. Install PyTorch with NVIDIA CUDA support
echo "Installing PyTorch with CUDA support..."
pip install --pre torch torchvision torchaudio --index-url https://download.pytorch.org/whl/nightly/cu130

# 3. Install ComfyUI requirements
echo "Installing ComfyUI requirements..."
pip install -r ComfyUI/requirements.txt

# 4 & 5. Clone custom nodes in parallel
CUSTOM_NODES_FILE="$SCRIPT_DIR/custom_nodes.txt"
CUSTOM_NODES_DIR="$SCRIPT_DIR/ComfyUI/custom_nodes"

if [ -f "$CUSTOM_NODES_FILE" ]; then
    echo "Cloning custom nodes in parallel..."
    while IFS= read -r line || [ -n "$line" ]; do
        # Skip empty lines and comments
        line="$(echo "$line" | xargs)"
        [ -z "$line" ] && continue
        [[ "$line" == \#* ]] && continue

        # Derive folder name from URL
        node_name="$(basename "$line" .git)"
        node_dir="$CUSTOM_NODES_DIR/$node_name"

        if [ -d "$node_dir" ]; then
            echo "Custom node '$node_name' already exists, skipping."
        else
            echo "Cloning custom node: $node_name"
            git clone "$line" "$node_dir" &
        fi
    done < "$CUSTOM_NODES_FILE"
    wait
    echo "All custom node clones finished."
else
    echo "No custom_nodes.txt found, skipping custom nodes."
fi

# 6. Install requirements for each custom node
echo "Installing custom node requirements..."
for node_dir in "$CUSTOM_NODES_DIR"/*/; do
    [ -d "$node_dir" ] || continue
    if [ -f "$node_dir/requirements.txt" ]; then
        node_name="$(basename "$node_dir")"
        echo "Installing requirements for $node_name..."
        pip install -r "$node_dir/requirements.txt"
    fi
done

# 7. Make run scripts executable
chmod +x "$SCRIPT_DIR/cpu_run.sh" "$SCRIPT_DIR/gpu_run.sh" "$SCRIPT_DIR/models_delete_all.sh" "$SCRIPT_DIR/models_delete_some.sh"

# 8. Completion message
echo ""
echo "========================================="
echo "  Installation complete!"
echo "========================================="
echo ""
echo "To run ComfyUI, use one of the following:"
echo "  ./cpu_run.sh    (CPU mode)"
echo "  ./gpu_run.sh    (GPU mode with CUDA)"
echo ""
