# How All 4 Pieces Integrate

## The Architecture

```
YOUR LOCAL MACHINE                              REMOTE SERVER (ComfyUI)
┌──────────────────────────────┐               ┌─────────────────────────────────┐
│                              │               │                                 │
│  ┌────────────────────────┐  │               │  ┌───────────────────────────┐  │
│  │  4. CLAUDE CODE CLI    │  │               │  │  Native ComfyUI API       │  │
│  │  (the brain)           │  │               │  │  /object_info             │  │
│  │                        │  │               │  │  /queue                   │  │
│  │  Understands your      │  │               │  │  /history                 │  │
│  │  natural language      │  │               │  │  /view                    │  │
│  │  Decides which tools   │  │               │  │  /system_stats            │  │
│  │  to call               │  │               │  │  /prompt                  │  │
│  └──────────┬─────────────┘  │               │  └───────────────────────────┘  │
│       stdin/stdout (JSON-RPC)│               │                                 │
│  ┌──────────▼─────────────┐  │               │  ┌───────────────────────────┐  │
│  │  1. MCP SERVER         │  │    HTTP/S     │  │  2. BACKEND (__init__.py) │  │
│  │  (mcp_server.py)       │──┼──────────────►│  │                           │  │
│  │                        │  │               │  │  /claude-code/workflow    │  │
│  │  Translates tool calls │  │               │  │  /claude-code/graph-cmd   │  │
│  │  into HTTP requests    │◄─┼──────────────┤│  │  /claude-code/mcp-status │  │
│  └────────────────────────┘  │               │  │  /ws/claude-terminal      │  │
│                              │               │  └─────────────┬─────────────┘  │
│  ┌────────────────────────┐  │               │                │                │
│  │  YOUR BROWSER          │  │               │  ┌─────────────▼─────────────┐  │
│  │                        │  │   loads page  │  │  3. FRONTEND (JS)         │  │
│  │  Opens the ComfyUI     │──┼──────────────►│  │  (claude-code.js)         │  │
│  │  page from remote      │  │               │  │                           │  │
│  │  server                │◄─┼──────────────┤│  │  Polls every 200ms       │  │
│  │                        │  │    renders    │  │  Executes LiteGraph cmds  │  │
│  └────────────────────────┘  │               │  │  Syncs workflow every 2s  │  │
│                              │               │  └───────────────────────────┘  │
└──────────────────────────────┘               └─────────────────────────────────┘
```

---

## The 3 Communication Channels

### Channel 1: Claude Code ↔ MCP Server (stdin/stdout)
```
Claude Code CLI  ──stdin──►  mcp_server.py
Claude Code CLI  ◄─stdout──  mcp_server.py
```
- **Protocol:** JSON-RPC 2.0 (one JSON object per line)
- **Transport:** Unix pipes (stdin/stdout of child process)
- **Speed:** Instant (in-process pipes)
- **What flows:** Tool calls and results
  - `→` "call edit_graph with operations=[create LoadImage]"
  - `←` "ok: 1/1, created: 5"

### Channel 2: MCP Server ↔ Backend (HTTP)
```
mcp_server.py  ──HTTP POST──►  __init__.py (on remote server)
mcp_server.py  ◄─HTTP resp───  __init__.py
```
- **Protocol:** HTTP/HTTPS with JSON bodies
- **Transport:** TCP over network (local or remote)
- **Speed:** ~10-50ms for local, ~50-200ms for remote
- **What flows:**
  - Read-only requests → native ComfyUI endpoints (`/object_info`, `/queue`, etc.)
  - Graph commands → Comfy-Pilot endpoints (`/claude-code/graph-command`)

