# How to Setup ComfyUI + Comfy-Pilot + Agent Browser

Complete guide to setting up ComfyUI with AI-powered workflow editing (Comfy-Pilot) and headless browser automation (agent-browser) from scratch.

---

## Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| **Python** | 3.12+ | Via Conda |
| **Conda** (Miniconda) | 25+ | `https://docs.conda.io/en/latest/miniconda.html` |
| **Node.js** | 22+ | `https://nodejs.org/` |
| **npm** | 11+ | Comes with Node.js |
| **Git** | any | `sudo apt install git` |
| **Claude Code CLI** | latest | `curl -fsSL https://claude.ai/install.sh \| bash` |

Verify everything is installed:

```bash
python3 --version
conda --version
node --version
npm --version
git --version
which claude
```

---

## Project Structure

After setup, your project will look like this:

```
ComfyUI_Image_Playground/
├── ComfyUI_setup/
│   ├── ComfyUI/                  # Cloned ComfyUI repo
│   │   ├── custom_nodes/
│   │   │   ├── Comfy-Pilot/      # Symlinked from project root
│   │   │   ├── ComfyUI-Manager/
│   │   │   ├── ComfyUI-Crystools/
│   │   │   ├── ComfyUI-Easy-Use/
│   │   │   ├── ComfyUI-iTools/
│   │   │   ├── ComfyUI-Studio-nodes/
│   │   │   ├── was-node-suite-comfyui/
│   │   │   └── rgthree-comfy/
│   │   ├── input/                # Place images here
│   │   ├── output/               # Generated images saved here
│   │   └── main.py
│   ├── install.sh
│   ├── cpu_run.sh
│   ├── gpu_run.sh
│   └── custom_nodes.txt
├── Comfy-Pilot/                  # Cloned Comfy-Pilot repo
├── agent-browser.json
├── package.json
└── node_modules/
```

---

## Step 1: Create the Project Directory

```bash
mkdir -p ~/Desktop/Comfy_Play_testing/ComfyUI_Image_Playground
cd ~/Desktop/Comfy_Play_testing/ComfyUI_Image_Playground
```

---

## Step 2: Setup Conda Environment

Create a dedicated Python environment for ComfyUI:

```bash
conda create -n comfy python=3.12 -y
conda activate comfy
```

> Always activate the `comfy` env before running install or start scripts.

---

## Step 3: Install ComfyUI

The `ComfyUI_setup/` directory contains all the scripts needed. If starting fresh, create it:

```bash
mkdir -p ComfyUI_setup
cd ComfyUI_setup
```

### 3a. Create `custom_nodes.txt`

This file lists custom node repos to install (one URL per line):

```
https://github.com/ltdrdata/ComfyUI-Manager.git
https://github.com/crystian/ComfyUI-Crystools
https://github.com/yolain/ComfyUI-Easy-Use
https://github.com/MohammadAboulEla/ComfyUI-iTools
https://github.com/comfyuistudio/ComfyUI-Studio-nodes
https://github.com/WASasquatch/was-node-suite-comfyui
https://github.com/rgthree/rgthree-comfy
```

### 3b. Create `install.sh`

```bash
#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# 1. Clone ComfyUI
if [ -d "ComfyUI" ]; then
    echo "ComfyUI directory already exists, skipping clone."
else
    echo "Cloning ComfyUI..."
    git clone https://github.com/comfyanonymous/ComfyUI.git
fi

# 2. Install PyTorch with CUDA support
echo "Installing PyTorch with CUDA support..."
pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu124

# 3. Install ComfyUI requirements
echo "Installing ComfyUI requirements..."
pip install -r ComfyUI/requirements.txt

# 4. Clone custom nodes in parallel
CUSTOM_NODES_FILE="$SCRIPT_DIR/custom_nodes.txt"
CUSTOM_NODES_DIR="$SCRIPT_DIR/ComfyUI/custom_nodes"

if [ -f "$CUSTOM_NODES_FILE" ]; then
    echo "Cloning custom nodes in parallel..."
    while IFS= read -r line || [ -n "$line" ]; do
        line="$(echo "$line" | xargs)"
        [ -z "$line" ] && continue
        [[ "$line" == \#* ]] && continue
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
fi

# 5. Install requirements for each custom node
echo "Installing custom node requirements..."
for node_dir in "$CUSTOM_NODES_DIR"/*/; do
    [ -d "$node_dir" ] || continue
    if [ -f "$node_dir/requirements.txt" ]; then
        node_name="$(basename "$node_dir")"
        echo "Installing requirements for $node_name..."
        pip install -r "$node_dir/requirements.txt"
    fi
done

echo ""
echo "========================================="
echo "  Installation complete!"
echo "========================================="
```

