# Comfy-Pilot: Complete Documentation

## What is Comfy-Pilot?

Comfy-Pilot is a ComfyUI custom node plugin (v1.0.24) that integrates Claude Code directly into the ComfyUI workflow editor. It provides:

1. **An MCP (Model Context Protocol) server** — exposes 15 tools that let Claude read, edit, and execute ComfyUI workflows programmatically
2. **An embedded terminal** — an xterm.js terminal running Claude Code CLI directly inside the ComfyUI browser interface
3. **Graph command system** — a REST + polling bridge that lets the MCP server manipulate the visual node graph through the frontend's LiteGraph API

**In plain terms:** Instead of manually dragging nodes, connecting wires, and tweaking values in ComfyUI, you can tell Claude what you want in natural language and it builds/modifies the workflow for you.

- **Author:** ConstantineB6 (publisher: constantine)
- **License:** MIT
- **Registry:** `comfy.org/publishers/constantine/nodes/comfy-pilot`
- **Repository:** `https://github.com/ConstantineB6/Comfy-Pilot`
- **Dependencies:** Zero runtime dependencies (uses Python stdlib + aiohttp bundled with ComfyUI)
- **Platform:** Linux/macOS (full terminal support), Windows (limited — no PTY terminal)

---

## Understanding the 4 Pieces (and Why Each One Exists)

Comfy-Pilot has 4 pieces that work together. Think of it like a restaurant:

- **You** = the customer (you type in natural language)
- **Claude Code** = the waiter (understands what you want)
- **MCP Server** = the kitchen (knows the recipes — how to create nodes, connect them, etc.)
- **Backend** = the service counter (passes orders between kitchen and dining room)
- **Frontend** = the dining room (where the food is actually served — the visual canvas)

If ANY piece is missing, the whole thing breaks. Here's each one explained:

---

### Piece 1: The FRONTEND (`js/claude-code.js`) — The Visual Canvas in Your Browser

**What is it?**
This is the JavaScript code that runs inside your web browser when you open `http://localhost:3000`. It has two jobs:
1. Show the xterm.js terminal where you talk to Claude
2. Execute graph commands (create nodes, connect wires, etc.) on the visual canvas

**Why is it there?**
ComfyUI's node editor uses a JavaScript library called LiteGraph. The ONLY way to create/move/connect nodes on the canvas is through LiteGraph's JavaScript API — which runs in the browser. There is no way to do this from the server side. The nodes, wires, and canvas are all browser-side objects.

**What happens if the frontend is NOT there (browser closed)?**
- You can still start ComfyUI on the server
- The MCP server can still send commands
- BUT the commands will **queue up and never execute**. They will timeout after 5 seconds with: `{"error": "Timeout waiting for frontend to execute command"}`
- This is exactly what happened in our testing — when the browser crashed, graph commands failed

**How does it help?**
Every 200 milliseconds (5 times per second), the frontend asks the backend: "Do you have any commands for me?" If yes, it:
1. Takes the command (e.g., `create_node`)
2. Executes it using LiteGraph (`LiteGraph.createNode("LoadImage")`)
3. Sends the result back to the backend

It also syncs the current workflow to the backend every 2 seconds, so the MCP server always knows what's on the canvas.

**Think of it as:** The hands that physically move the nodes on the screen. Without hands, nothing moves.

---

### Piece 2: The BACKEND (`__init__.py`) — The Middleman Inside ComfyUI Server

**What is it?**
This is Python code that runs inside the ComfyUI server process. When ComfyUI starts and loads `custom_nodes/Comfy-Pilot/`, this file executes. It adds 8 new URL routes (endpoints) to ComfyUI's web server.

**Why is it there?**
The MCP server (piece 3) and the Frontend (piece 1) cannot talk to each other directly. The MCP server is a separate process that only speaks stdin/stdout. The frontend is JavaScript in a browser. They need a middleman — something both can reach via HTTP. That's the backend.

The backend is like a **message board**:
- The MCP server **posts a command** on the board (via HTTP POST)
- The frontend **reads the command** from the board (via HTTP GET, every 200ms)
- The frontend **posts the result** back on the board (via HTTP POST)
- The backend **returns the result** to whoever originally posted the command

**What happens if the backend is NOT there?**
- ComfyUI starts, but without the `/claude-code/*` endpoints
- The MCP server has nowhere to send commands → all tools fail
- The frontend has nowhere to poll for commands → no AI-driven editing
- The terminal WebSocket doesn't exist → no embedded Claude Code terminal
- Basically: Comfy-Pilot doesn't exist. ComfyUI works normally, but without any Claude integration.