### Channel 3: Frontend ↔ Backend (HTTP polling + WebSocket)
```
claude-code.js  ──GET /graph-command──►  __init__.py     (every 200ms)
claude-code.js  ──POST /graph-command──►  __init__.py     (results)
claude-code.js  ──POST /workflow──────►  __init__.py     (every 2s)
claude-code.js  ◄──WebSocket──────────►  __init__.py     (terminal I/O)
```
- **Protocol:** HTTP polling (commands) + WebSocket (terminal)
- **Transport:** Same TCP connection as the page
- **Speed:** Max 200ms latency for commands (polling interval)
- **What flows:**
  - Workflow state (canvas → backend, every 2s)
  - Graph commands (backend → canvas, polled every 200ms)
  - Command results (canvas → backend, immediate)
  - Terminal I/O (bidirectional WebSocket)

---

## Complete Flow: "Create a LoadImage node"

Here is the exact sequence across all 4 pieces, with timing:

```
TIME    WHO                WHAT
─────   ─────────────────  ──────────────────────────────────────────────

0ms     YOU                Type: "create a LoadImage node"

50ms    CLAUDE CODE        AI receives message, thinks about which tool to use

200ms   CLAUDE CODE        Decides to call edit_graph. Writes to stdin:
                           {"method": "tools/call", "params": {
                             "name": "edit_graph",
                             "arguments": {"operations": [{
                               "action": "create",
                               "node_type": "LoadImage",
                               "title": "Load Image",
                               "pos_x": 200, "pos_y": 200
                             }]}
                           }}

201ms   MCP SERVER         Receives on stdin. Calls edit_graph().
                           First checks: does "LoadImage" exist?
                           → Calls get_object_info_cached()
                           → Cached, returns instantly. Yes it exists.

202ms   MCP SERVER         Calls send_graph_command("create_node", {...})
                           → HTTP POST to https://remote:3000/claude-code/graph-command
                           → Body: {"action": "create_node", "params": {"type": "LoadImage", ...}}

250ms   BACKEND            Receives POST. Generates command ID: "abc-123".
                           Wraps as: {"id": "abc-123", "action": "create_node", "params": {...}}
                           Appends to pending_commands list.
                           Starts waiting for result (async, up to 5 seconds).

300ms   FRONTEND           pollGraphCommands() fires (every 200ms).
                           GET /claude-code/graph-command
                           Backend pops "abc-123" from pending_commands, returns it.

301ms   FRONTEND           Receives command. Calls executeGraphCommand():
                           → action = "create_node"
                           → LiteGraph.createNode("LoadImage")
                           → node.pos = findFreePosition(200, 200)
                           → node.title = "Load Image"
                           → app.graph.add(node)
                           → app.graph.setDirtyCanvas(true, true)
                           → NODE APPEARS ON CANVAS

310ms   FRONTEND           POST /claude-code/graph-command
                           Body: {"command_id": "abc-123", "result": {
                             "status": "created", "node_id": "5",
                             "pos": [200, 200], "size": [315, 58]
                           }}

311ms   BACKEND            Stores result in command_results["abc-123"].
                           The async wait from 250ms detects it. Unblocks.
                           Returns HTTP response to MCP server.

350ms   MCP SERVER         Receives HTTP response: {"status": "created", "node_id": "5"}
                           Builds text result: "ok: 1/1\ncreated: 5"
                           Writes to stdout.

351ms   CLAUDE CODE        Reads result from stdout.
                           Tells you: "I created a LoadImage node (ID: 5)"

TOTAL: ~350ms from tool call to visible result on canvas
```

---

## What Needs What

### If the BROWSER IS CLOSED:

| Tool | Works? | Why |
|------|--------|-----|
| `get_status` | YES | Native ComfyUI API |
| `get_node_types` | YES | Native ComfyUI API |
| `get_workflow` | NO | Needs frontend to sync canvas |
| `summarize_workflow` | NO | Needs frontend to sync canvas |
| `edit_graph` | NO | Commands timeout after 5s |
| `run` | NO | Uses frontend's queue_prompt |
| `view_image` | PARTIAL | Can view from history, not live |
| `search_custom_nodes` | YES | Calls external API |
| `install/uninstall/update` | YES* | Filesystem operations |
| `download_model` | YES* | Download operations |

*Only if MCP server runs on same machine as ComfyUI.

### If COMFY-PILOT IS NOT INSTALLED on server:

