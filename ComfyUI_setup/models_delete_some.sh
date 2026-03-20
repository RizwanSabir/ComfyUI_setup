#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODELS_DIR="$SCRIPT_DIR/ComfyUI/models"

if [ ! -d "$MODELS_DIR" ]; then
    echo "Error: Models directory not found at $MODELS_DIR"
    exit 1
fi

echo ""
echo "==================================="
echo "  ComfyUI - Delete Select Models"
echo "==================================="
echo ""

# Build list of folders that have model files
FOLDERS=()
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
        FOLDERS+=("$dirname")
        echo "  ${#FOLDERS[@]}. $dirname — $count file(s) ($size)"
    fi
done

if [ ${#FOLDERS[@]} -eq 0 ]; then
    echo "No model files found. Nothing to delete."
    exit 0
fi

echo ""
echo "Enter numbers to delete (e.g. 1 3 5 or 1,3,5):"
echo -n "> "
read -r selection

# Parse selection (support spaces, commas, or both)
SELECTED=$(echo "$selection" | tr ',' ' ')

DELETED=0
for num in $SELECTED; do
    # Validate number
    if ! [[ "$num" =~ ^[0-9]+$ ]] || [ "$num" -lt 1 ] || [ "$num" -gt ${#FOLDERS[@]} ]; then
        echo "Skipping invalid selection: $num"
        continue
    fi

    folder="${FOLDERS[$((num-1))]}"
    folder_path="$MODELS_DIR/$folder"

    count=$(find "$folder_path" -type f \
        ! -name "put_*" \
        ! -name ".gitkeep" \
        ! -name "*.yaml" \
        ! -name "*.txt" | wc -l)

    find "$folder_path" -type f \
        ! -name "put_*" \
        ! -name ".gitkeep" \
        ! -name "*.yaml" \
        ! -name "*.txt" \
        -delete

    echo "Deleted $count file(s) from $folder"
    DELETED=$((DELETED + count))
done

echo ""
if [ "$DELETED" -gt 0 ]; then
    echo "Done. Deleted $DELETED file(s) total."
else
    echo "No files deleted."
fi