**How does it help?**
It provides:
1. **Command queue** (`pending_commands`) — stores commands from MCP server until frontend picks them up
2. **Result storage** (`command_results`) — stores results from frontend until MCP server reads them
3. **Workflow cache** (`current_workflow`) — stores the latest canvas state so the MCP server can read it
4. **Terminal WebSocket** (`/ws/claude-terminal`) — spawns a PTY process running Claude Code CLI and bridges it to the browser terminal
5. **Auto-setup** — writes `.comfyui_url` file and runs `claude mcp add` to register the MCP server

**Think of it as:** The post office. Everyone sends their messages through it. Without the post office, nobody can communicate.

---

### Piece 3: The MCP SERVER (`mcp_server.py`) — Claude's Toolbox

**What is it?**
A standalone Python script that runs as a separate process. It speaks the MCP protocol (JSON-RPC 2.0 over stdin/stdout) and exposes 15 tools that Claude can use.

**Why is it there?**
Claude Code is an AI — it's smart, but it doesn't know how to operate ComfyUI by itself. It doesn't know what node types exist, how to create them, or how to connect them. The MCP server gives Claude **hands inside ComfyUI**.

Without the MCP server, Claude would be like a person sitting in front of ComfyUI who is blindfolded and has no hands. It can think and talk, but can't see or touch anything.

The MCP server translates Claude's high-level intentions into concrete ComfyUI operations:
- Claude says "create a LoadImage node" → MCP server validates the node type exists, sends `create_node` command to the backend
- Claude says "what's in my workflow?" → MCP server fetches the workflow from the backend, formats it as readable text
- Claude says "run it" → MCP server tells the frontend to queue the prompt

**What happens if the MCP server is NOT there?**
- The embedded terminal still works — Claude Code CLI runs, you can talk to it
- BUT Claude has **no ComfyUI tools**. It can't see your workflow, can't create nodes, can't run anything
- Claude becomes a general-purpose AI that happens to be running inside ComfyUI, but can't interact with it
- You could still ask Claude general questions, write code, etc. — but nothing ComfyUI-specific
- The MCP status dot in the UI turns **red** instead of green

**How does it help?**
It provides 15 tools organized into 4 categories:
1. **Reading** — `get_workflow`, `summarize_workflow`, `get_node_types`, `get_node_info`, `get_status`, `view_image`
2. **Editing** — `edit_graph`, `center_on_node`
3. **Executing** — `run`
4. **Managing** — `search_custom_nodes`, `install_custom_node`, `uninstall_custom_node`, `update_custom_node`, `download_model`

Each tool makes HTTP requests to either:
- ComfyUI's native API (`/object_info`, `/queue`, `/history`, `/view`) for reading data
- Comfy-Pilot's backend (`/claude-code/graph-command`, `/claude-code/workflow`) for editing/executing

**Think of it as:** Claude's hands and eyes inside ComfyUI. Without it, Claude is blind and can't touch anything.

---

### Piece 4: CLAUDE CODE CLI — The Brain

**What is it?**
The Claude Code command-line tool (`claude`). It's Anthropic's official AI assistant that runs in your terminal. In Comfy-Pilot, it runs inside an embedded xterm.js terminal in the browser.