### 3c. Create `cpu_run.sh`

```bash
#!/bin/bash

PORT=3000

echo "Checking port $PORT..."
PID=$(ss -tlnp 2>/dev/null | grep :$PORT | grep -oP 'pid=\K[0-9]+' | head -1)

if [ -n "$PID" ]; then
    echo "Port in use by PID: $PID — killing..."
    kill -9 $PID
    while ss -tlnp 2>/dev/null | grep -q :$PORT; do sleep 1; done
    echo "Port released."
else
    echo "Port is already free."
fi

cd ComfyUI || { echo "ComfyUI folder not found"; exit 1; }
echo "Starting ComfyUI (CPU mode)..."
python main.py --cpu --listen 0.0.0.0 --port 3000
```

### 3d. Run the installer

```bash
conda activate comfy
chmod +x install.sh cpu_run.sh
bash install.sh
```

This clones ComfyUI, installs PyTorch + all dependencies, clones custom nodes, and installs their requirements. Takes 5-15 minutes depending on internet speed.

---

## Step 4: Clone and Setup Comfy-Pilot

Go back to the project root and clone Comfy-Pilot:

```bash
cd ~/Desktop/Comfy_Play_testing/ComfyUI_Image_Playground

# Clone Comfy-Pilot
git clone https://github.com/ConstantineB6/Comfy-Pilot.git

# Symlink it into ComfyUI's custom_nodes
ln -sf "$(pwd)/Comfy-Pilot" ComfyUI_setup/ComfyUI/custom_nodes/Comfy-Pilot
```

Comfy-Pilot has **zero dependencies** — no pip install needed. It uses Python stdlib + aiohttp bundled with ComfyUI.

### What Comfy-Pilot provides:

- **MCP Server** (`mcp_server.py`) — 15 tools for Claude to read/edit/run workflows
- **Embedded Terminal** — xterm.js terminal running Claude Code inside ComfyUI
- **Graph Command System** — REST API to create/connect/move nodes on the visual canvas

---

## Step 5: Register the MCP Server with Claude Code

This lets Claude Code use Comfy-Pilot's 15 tools:

```bash
claude mcp add comfyui python3 "$(pwd)/Comfy-Pilot/mcp_server.py"
```

Verify it was registered:

```bash
claude mcp get comfyui
```

You should see `Status: Connected` and the command pointing to `mcp_server.py`.

---

## Step 6: Start ComfyUI

```bash
cd ComfyUI_setup
conda activate comfy
bash cpu_run.sh
```

Or run it in the background:

```bash
conda run -n comfy bash -c "cd ComfyUI && python main.py --cpu --listen 0.0.0.0 --port 3000" &
```

Wait for it to start (usually 15-30 seconds):

```bash
# Poll until ready
for i in $(seq 1 30); do
    curl -s http://localhost:3000 >/dev/null 2>&1 && echo "ComfyUI is UP!" && break
    sleep 2
done
```

### Verify Comfy-Pilot is loaded:

```bash
curl -s http://localhost:3000/claude-code/mcp-status
```

Expected response:
```json
{"connected": true, "tools": 15, "platform": "unix", "terminal_supported": true}
```

---

## Step 7: Install and Setup Agent Browser

Agent-browser is a headless/GUI browser automation CLI for AI agents.

```bash
cd ~/Desktop/Comfy_Play_testing/ComfyUI_Image_Playground

# Install the package
npm install agent-browser

# Install Chromium
npx agent-browser install
```

On Linux, if you get sandbox errors, you may need system deps:

```bash
sudo npx agent-browser install --with-deps
```

### Create config file

Create `agent-browser.json` in the project root:

```json
{
  "headed": true
}
```

This makes the browser window visible by default.

### Open ComfyUI in agent-browser

```bash
npx agent-browser --headed --args "--no-sandbox" open http://localhost:3000
```

> The `--no-sandbox` flag is needed on most Linux setups (VMs, containers, remote desktops).

### Verify it's working

