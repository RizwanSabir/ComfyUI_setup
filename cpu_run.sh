#!/bin/bash

PORT=3000

echo "Checking port $PORT..."

PID=$(ss -tlnp 2>/dev/null | grep :$PORT | grep -oP 'pid=\K[0-9]+' | head -1)

if [ -n "$PID" ]; then
    echo "Port in use by PID: $PID"
    echo "Killing process..."

    kill -9 $PID

    # Wait until port is free
    while ss -tlnp 2>/dev/null | grep -q :$PORT; do
        echo "Waiting for port to free..."
        sleep 1
    done

    echo "Port released."
else
    echo "Port is already free."
fi

# Move to ComfyUI
cd ComfyUI || { echo "ComfyUI folder not found"; exit 1; }

echo "Starting ComfyUI..."
python main.py --cpu --listen 0.0.0.0 --port 3000