**Why is it there?**
This is the AI brain that:
- **Understands your natural language** ("build me a workflow that upscales an image")
- **Decides which tools to use** (first search for node types, then create nodes, then connect them)
- **Calls the MCP tools** in the right order with the right parameters
- **Handles errors** (if a node type doesn't exist, it searches for alternatives)
- **Shows you results** (fetches the output image and displays it)

**What happens if Claude Code is NOT there?**
- The terminal in the browser is empty or shows an error
- No AI assistant — you have to use ComfyUI manually (drag nodes, connect wires by hand)
- The MCP server exists but nobody calls it. It's like having a kitchen with no waiter — the recipes are there but nobody orders.
- You could still call the graph commands yourself via `curl`, but you'd need to know every node type, every slot number, every parameter — which defeats the purpose

**How does it help?**
It's the intelligence layer. You say what you want in English, and Claude:
1. Figures out which ComfyUI nodes you need
2. Creates them in the right positions
3. Sets their properties correctly
4. Connects them in the right order
5. Runs the workflow
6. Shows you the result

All by calling the MCP server's tools behind the scenes.

**Think of it as:** The chef who reads your order, knows the recipes, and tells the kitchen what to cook. Without the chef, the kitchen equipment sits unused.

---

## How All 4 Pieces Work Together — A Real Example

You type in the terminal: **"Load the image A.jpg and preview it"**

Here's what happens, step by step, through all 4 pieces:

```
STEP 1: YOU → CLAUDE CODE (the brain thinks)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
You type "Load the image A.jpg and preview it" in the browser terminal.
Claude Code receives your message and thinks:
  "I need to: find the right node types, create them, set the image, connect them, run it."

STEP 2: CLAUDE CODE → MCP SERVER (the brain asks for information)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Claude calls the MCP tool: get_node_types(search="LoadImage")
The MCP server receives this via stdin (JSON-RPC).
The MCP server makes HTTP request: GET http://localhost:3000/object_info/LoadImage
ComfyUI responds with the node definition.
The MCP server returns this to Claude via stdout.
Claude now knows: "LoadImage exists, it has an IMAGE output on slot 0."

STEP 3: CLAUDE CODE → MCP SERVER → BACKEND (the brain sends an order)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Claude calls the MCP tool: edit_graph(operations=[create LoadImage, create PreviewImage, ...])
The MCP server decomposes this into individual commands.
First command: POST http://localhost:3000/claude-code/graph-command
  Body: {"action": "create_node", "params": {"type": "LoadImage", "pos_x": 200, "pos_y": 200}}
The BACKEND receives this POST.
The BACKEND puts it in the pending_commands queue.
The BACKEND starts waiting for a result (up to 5 seconds).

STEP 4: BACKEND → FRONTEND (the message board is checked)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
The FRONTEND (browser JavaScript) has been polling GET /claude-code/graph-command every 200ms.
This time, it gets back: {"command": {"id": "abc-123", "action": "create_node", "params": {...}}}
The FRONTEND says: "I have a command to execute!"

STEP 5: FRONTEND (the visual canvas does the work)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
The FRONTEND runs: LiteGraph.createNode("LoadImage")
A new LoadImage node appears on the canvas at position (200, 200).
The node gets assigned ID 10.
The FRONTEND sends the result back:
  POST /claude-code/graph-command
  Body: {"command_id": "abc-123", "result": {"status": "created", "node_id": 10}}

STEP 6: FRONTEND → BACKEND → MCP SERVER → CLAUDE CODE (result flows back)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
The BACKEND picks up the result from command_results.
The BACKEND returns it to the MCP server's original POST request.
The MCP server formats it and sends it to Claude via stdout.
Claude sees: "LoadImage node created with ID 10."

STEP 7: REPEAT for each operation
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Steps 3-6 repeat for:
  - Create PreviewImage → node ID 11
  - Set image property on node 10 → "A.jpg"
  - Connect node 10 slot 0 → node 11 slot 0
  - Queue prompt → workflow executes

STEP 8: THE RESULT
━━━━━━━━━━━━━━━━━━
ComfyUI loads A.jpg, passes it through, and the PreviewImage node
displays it on the canvas. Claude calls view_image() to see the
output and confirms to you: "Done! The image is loaded and previewed."
```

---

## What Breaks When Each Piece is Missing — Summary Table

| Missing Piece | What Happens | What Still Works |
|--------------|-------------|-----------------|
| **Frontend** (browser closed) | Graph commands timeout after 5s. Nodes can't be created/moved/connected. Workflows can't be queued from the frontend. | ComfyUI server runs. MCP server runs. You can submit workflows via the native `/prompt` API (bypassing Comfy-Pilot entirely). |
| **Backend** (Comfy-Pilot not installed) | No `/claude-code/*` endpoints exist. No terminal. No graph commands. No workflow sync. | ComfyUI works normally as a manual node editor. No AI integration. |
| **MCP Server** (mcp_server.py not running) | Claude has no tools. Can't see/edit/run workflows. MCP dot turns red. | Terminal still works (Claude Code runs). You can chat with Claude about general topics. Graph commands still work if you send them manually via curl. |
| **Claude Code** (CLI not installed) | Terminal is empty. No AI brain to understand your requests or call tools. | Backend and frontend still work. You can use ComfyUI manually. You can send graph commands via curl. The MCP server exists but nobody calls it. |

---

## Why Can't We Simplify This? Why 4 Pieces?

**"Why not just have Claude talk directly to ComfyUI?"**

Because ComfyUI's visual editor runs in the browser (JavaScript), but Claude runs on the server (Python). They're in different worlds. You NEED:
- Something in the **browser** to move nodes on the canvas (Frontend)
- Something in the **server** to receive messages from both sides (Backend)
- Something that **gives Claude tools** to work with (MCP Server)
- The **AI itself** to understand your words and decide what to do (Claude Code)

**"Why not just use the ComfyUI API directly?"**

ComfyUI does have a `/prompt` API where you can submit a workflow as JSON. But:
- You'd have to write the entire workflow JSON by hand (hundreds of lines)
- You can't see the nodes on the canvas (it runs server-side only)
- You can't create nodes one at a time interactively
- You can't see what you're building as you build it
- Comfy-Pilot gives you the best of both worlds: AI intelligence + visual feedback

**"Why does the frontend need to poll? Why not push?"**

The backend could push commands via WebSocket, but polling is simpler and more reliable. At 200ms intervals (5 times per second), it feels instant to the user. The trade-off (tiny bandwidth cost) is worth the simplicity.

---

## The Communication Map — Who Talks to Whom

```
YOU (typing in browser terminal)
  │
  │ keystrokes via WebSocket
  ▼
CLAUDE CODE CLI (running in PTY on the server)
  │
  │ MCP protocol (JSON-RPC via stdin/stdout)
  ▼
MCP SERVER (mcp_server.py, separate process)
  │
  │ HTTP requests (urllib)
  ▼
BACKEND (__init__.py, inside ComfyUI server)
  │
  │ HTTP polling (every 200ms)
  ▼
FRONTEND (claude-code.js, in your browser)
  │
  │ LiteGraph JavaScript API
  ▼
COMFYUI CANVAS (nodes appear, wires connect, images preview)
```

**The return path is the same in reverse:**
```
Canvas result → Frontend → Backend → MCP Server → Claude Code → You see the response in terminal
```

Every arrow is a potential failure point. That's why:
- Browser must be open (for the Frontend)
- ComfyUI must be running (for the Backend)
- Claude Code must be running (for the Brain)
- MCP server must be registered (for the Tools)

---

## The 15 MCP Tools

### Workflow Tools

#### 1. `get_workflow`
Get the full workflow node graph (all nodes, connections, properties).
- **Parameters:** none
- **Returns:** `{source, workflow, workflow_api, timestamp}`
- **Source:** Live from frontend via `/claude-code/workflow`, falls back to most recent `/history` entry

#### 2. `summarize_workflow`
Get a concise text summary of the workflow (lighter than full graph).
- **Parameters:** none
- **Returns:** TOON-format string with canvas bounds, node list (id, type, title, position, size), connections, collision detection

#### 3. `get_node_types`
Search available ComfyUI node types. Cached for 5 minutes.
- **Parameters (all optional):**
  - `search` — string or array of strings to match against node type names
  - `category` — filter by category substring
  - `fields` — array of: `"inputs"`, `"outputs"`, `"description"`, `"input_types"`, `"output_types"`
- **Returns:** Category summary (no filters) or matching nodes in TOON format

#### 4. `get_node_info`
Detailed info about a specific node currently in the workflow.
- **Parameters:** `node_id` (required)
- **Returns:** Type, position, size, category, description, all inputs (with required markers), outputs, connections, widget values

#### 5. `get_status`
Queue status, system stats, and execution history.
- **Parameters (all optional):**
  - `include` — array of: `"queue"`, `"system"`, `"history"` (default: queue + system)
  - `detail` — `"summary"` or `"full"`
  - `history_limit` — int, max 20
  - `history_offset` — int for pagination
- **Returns:** Running/pending queue counts, OS/Python/GPU VRAM info, paginated history entries

### Execution Tools

#### 6. `run`
Execute the workflow or interrupt a running execution.
- **Parameters (all optional):**
  - `action` — `"queue"` (default) or `"interrupt"`
  - `node_ids` — string or array; pre-flight validation that these nodes exist before queuing
- **How it works:** Fetches `workflow_api` from frontend via graph command, validates node IDs if given, then queues via `queue_prompt` graph command
- **Returns:** `{status: "queued", prompt_id}` or `{status: "interrupted"}`

### Graph Editing Tools

#### 7. `edit_graph`
The primary graph manipulation tool. Batch operations in a single call.
- **Parameters:** `operations` (required) — single object or array of operations
- **Supports `ref` chaining** — create a node with `ref: "mynode"`, then reference it by that ref in later operations

**Supported actions:**

| Action | Parameters | Description |
|--------|-----------|-------------|
| `create` | `node_type`, `pos_x`, `pos_y`, `title`, `ref`, `place_in_view` | Create a new node. Validates type against `/object_info`. |
| `delete` | `node_id` or `node_ids` (array) | Remove node(s) from the graph. |
| `move` | `node_id`, `x`/`y` (absolute) OR `relative_to`/`direction`/`gap` | Reposition a node. Directions: right, left, below, above. Default gap: 30px. |
| `resize` | `node_id`, `width`, `height` | Resize a node. |
| `set` | `node_id`, `property`/`value` OR `properties: {k:v}` | Set widget values or properties. |
| `connect` | `from_node`, `from_slot`, `to_node`, `to_slot` | Connect output slot to input slot (0-based). |
| `disconnect` | `from_node`, `from_slot`, `to_node`, `to_slot` | Remove a connection. |

**Example:**
```json
{
  "operations": [
    {"action": "create", "node_type": "LoadImage", "pos_x": 200, "pos_y": 200, "ref": "loader"},
    {"action": "create", "node_type": "PreviewImage", "pos_x": 600, "pos_y": 200, "ref": "preview"},
    {"action": "set", "node_id": "loader", "property": "image", "value": "photo.jpg"},
    {"action": "connect", "from_node": "loader", "from_slot": 0, "to_node": "preview", "to_slot": 0}
  ]
}
```

#### 8. `center_on_node`
Center the viewport on a specific node.
- **Parameters:** `node_id` (required)

#### 9. `view_image`
View output images from Preview/Save Image nodes.
- **Parameters (all optional):**
  - `node_id` — specific node to check (auto-finds preview nodes if omitted)
  - `image_index` — which image (default 0)
- **Returns:** Base64-encoded image data with media type (png/jpeg/webp)

### Custom Node Management Tools

#### 10. `search_custom_nodes`
Search the ComfyUI node registry or list installed nodes.
- **Parameters (all optional):**
  - `query` — search string
  - `status` — `"all"`, `"installed"`, `"not-installed"`
  - `category` — category filter
  - `limit` — max results (default 10)
- **Returns:** `{total_matches, nodes: [{id, name, author, description, repository, installed, stars, downloads}]}`

#### 11. `install_custom_node`
Install a custom node from the registry or a git URL.
- **Parameters:** `node_id` (required) — registry ID, name, or git URL
- **Method:** `git clone --depth 1`
- **Notes:** Reports if `requirements.txt` exists (needs manual install)

#### 12. `uninstall_custom_node`
Remove an installed custom node.
- **Parameters:** `node_id` (required) — exact or partial name match
- **Safety:** Validates path is inside `custom_nodes/` before deletion

#### 13. `update_custom_node`
Update an installed custom node via git pull.
- **Parameters:** `node_id` (required)
- **Method:** `git pull` in the node's directory

### Model Download Tool

#### 14. `download_model`
Download models from HuggingFace, CivitAI, or direct URLs.
- **Parameters:**
  - `url` (required) — HuggingFace URL/shorthand, CivitAI URL, or direct download URL
  - `model_type` (required) — one of 30+ types: `checkpoint`, `lora`, `vae`, `controlnet`, `clip`, `clip_vision`, `unet`, `diffusion_model`, `text_encoder`, `upscale_model`, `embeddings`, `hypernetwork`, `style_model`, `ipadapter`, `instantid`, `insightface`, `pulid`, `reactor`, `animatediff`, etc.
  - `filename` (optional) — custom filename
  - `hf_token` (optional) — for gated HuggingFace models
  - `subfolder` (optional) — subdirectory within the model type folder
- **Download methods:** `huggingface-cli` (HF), `wget`/`curl`/`urllib` (direct)
- **Timeout:** 30 minutes for direct downloads, 10 minutes for HuggingFace CLI

---

## REST API Endpoints

All endpoints are registered by `__init__.py` on ComfyUI's aiohttp server.

### Terminal

| Method | Path | Description |
|--------|------|-------------|
| WebSocket | `/ws/claude-terminal` | PTY terminal session. Spawns Claude Code CLI. Messages: `"i"` (input), `"resize"` (terminal resize). Output prefixed with `"o"`. |

### Workflow

| Method | Path | Description |
|--------|------|-------------|
| GET | `/claude-code/workflow` | Returns cached workflow JSON (`{workflow, workflow_api, timestamp}`) |
| POST | `/claude-code/workflow` | Frontend pushes updated workflow. Body: `{workflow, workflow_api, timestamp}` |

### Graph Commands

| Method | Path | Description |
|--------|------|-------------|
| GET | `/claude-code/graph-command` | Frontend polls for pending commands. Returns `{command: {id, action, params}}` or `{command: null}` |
| POST | `/claude-code/graph-command` | Two uses: (1) MCP server posts new command `{action, params}` — server queues it, waits up to 5s for frontend result. (2) Frontend posts result `{command_id, result}`. |

### Node Execution

| Method | Path | Description |
|--------|------|-------------|
| POST | `/claude-code/run-node` | Queue prompt for specific node. Body: `{node_id}`. Uses `PromptServer.instance.prompt_queue.put()`. |

### Status & Info

| Method | Path | Description |
|--------|------|-------------|
| GET | `/claude-code/mcp-status` | Returns `{connected, tools, platform, terminal_supported}`. Any response confirms plugin loaded. |
| GET | `/claude-code/memory` | Returns `{process_mb, plugin: {workflow_bytes, pending_commands_bytes, command_results_bytes, terminal_sessions, total_plugin_kb}}` |
| GET | `/claude-code/platform` | Returns `{platform, is_windows, terminal_supported, python_version, comfyui_url}` |

---

## The Graph Command Flow (In Detail)

This is the core mechanism that lets Claude edit ComfyUI workflows. It's a producer-consumer pattern bridging the MCP server (backend) to the LiteGraph canvas (frontend).

### Step-by-step:

```
1. Claude says: "Create a LoadImage node"

2. Claude Code CLI sends MCP request:
   {"method": "tools/call", "params": {"name": "edit_graph", "arguments": {"operations": [...]}}}

3. MCP server (mcp_server.py) receives the request
   → Decomposes edit_graph into individual commands
   → POSTs to http://localhost:3000/claude-code/graph-command:
     {"action": "create_node", "params": {"type": "LoadImage", "pos_x": 200, "pos_y": 200}}

4. ComfyUI backend (__init__.py) receives the POST
   → Assigns a UUID to the command
   → Adds to pending_commands queue
   → Starts polling command_results for up to 5 seconds

5. Frontend JS (claude-code.js) polls GET /claude-code/graph-command every 200ms
   → Receives: {"command": {"id": "uuid-123", "action": "create_node", "params": {...}}}
   → Calls executeGraphCommand(command)

6. Frontend executes the command using LiteGraph API:
   → LiteGraph.createNode("LoadImage")
   → Sets position, title
   → Runs collision avoidance (30px gap, 4-direction search)
   → app.graph.add(node)
   → app.graph.setDirtyCanvas(true, true)

7. Frontend POSTs result back:
   POST /claude-code/graph-command
   {"command_id": "uuid-123", "result": {"status": "created", "node_id": 10, "type": "LoadImage", ...}}

8. Backend picks up the result from command_results dict
   → Returns it to the original POST (step 4)

9. MCP server receives the result
   → Returns it to Claude Code CLI as the tool response

10. Claude sees: "Node created with ID 10"
    → Continues building the workflow
```

### Frontend Action Names

The frontend (`claude-code.js`) expects these specific action names:

| Action | Parameters | Description |
|--------|-----------|-------------|
| `create_node` | `type`, `pos_x` (default 100), `pos_y` (default 100), `title`, `place_in_view` | Create node with collision avoidance |
| `delete_node` | `node_id` | Remove a node |
| `set_node_property` | `node_id`, `property_name`, `value` | Set widget value, node property, or `node.properties` |
| `connect_nodes` | `from_node_id`, `from_slot`, `to_node_id`, `to_slot` | Connect output to input |
| `disconnect_nodes` | `from_node_id`, `from_slot`, `to_node_id`, `to_slot` | Remove a connection |
| `move_node` | `node_id`, `x`/`y` OR `relative_to`/`direction`/`gap`, `width`/`height` | Move and/or resize |
| `center_on_node` | `node_id` | Pan viewport to center on node |
| `get_workflow_api` | (none) | Get prompt-format workflow from frontend |
| `queue_prompt` | (none) | Queue the current workflow for execution |

**Important:** The MCP-level `edit_graph` tool decomposes its operations into these individual frontend actions. When calling the REST API directly, use these action names — not `edit_graph`.

---

## The Embedded Terminal

### How It Works

1. Browser opens WebSocket to `/ws/claude-terminal`
2. Backend spawns a PTY (pseudo-terminal) via `pty.fork()`
3. Claude Code CLI is launched inside the PTY
4. Terminal I/O flows over WebSocket:
   - Input: Browser sends `{"type": "i", "d": "<keystrokes>"}` (fast path)
   - Output: Backend sends `"o<terminal_data>"` (raw string, no JSON parsing needed)
   - Resize: Browser sends `{"type": "resize", "rows": N, "cols": N}` → backend sends `SIGWINCH` to PTY

### Terminal Features

- **xterm.js v5.3.0** with Canvas renderer, Unicode11 support, FitAddon
- **Custom dark theme:** Background `#0d0d0d`, foreground `#e0e0e0`, cursor green `#4ade80`
- **Font:** SF Mono, Monaco, Inconsolata, Fira Code, Consolas (13px)
- **Scrollback:** 1000 lines
- **Keyboard shortcuts:**
  - `Shift+Enter` — literal newline (multi-line Claude input)
  - `Alt+Left/Right` — word navigation
  - `Cmd/Ctrl+Left/Right` — beginning/end of line
  - `Alt+Backspace` — delete word backward
  - `Cmd/Ctrl+Backspace` — delete to line start

### UI Elements

- **Floating window** — draggable, resizable (8-direction), 950x600px default, z-index 10000
- **Header bar** — "Claude Code" title, green/red/yellow MCP status dot, reload/minimize/close buttons
- **Menu button** — purple gradient button in ComfyUI toolbar
- **Context menu** — "Open Claude Code" option in right-click canvas menu
- **Minimize mode** — collapses to small floating badge showing "Claude Code" + MCP dot

### Auto-Setup on Startup

When the terminal first connects:
1. Detects Claude Code CLI location (`find_executable("claude")`)
2. If not installed, auto-installs it (`curl ... | bash` on Unix, PowerShell on Windows)
3. Configures MCP server: `claude mcp add comfyui <python> <mcp_server.py>`
4. Spawns PTY with: `bash -l -i -c "<claude_command>"`
5. If an existing Claude conversation is found (`~/.claude/projects/.../*.jsonl`), adds `-c` flag to continue it

---

## Port Discovery

Comfy-Pilot needs to know where ComfyUI is running. This is handled by:

### `.comfyui_url` File

On startup, `__init__.py` writes the server URL to `.comfyui_url` in the plugin directory:
```
http://127.0.0.1:3000
```

The MCP server reads this file first before probing ports.

### Fallback Port Probing

If `.comfyui_url` doesn't exist or the URL is unreachable, `mcp_server.py` probes these ports in order:
1. `8000` (ComfyUI Desktop default)
2. `8188` (ComfyUI classic default)
3. `8189`

Hard default if nothing responds: `http://127.0.0.1:8000`

### Known Issue

If `PromptServer.instance` retrieval fails during startup, `__init__.py` writes `http://127.0.0.1:8188` as the fallback — which may be wrong if ComfyUI runs on a different port (e.g., 3000). In that case, manually fix:
```bash
echo "http://127.0.0.1:3000" > custom_nodes/Comfy-Pilot/.comfyui_url
```

---

## File Structure

```
Comfy-Pilot/
├── __init__.py          # Backend: REST endpoints, WebSocket terminal, PTY management
│                        #   824 lines, registers 8 routes on ComfyUI's aiohttp server
│
├── mcp_server.py        # MCP Server: 15 tools for workflow manipulation
│                        #   2904 lines, stdio JSON-RPC 2.0, talks to ComfyUI API
│
├── js/
│   └── claude-code.js   # Frontend: xterm.js terminal, graph command executor, UI
│                        #   1424 lines, polls for commands, executes via LiteGraph
│
├── CLAUDE.md            # Instructions for Claude when editing ComfyUI workflows
│                        #   Node layout rules, batch operations, best practices
│
├── .comfyui_url         # Auto-generated: ComfyUI server URL for MCP discovery
│
├── .claude/             # Claude skill definitions for ComfyUI nodes
│   └── skills/
│       └── comfy-nodes/
│
├── tests/               # Test suite (pytest)
├── conftest.py          # Pytest configuration
├── pyproject.toml       # Package metadata (v1.0.24, publisher: constantine)
├── README.md            # Project documentation
├── LICENSE              # MIT License
└── thumbnail.jpg        # Plugin icon
```

---

## Installation

### Method 1: CLI
```bash
comfy node install comfy-pilot
```

### Method 2: ComfyUI Manager
Manager → Install Custom Nodes → Search "Comfy Pilot"

### Method 3: Git Clone
```bash
cd ComfyUI/custom_nodes/
git clone https://github.com/ConstantineB6/Comfy-Pilot.git
```

No `pip install` needed — zero runtime dependencies.

---

## How Comfy-Pilot is Used (Practical Workflow)

### 1. Start ComfyUI
```bash
python main.py --cpu --listen 0.0.0.0 --port 3000
```

### 2. Open the Browser
Navigate to `http://localhost:3000`. You'll see:
- The ComfyUI node editor canvas
- "Claude Code" button in the toolbar (purple)
- The Claude Code floating terminal (auto-opens)
- Green "MCP" indicator showing connection status

### 3. Talk to Claude in the Terminal
The embedded terminal runs Claude Code CLI. You can say things like:

- **"Build me an SDXL workflow with ControlNet"** — Claude uses `get_node_types` to find the right nodes, `edit_graph` to create and connect them, `run` to execute
- **"Load this image and preview it"** — Claude creates LoadImage + PreviewImage nodes, sets the image, connects them, queues execution
- **"Download the FLUX schnell model"** — Claude uses `download_model` with the HuggingFace URL
- **"What nodes do I have?"** — Claude uses `summarize_workflow` to see the current state
- **"Show me the output"** — Claude uses `view_image` to fetch the generated image
- **"Install the ControlNet preprocessor nodes"** — Claude uses `search_custom_nodes` and `install_custom_node`

### 4. Claude's Internal Flow

When you say "Create a workflow that loads an image and previews it":

1. Claude calls `get_node_types(search="LoadImage")` → finds the node type
2. Claude calls `edit_graph` with operations:
   - Create LoadImage node with ref "loader"
   - Create PreviewImage node with ref "preview"
   - Set image property on "loader"
   - Connect "loader" output 0 to "preview" input 0
3. The MCP server decomposes this into individual `create_node`, `set_node_property`, `connect_nodes` commands
4. Each command flows through the graph command system (REST → frontend → LiteGraph → result)
5. Claude calls `run(action="queue")` to execute the workflow
6. Claude calls `view_image()` to show you the result

---

## Global State (Backend)

The `__init__.py` module maintains these globals:

| Variable | Type | Purpose |
|----------|------|---------|
| `terminal_sessions` | `dict` | Active WebSocket terminal sessions, keyed by session ID |
| `current_workflow` | `dict` | Last workflow received from frontend (`{workflow, timestamp}`) |
| `pending_commands` | `list` | Queue of graph commands waiting for frontend execution |
| `command_results` | `dict` | Completed command results keyed by UUID |
| `_comfyui_url_cache` | `str` | Cached server URL |

---

## MCP Server Internals

### Caching

- **`/object_info`** — cached for 300 seconds (5 minutes). Contains all available node type definitions.
- **ComfyUI URL** — lazily resolved on first request, then cached globally.

### Error Handling

- HTTP requests have 10-second timeout (30s for `/object_info`)
- Graph commands have 5-second timeout waiting for frontend response
- Model downloads have 30-minute timeout (10 min for HuggingFace CLI)
- All tool calls are wrapped in try/catch, returning `{error: "..."}` on failure

### TOON Format

Many tools return results in "TOON format" — a compact text representation optimized for AI consumption:
```
nodes:
  [10] LoadImage "Load Image" at (200,200) size 283x102
  [11] PreviewImage "Preview Image" at (600,200) size 140x26

connections:
  [10]:0 -> [11]:0 (IMAGE)
```

---

## Troubleshooting

### Claude CLI Not Found
Comfy-Pilot auto-installs Claude Code CLI. If it fails:
```bash
curl -fsSL https://claude.ai/install.sh | bash
```

### MCP Not Connecting (red dot)
Check if the MCP server is registered:
```bash
claude mcp get comfyui
```
If not, manually add:
```bash
claude mcp add comfyui python3 /path/to/Comfy-Pilot/mcp_server.py
```

### Graph Commands Timeout
The browser MUST be open with ComfyUI loaded. The frontend JS polls for commands every 200ms — without it, commands queue but never execute.

### Terminal Disconnected
Click the reload button (↻) in the terminal header, or refresh the browser page.

### Wrong Port in .comfyui_url
If ComfyUI runs on a non-standard port:
```bash
echo "http://127.0.0.1:YOUR_PORT" > custom_nodes/Comfy-Pilot/.comfyui_url
```

### Windows Limitations
PTY (pseudo-terminal) is not supported on Windows. The embedded terminal will show an error. MCP tools still work if Claude Code is configured separately.