```bash
# Take a screenshot
npx agent-browser screenshot /tmp/comfy_test.png

# Get the accessibility tree (shows clickable elements)
npx agent-browser snapshot

# Close when done
npx agent-browser close
```

---

## Step 8: Create a Workflow (LoadImage + PreviewImage)

With ComfyUI running and agent-browser open, you can create workflows using the Comfy-Pilot graph command API.

### 8a. Add a test image

Copy an image to ComfyUI's input folder:

```bash
cp /path/to/your/image.jpg ComfyUI_setup/ComfyUI/input/A.jpg
```

### 8b. Create nodes on the canvas

```bash
# Create LoadImage node
curl -s -X POST http://localhost:3000/claude-code/graph-command \
  -H "Content-Type: application/json" \
  -d '{"action": "create_node", "params": {"type": "LoadImage", "pos_x": 200, "pos_y": 300, "title": "Load Image"}}'

# Create PreviewImage node
curl -s -X POST http://localhost:3000/claude-code/graph-command \
  -H "Content-Type: application/json" \
  -d '{"action": "create_node", "params": {"type": "PreviewImage", "pos_x": 600, "pos_y": 200, "title": "Preview Image"}}'

# Create SaveImage node
curl -s -X POST http://localhost:3000/claude-code/graph-command \
  -H "Content-Type: application/json" \
  -d '{"action": "create_node", "params": {"type": "SaveImage", "pos_x": 600, "pos_y": 400, "title": "Save Image"}}'
```

### 8c. Set the image and connect nodes

```bash
# Set image on LoadImage node (node_id from create response)
curl -s -X POST http://localhost:3000/claude-code/graph-command \
  -H "Content-Type: application/json" \
  -d '{"action": "set_node_property", "params": {"node_id": 1, "property_name": "image", "value": "A.jpg"}}'

# Connect LoadImage (output 0: IMAGE) → PreviewImage (input 0)
curl -s -X POST http://localhost:3000/claude-code/graph-command \
  -H "Content-Type: application/json" \
  -d '{"action": "connect_nodes", "params": {"from_node_id": 1, "from_slot": 0, "to_node_id": 2, "to_slot": 0}}'

# Connect LoadImage (output 0: IMAGE) → SaveImage (input 0)
curl -s -X POST http://localhost:3000/claude-code/graph-command \
  -H "Content-Type: application/json" \
  -d '{"action": "connect_nodes", "params": {"from_node_id": 1, "from_slot": 0, "to_node_id": 3, "to_slot": 0}}'
```

### 8d. Run the workflow

```bash
curl -s -X POST http://localhost:3000/claude-code/graph-command \
  -H "Content-Type: application/json" \
  -d '{"action": "queue_prompt", "params": {}}'
```

### 8e. Verify the output

```bash
# Check output folder
ls ComfyUI_setup/ComfyUI/output/

# Take a screenshot to see the visual result
npx agent-browser screenshot /tmp/comfy_result.png
```

The saved image will be in `ComfyUI_setup/ComfyUI/output/ComfyUI_00001_.png`.

---

## Alternative: Use the ComfyUI API Directly

You can also queue workflows without the visual canvas using ComfyUI's `/prompt` API:

```bash
curl -s -X POST http://localhost:3000/prompt \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": {
      "1": {
        "class_type": "LoadImage",
        "inputs": { "image": "A.jpg" }
      },
      "2": {
        "class_type": "PreviewImage",
        "inputs": { "images": ["1", 0] }
      },
      "3": {
        "class_type": "SaveImage",
        "inputs": { "images": ["1", 0], "filename_prefix": "ComfyUI_Preview" }
      }
    }
  }'
```

This runs server-side without needing the browser open, but nodes won't appear on the canvas.

---

## Agent Browser Quick Reference

| Command | Description |
|---------|-------------|
| `npx agent-browser --headed --args "--no-sandbox" open <url>` | Open URL in visible browser |
| `npx agent-browser screenshot /tmp/page.png` | Take screenshot |
| `npx agent-browser snapshot` | Get accessibility tree (shows `@ref` IDs) |
| `npx agent-browser click @e2` | Click element by ref |
| `npx agent-browser fill @e3 "text"` | Fill input field |
| `npx agent-browser scroll down 500` | Scroll down 500px |
| `npx agent-browser close` | Close browser session |

**Workflow pattern:** Open → Snapshot → Screenshot → Interact → Snapshot again → Close

