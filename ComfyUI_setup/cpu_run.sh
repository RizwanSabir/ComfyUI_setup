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

# Move to ComfyUI
cd ComfyUI || { echo "ComfyUI folder not found"; exit 1; }

echo "Starting ComfyUI..."
python main.py --cpu --listen 0.0.0.0 --port 3000
