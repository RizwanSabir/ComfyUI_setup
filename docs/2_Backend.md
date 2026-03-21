# File 2: Backend (`__init__.py`)

## Where It Runs
**On the REMOTE server** (or wherever ComfyUI is running) — inside the ComfyUI server process.

When ComfyUI starts, it scans `custom_nodes/` and imports each folder's `__init__.py`. So this file runs automatically as part of ComfyUI's Python process. It adds new HTTP endpoints to ComfyUI's existing web server.

## What It Does
Acts as a **message board** between the MCP server and the frontend. Neither can talk to each other directly — the MCP server speaks stdin/stdout, the frontend is JavaScript in a browser. This backend sits in the middle, holding messages until the other side picks them up.

Without this file, the MCP server has nowhere to send commands and the frontend has nowhere to poll.

---

## Code Walkthrough (section by section)

### Section 1: Platform Detection and Imports (lines 1-39)

```python
IS_WINDOWS = sys.platform == "win32"

if not IS_WINDOWS:
    import pty, select, fcntl, termios, signal, resource
```

The terminal feature (embedded Claude Code in the browser) needs Unix PTY (pseudo-terminal) support. On Windows, the terminal is disabled but all REST endpoints still work.

Key exports:
```python
NODE_CLASS_MAPPINGS = {}
NODE_DISPLAY_NAME_MAPPINGS = {}
WEB_DIRECTORY = "./js"
```
- `NODE_CLASS_MAPPINGS` is empty — Comfy-Pilot doesn't register any ComfyUI nodes. It's purely a backend extension.
- `WEB_DIRECTORY = "./js"` tells ComfyUI to serve the `js/` folder as static files, which loads the frontend.

### Section 2: Claude CLI Detection (lines 42-205)

```python
def has_claude_conversation(working_dir=None):
def find_executable(name, verbose=False):
def is_claude_installed():
def install_claude_code():
def get_claude_command(working_dir=None):
```

These functions find the `claude` CLI on the system:
- Checks standard `PATH`, then common locations (Homebrew, nvm, Conda, etc.)
- If not found, auto-installs it (`curl ... | bash`)
- Detects if there's an existing conversation (`claude -c` to resume vs `claude` to start fresh)

Used when spawning the terminal process.

### Section 3: WebSocketTerminal Class (lines 207-326)

```python
class WebSocketTerminal:
    def spawn(self, command=None):
    def resize(self, rows, cols):
    def write(self, data):
    def read_nonblock(self):
    def close(self):
```

Manages a PTY (pseudo-terminal) session. When a user opens the terminal in the browser:
1. `spawn()` — forks a new process via `pty.fork()`, runs the `claude` command in it
2. `write()` — sends keystrokes from the browser to the PTY
3. `read_nonblock()` — reads terminal output from the PTY (non-blocking)
4. `resize()` — sends `SIGWINCH` to tell the process about terminal size changes
5. `close()` — kills the process and closes the file descriptor

This is Unix-only. On Windows, the class is a stub.

### Section 4: Global State — THE MESSAGE BOARD (lines 328-336)

```python
current_workflow = {"workflow": None, "timestamp": None}
pending_commands = []
command_results = {}
```

**These three variables are the entire communication system:**

| Variable | Who Writes | Who Reads | What It Holds |
|----------|-----------|-----------|---------------|
| `current_workflow` | Frontend (every 2s) | MCP server (on demand) | The current canvas state |
| `pending_commands` | MCP server (when Claude calls a tool) | Frontend (every 200ms) | Commands waiting to be executed |
| `command_results` | Frontend (after executing a command) | MCP server (waiting for result) | Results of executed commands |

### Section 5: Memory Monitoring (lines 338-396)

```python
def get_memory_mb():
def log_memory(context=""):
def get_plugin_memory_breakdown():
async def memory_stats_handler(request):
```

Tracks memory usage of the plugin's data structures. Logs every 60 seconds. Available at `GET /claude-code/memory`. This is diagnostic — helps detect if workflows or command queues are growing too large.

### Section 6: Workflow Endpoint (lines 399-418)

```python
async def workflow_handler(request):
    if request.method == "POST":
        # Frontend sends canvas state
        current_workflow = {
            "workflow": data.get("workflow"),
            "workflow_api": data.get("workflow_api"),
            "timestamp": data.get("timestamp")
        }
    else:
        # GET - MCP server reads it
        return web.json_response(current_workflow)
```

**Two consumers:**
- `POST /claude-code/workflow` — the frontend calls this every 2 seconds with `app.graph.serialize()` (the full canvas state as JSON)
- `GET /claude-code/workflow` — the MCP server calls this when Claude uses `get_workflow()` or `summarize_workflow()`

### Section 7: Graph Command Endpoint — THE CORE (lines 421-468)

```python
async def graph_command_handler(request):
```

This is the **most important endpoint**. Three HTTP methods on the same URL:

**1. MCP server POSTs a new command:**
```
POST /claude-code/graph-command
Body: {"action": "create_node", "params": {"type": "LoadImage", ...}}
```
The backend:
- Generates a unique command ID (UUID)
- Wraps the command: `{"id": uuid, "action": "create_node", "params": {...}}`
- Appends it to `pending_commands` list
- **Blocks** (async sleep loop) for up to 5 seconds, waiting for the result in `command_results`
- Returns the result or timeout error