| Tool | Works? | Why |
|------|--------|-----|
| `get_status` | YES | Native ComfyUI API |
| `get_node_types` | YES | Native ComfyUI API |
| `get_workflow` | NO | No `/claude-code/workflow` endpoint |
| `edit_graph` | NO | No `/claude-code/graph-command` endpoint |
| `run` | NO | No `/claude-code/graph-command` endpoint |
| Everything else | NO | Needs Comfy-Pilot endpoints |

### If MCP SERVER IS NOT CONFIGURED:

Nothing works. Claude Code doesn't know ComfyUI exists. It's a regular AI without any ComfyUI tools.

---

## Setup Checklist for Remote ComfyUI

### On the REMOTE server:
1. ComfyUI is running (e.g., port 3000)
2. **Install Comfy-Pilot:**
   ```bash
   cd /path/to/ComfyUI/custom_nodes
   git clone https://github.com/ConstantineB6/Comfy-Pilot.git
   ```
3. Restart ComfyUI
4. Verify: `curl http://localhost:3000/claude-code/mcp-status`
   → `{"connected": true, "tools": 15}`

### On YOUR LOCAL machine:
1. Claude Code CLI is installed (`which claude`)
2. Clone or have Comfy-Pilot locally (for the `mcp_server.py` file):
   ```bash
   git clone https://github.com/ConstantineB6/Comfy-Pilot.git
   ```
3. Point MCP server at remote URL:
   ```bash
   echo "https://your-remote-url:3000" > Comfy-Pilot/.comfyui_url
   ```
4. Register MCP server:
   ```bash
   claude mcp add comfyui python3 /path/to/Comfy-Pilot/mcp_server.py
   ```
5. Open the remote ComfyUI in your browser:
   `https://your-remote-url:3000`
   (The frontend JS must be running for graph commands to work)

### Verify everything:
```bash
# In Claude Code:
> check comfyui status

# Claude should call get_status and report:
# "ComfyUI is running on linux, python 3.12, 0 items in queue"
```

---

## Data Flow Diagram for Each Tool

### `edit_graph` (needs all 4 pieces):
```
Claude → stdin → MCP Server → HTTP POST → Backend → pending_commands
                                                          ↓
                                            Frontend polls (200ms)
                                                          ↓
                                            Frontend executes (LiteGraph)
                                                          ↓
                                            Frontend POSTs result → Backend → command_results
                                                                                    ↓
                               MCP Server ← HTTP response ← Backend unblocks
                                    ↓
                        Claude ← stdout ← MCP Server
```

### `get_status` (needs only MCP Server + ComfyUI):
```
Claude → stdin → MCP Server → HTTP GET /queue → ComfyUI native API
                                    ↓
                        Claude ← stdout ← MCP Server ← HTTP response
```

### `view_image` (needs MCP Server + Backend + ComfyUI):
```
Claude → stdin → MCP Server → HTTP GET /claude-code/workflow → Backend → cached workflow
                                    ↓
                    MCP Server finds image node in workflow
                                    ↓
                    MCP Server → HTTP GET /history → ComfyUI (find image filename)
                                    ↓
                    MCP Server → HTTP GET /view?filename=... → ComfyUI (download image)
                                    ↓
                    MCP Server converts to base64
                                    ↓
                        Claude ← stdout ← MCP Server (sees the image)
```

---

## Failure Modes

| Failure | Symptom | Fix |
|---------|---------|-----|
| Browser closed | `edit_graph` returns "Timeout waiting for frontend" after 5s | Open browser to ComfyUI page |
| Comfy-Pilot not installed | `edit_graph` returns "HTTP Error 405" | Install Comfy-Pilot on server, restart ComfyUI |
| Wrong `.comfyui_url` | `get_status` returns "Failed to connect" | Fix URL in `.comfyui_url` file |
| MCP not registered | Claude says "I don't have ComfyUI tools" | Run `claude mcp add comfyui ...` |
| ComfyUI not running | All tools return connection errors | Start ComfyUI on the server |
| Network issue | Intermittent timeouts | Check firewall, try SSH tunnel |
