#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODELS_DIR="$SCRIPT_DIR/ComfyUI/models"

if [ ! -d "$MODELS_DIR" ]; then
    echo "Error: Models directory not found at $MODELS_DIR"
    exit 1
fi

# Count model files (exclude placeholders, configs, and yaml files)
MODEL_COUNT=$(find "$MODELS_DIR" -type f \
    ! -name "put_*" \
    ! -name ".gitkeep" \
    ! -name "*.yaml" \
    ! -name "*.txt" \
    -not -path "*/configs/*" | wc -l)

if [ "$MODEL_COUNT" -eq 0 ]; then
    echo "No model files found. Nothing to delete."
    exit 0
fi

# Show disk usage
TOTAL_SIZE=$(find "$MODELS_DIR" -type f \
    ! -name "put_*" \
    ! -name ".gitkeep" \
    ! -name "*.yaml" \
    ! -name "*.txt" \
    -not -path "*/configs/*" \
    -exec du -ch {} + 2>/dev/null | tail -1 | cut -f1)

echo ""
echo "==================================="
echo "  ComfyUI - Delete ALL Models"
echo "==================================="
echo ""
echo "Found $MODEL_COUNT model file(s) using $TOTAL_SIZE"
echo ""

# List files per folder
for dir in "$MODELS_DIR"/*/; do
    [ -d "$dir" ] || continue
    dirname="$(basename "$dir")"
    [ "$dirname" = "configs" ] && continue

    count=$(find "$dir" -type f \
        ! -name "put_*" \
        ! -name ".gitkeep" \
        ! -name "*.yaml" \
        ! -name "*.txt" | wc -l)

    if [ "$count" -gt 0 ]; then
        size=$(find "$dir" -type f \
            ! -name "put_*" \
            ! -name ".gitkeep" \
            ! -name "*.yaml" \
            ! -name "*.txt" \
            -exec du -ch {} + 2>/dev/null | tail -1 | cut -f1)
        echo "  $dirname: $count file(s) ($size)"
    fi
done

echo ""
echo -n "Delete ALL model files? (y/N): "
read -r confirm

if [[ "$confirm" =~ ^[Yy]$ ]]; then
    find "$MODELS_DIR" -type f \
        ! -name "put_*" \
        ! -name ".gitkeep" \
        ! -name "*.yaml" \
        ! -name "*.txt" \
        -not -path "*/configs/*" \
        -delete

    echo ""
    echo "All model files deleted."
else
    echo "Cancelled."
fi