**2. Frontend GETs the next pending command:**
```
GET /claude-code/graph-command
```
The frontend polls this every 200ms. If `pending_commands` is not empty, it pops the first command and returns it. If empty, returns `{"command": null}`.

**3. Frontend POSTs back the result:**
```
POST /claude-code/graph-command
Body: {"command_id": "uuid-here", "result": {"status": "created", "node_id": "5"}}
```
The backend stores it in `command_results[command_id]`. The MCP server's blocking wait (from step 1) detects it and returns the result to Claude.

**The timing flow:**
```
  Time 0ms:  MCP server POSTs command → backend adds to pending_commands, starts waiting
  Time 0ms:  Backend is now blocked, waiting for result...
  Time 200ms: Frontend polls GET → picks up the command
  Time 210ms: Frontend executes it (LiteGraph.createNode(...))
  Time 220ms: Frontend POSTs result back
  Time 220ms: Backend unblocks, returns result to MCP server

  Total roundtrip: ~220ms

  If frontend never picks it up (browser closed):
  Time 5000ms: Backend timeout → returns {"error": "Timeout waiting for frontend"}
```

### Section 8: Run Node Endpoint (lines 471-516)

```python
async def run_node_handler(request):
```

Direct workflow execution via `POST /claude-code/run-node`. Takes a `node_id`, validates it exists in the workflow API format, then queues the prompt via ComfyUI's internal `PromptQueue`. This is a server-side execution path (doesn't need the frontend).

### Section 9: WebSocket Terminal Handler (lines 519-648)

```python
async def websocket_handler(request):
```

Handles the WebSocket connection for the embedded terminal:
1. Browser connects to `ws://host/ws/claude-terminal`
2. Backend creates a `WebSocketTerminal`, waits for first `resize` message
3. On first resize → spawns PTY with `claude` command at the correct terminal size
4. Starts async read loop: PTY output → WebSocket → browser
5. Handles messages from browser: keystrokes (`type: "i"`), resize events (`type: "resize"`)
6. On disconnect → kills PTY process, cleans up

The protocol uses a fast path: `"o" + data` for output (no JSON overhead), `{"type": "i", "d": data}` for input.

### Section 10: Status and Info Endpoints (lines 650-686)

```python
async def mcp_status_handler(request):    # GET /claude-code/mcp-status
async def platform_info_handler(request): # GET /claude-code/platform
```

- **MCP status** — checks if `mcp_server.py` file exists. Returns `{"connected": true, "tools": 15}`. The frontend's green/red MCP dot uses this.
- **Platform info** — returns OS, Python version, whether terminal is supported.

### Section 11: Route Registration (lines 706-726)

```python
def setup_routes(app):
    app.router.add_get("/ws/claude-terminal", websocket_handler)
    app.router.add_get("/claude-code/workflow", workflow_handler)
    app.router.add_post("/claude-code/workflow", workflow_handler)
    app.router.add_post("/claude-code/run-node", run_node_handler)
    app.router.add_get("/claude-code/graph-command", graph_command_handler)
    app.router.add_post("/claude-code/graph-command", graph_command_handler)
    app.router.add_get("/claude-code/mcp-status", mcp_status_handler)
    app.router.add_get("/claude-code/memory", memory_stats_handler)
    app.router.add_get("/claude-code/platform", platform_info_handler)
```

Registers all 8 endpoints on ComfyUI's aiohttp web server. This is why Comfy-Pilot needs to be installed as a custom node — it hooks into ComfyUI's server.

### Section 12: Auto-Setup (lines 728-821)

```python
def write_comfyui_url():
def setup_mcp_config():
```

On startup:
1. **Writes `.comfyui_url`** — records the server's address/port so the MCP server can find it
2. **Registers MCP server** — runs `claude mcp add comfyui python3 /path/to/mcp_server.py` so Claude Code knows about the tools

The final block (lines 800-821) runs at import time:
```python
from server import PromptServer
setup_routes(PromptServer.instance.app)
write_comfyui_url()
setup_mcp_config()
```

---

## All Endpoints Summary

| Endpoint | Method | Who Calls It | Purpose |
|----------|--------|-------------|---------|
| `/ws/claude-terminal` | WebSocket | Browser | Terminal I/O |
| `/claude-code/workflow` | GET | MCP server | Read canvas state |
| `/claude-code/workflow` | POST | Frontend JS | Write canvas state |
| `/claude-code/graph-command` | GET | Frontend JS (poll) | Pick up pending commands |
| `/claude-code/graph-command` | POST | MCP server | Send new commands |
| `/claude-code/graph-command` | POST | Frontend JS | Return command results |
| `/claude-code/run-node` | POST | MCP server | Execute specific node |
| `/claude-code/mcp-status` | GET | Frontend JS | Check MCP availability |
| `/claude-code/memory` | GET | Anyone | Memory diagnostics |
| `/claude-code/platform` | GET | Anyone | Platform info |