> Refs like `@e2` change after every page navigation or DOM update. Always take a fresh `snapshot` before interacting.

---

## Comfy-Pilot Graph Command Reference

All commands are sent via POST to `http://localhost:3000/claude-code/graph-command`.

| Action | Parameters | Description |
|--------|-----------|-------------|
| `create_node` | `type`, `pos_x`, `pos_y`, `title` | Create a node on the canvas |
| `delete_node` | `node_id` | Remove a node |
| `set_node_property` | `node_id`, `property_name`, `value` | Set a widget value |
| `connect_nodes` | `from_node_id`, `from_slot`, `to_node_id`, `to_slot` | Connect two nodes |
| `disconnect_nodes` | `from_node_id`, `from_slot`, `to_node_id`, `to_slot` | Remove a connection |
| `move_node` | `node_id`, `x`, `y` | Move a node |
| `queue_prompt` | (none) | Run the workflow |
| `get_workflow_api` | (none) | Get workflow as JSON |

---

## Comfy-Pilot MCP Tools (via Claude Code)

When using Claude Code with the MCP server registered, Claude has access to these 15 tools:

| Tool | Description |
|------|-------------|
| `get_workflow` | Get full workflow graph |
| `summarize_workflow` | Human-readable workflow summary |
| `get_node_types` | Search available node types |
| `get_node_info` | Detailed info about a specific node |
| `get_status` | Queue status, system stats, history |
| `run` | Execute or interrupt workflow |
| `edit_graph` | Batch create/delete/move/connect nodes |
| `view_image` | View output images from Preview/Save nodes |
| `center_on_node` | Center viewport on a node |
| `search_custom_nodes` | Search ComfyUI Manager registry |
| `install_custom_node` | Install a custom node |
| `uninstall_custom_node` | Remove a custom node |
| `update_custom_node` | Update a custom node |
| `download_model` | Download models from HuggingFace/CivitAI |

---

## Troubleshooting

### Port 3000 already in use

```bash
# Find and kill the process
ss -tlnp | grep :3000
kill -9 <PID>
```

### Agent-browser sandbox error on Linux

```bash
# Use --no-sandbox flag
npx agent-browser --headed --args "--no-sandbox" open http://localhost:3000

# Or install system dependencies
sudo npx agent-browser install --with-deps
```

### Comfy-Pilot MCP not connecting (red dot)

```bash
# Check if registered
claude mcp get comfyui

# Re-register if needed
claude mcp add comfyui python3 /full/path/to/Comfy-Pilot/mcp_server.py
```

### Graph commands timeout (5s)

The browser **must be open** with ComfyUI loaded. The frontend JS polls for commands every 200ms. Without the browser, commands queue but never execute.

### "Invalid image file" error

The image must be in the **running ComfyUI instance's** `input/` folder. Check:

```bash
ls ComfyUI_setup/ComfyUI/input/
```

### Claude Code CLI not found

```bash
curl -fsSL https://claude.ai/install.sh | bash
```

---

## Quick Start (Copy-Paste)

Run all of these in order to go from zero to a working workflow:

```bash
# 1. Go to project directory
cd ~/Desktop/Comfy_Play_testing/ComfyUI_Image_Playground

# 2. Activate conda env
conda activate comfy

# 3. Install ComfyUI (first time only)
cd ComfyUI_setup && bash install.sh && cd ..

# 4. Clone Comfy-Pilot (first time only)
git clone https://github.com/ConstantineB6/Comfy-Pilot.git
ln -sf "$(pwd)/Comfy-Pilot" ComfyUI_setup/ComfyUI/custom_nodes/Comfy-Pilot

# 5. Register MCP server (first time only)
claude mcp add comfyui python3 "$(pwd)/Comfy-Pilot/mcp_server.py"

# 6. Install agent-browser (first time only)
npm install agent-browser
npx agent-browser install

# 7. Start ComfyUI in background
conda run -n comfy bash -c "cd ComfyUI_setup/ComfyUI && python main.py --cpu --listen 0.0.0.0 --port 3000" &

# 8. Wait for startup
sleep 20

# 9. Open in agent-browser
npx agent-browser --headed --args "--no-sandbox" open http://localhost:3000

# 10. Verify Comfy-Pilot is loaded
curl -s http://localhost:3000/claude-code/mcp-status
```
