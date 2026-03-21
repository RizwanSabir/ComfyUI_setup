# File 1: MCP Server (`mcp_server.py`)

## Where It Runs
**Your LOCAL machine** — as a child process of Claude Code CLI.

When you run `claude` in your terminal, Claude Code reads its MCP config and launches:
```
python3 /path/to/Comfy-Pilot/mcp_server.py
```
This process stays running in the background. Claude sends tool calls to it via **stdin**, and it replies via **stdout** using JSON-RPC 2.0.

## What It Does
Translates Claude's high-level intentions into HTTP requests to ComfyUI. It's Claude's **hands and eyes** inside ComfyUI.

Without this file, Claude can talk to you but can't see or touch anything in ComfyUI.

---

## Code Walkthrough (section by section)

### Section 1: URL Discovery (lines 36-71)

```python
def get_comfyui_url() -> str:
```

When the MCP server starts, it needs to find ComfyUI. It checks in order:

1. **Read `.comfyui_url` file** — a plain text file containing the URL (e.g., `http://localhost:3000` or `https://remote-server:3000`). This file is written by the backend (`__init__.py`) or manually by you.
2. **Try localhost ports** — `8000`, `8188`, `8189` (common ComfyUI ports). It hits `/system_stats` on each to test if ComfyUI is there.
3. **Default** — falls back to `http://127.0.0.1:8000`.

**For remote setup:** You write the remote URL to `.comfyui_url`:
```bash
echo "https://your-remote-server:3000" > Comfy-Pilot/.comfyui_url
```

The URL is cached globally in `COMFYUI_URL` after first resolution.

### Section 2: Object Info Cache (lines 73-97)

```python
_object_info_cache = None
_object_info_cache_time = 0
CACHE_TTL = 300  # 5 minutes

def get_object_info_cached() -> dict:
```

ComfyUI's `/object_info` endpoint returns ALL available node types (hundreds of them). This response is large and slow. So the MCP server caches it for 5 minutes. Every `edit_graph()` call needs this to validate that a node type exists before trying to create it.

### Section 3: HTTP Client (lines 100-134)

```python
def make_request(endpoint, method="GET", data=None, timeout=None) -> dict:
```

**Every single tool** ends up calling this function. It:
1. Prepends `COMFYUI_URL` to the endpoint (e.g., `https://remote:3000` + `/object_info`)
2. Sends the HTTP request with optional JSON body
3. Parses the JSON response
4. Returns `{"error": "..."}` if anything goes wrong

Timeout is 30s for `/object_info` (large response), 10s for everything else.

### Section 4: Workflow Reading (lines 137-169)

```python
def get_workflow() -> dict:
```

Tries two sources:
1. **Live canvas** — `GET /claude-code/workflow` (Comfy-Pilot backend). This is the actual canvas state, synced by the frontend every 2 seconds.
2. **History fallback** — `GET /history` (native ComfyUI API). If the browser isn't open, falls back to the last executed workflow.

If neither works: `"No workflow found. Make sure ComfyUI is open in a browser with the Claude Code plugin loaded."`

### Section 5: Node Type Search (lines 172-295)

```python
def get_node_types(search=None, category=None, fields=None) -> str:
```

Searches ComfyUI's available node types. Uses `get_object_info_cached()` so it doesn't hit the server every time.

- **No filters** → returns category summary (e.g., "loaders: 15, sampling: 8, ...")
- **`search="KSampler"`** → returns matching nodes with name, display name, category
- **`fields=["inputs", "outputs"]`** → includes input/output slot details (expensive, only use for specific nodes)

Returns compact text format (not JSON) to save tokens.

### Section 6: Status Tool (lines 325-423)

```python
def get_status(include=None, detail="summary", history_limit=5, history_offset=0) -> str:
```

Combines three native ComfyUI API calls into one tool:
- **Queue** — `GET /queue` → running/pending prompt count
- **System** — `GET /system_stats` → OS, Python version, GPU VRAM usage
- **History** — `GET /history` → past executions with pagination

None of these need Comfy-Pilot — they're native ComfyUI endpoints.

### Section 7: Run Tool (lines 451-493)

```python
def run(action="queue", node_ids=None) -> dict:
```

Two modes:
- **`action="queue"`** — runs the workflow. Sends `queue_prompt` command through the graph command bridge (needs frontend open).
- **`action="interrupt"`** — stops current generation. Hits `POST /interrupt` (native ComfyUI API, no frontend needed).

Before queuing, it fetches the workflow API format from the frontend via `get_workflow_api` graph command, validates any specified node IDs exist.

### Section 8: Edit Graph — The Main Tool (lines 496-788)

```python
def edit_graph(operations) -> str:
```

This is the **most important function**. It takes a list of operations and executes them in order:

| Action | What It Does | Params |
|--------|-------------|--------|
| `create` | Creates a node on canvas | `node_type`, `pos_x`, `pos_y`, `title`, `ref`, `place_in_view` |
| `delete` | Removes a node | `node_id` or `node_ids` |
| `move` | Repositions a node | `node_id`, `x`, `y` OR `relative_to`, `direction`, `gap` |
| `resize` | Changes node size | `node_id`, `width`, `height` |
| `set` | Sets widget values | `node_id`, `property`, `value` OR `properties: {k:v}` |
| `connect` | Wires two nodes | `from_node`, `from_slot`, `to_node`, `to_slot` |
| `disconnect` | Removes a wire | `from_node`, `from_slot`, `to_node`, `to_slot` |

**Key features:**
- **Ref system** — when creating nodes, you can set `ref: "sampler"`, then later operations can reference `"sampler"` instead of the real node ID. The function resolves refs to real IDs.
- **Validation** — checks that node types exist in `object_info` before creating.
- **Collision detection** — after operations, it fetches the workflow and checks if any nodes overlap.
- **Batch results** — returns `"ok: 3/3"` or `"failed: 1/3"` with error details.

Every operation calls `send_graph_command()` which POSTs to the backend.

### Section 9: Graph Command Bridge (lines 884-890)

```python
def send_graph_command(action: str, params: dict) -> dict:
    result = make_request("/claude-code/graph-command", method="POST", data={
        "action": action,
        "params": params
    })
    return result
```

**This is the bridge to the frontend.** Every graph manipulation goes through this single function. It POSTs to the backend (`__init__.py`), which queues it for the frontend (`claude-code.js`) to pick up and execute.

### Section 10: View Image (lines 1470-1607)

```python
def view_image(node_id=None, image_index=0) -> dict:
```

Fetches an output image from a Preview/Save Image node:
1. Gets the workflow to find image nodes
2. Searches execution history for the latest output from that node
3. Downloads the image from `GET /view?filename=...&type=output` (native ComfyUI API)
4. Converts to base64 and returns it so Claude can "see" the image

### Section 11: Custom Node Management (lines 1610-2006)

Four tools for managing custom nodes:

- **`search_custom_nodes(query)`** — searches the ComfyUI Registry API (`https://api.comfy.org/nodes/search`), cross-references with locally installed nodes
- **`install_custom_node(node_id)`** — looks up the git URL from registry, runs `git clone --depth 1` into `custom_nodes/`
- **`uninstall_custom_node(node_id)`** — finds the directory, runs `shutil.rmtree()`
- **`update_custom_node(node_id)`** — runs `git pull` in the node's directory

### Section 12: Model Download (lines 2008-2412)

```python
def download_model(url, model_type, filename=None, hf_token=None, subfolder=None) -> dict:
```

Downloads models from three sources:
- **Hugging Face** — parses HF URLs, uses `huggingface-cli download`
- **CivitAI** — parses CivitAI URLs, uses direct download
- **Direct URLs** — uses `wget` or `curl` or `urllib` fallback

The `model_type` param (checkpoint, lora, vae, etc.) maps to the correct ComfyUI subfolder via `MODEL_TYPE_FOLDERS` dict.

### Section 13: MCP Protocol Handler (lines 2415-end)

```python
def send_response(response: dict):
    sys.stdout.write(json.dumps(response) + "\n")
    sys.stdout.flush()

def handle_request(request: dict) -> dict:
```

The main loop:
1. Reads JSON-RPC requests from **stdin** (sent by Claude Code)
2. Routes to the right handler based on `method`:
   - `initialize` → returns server capabilities
   - `tools/list` → returns all 15 tool definitions with JSON schemas
   - `tools/call` → dispatches to the right function (`get_workflow`, `edit_graph`, etc.)
3. Writes JSON-RPC response to **stdout**

The `tools/list` response defines all 15 tools with their parameter schemas — this is what Claude sees when deciding which tools to use.

---

## The 15 Tools Summary

| # | Tool | Needs Comfy-Pilot? | What It Hits |
|---|------|-------------------|-------------|
| 1 | `get_workflow` | YES | `GET /claude-code/workflow` |
| 2 | `summarize_workflow` | YES | `GET /claude-code/workflow` |
| 3 | `get_node_types` | NO | `GET /object_info` |
| 4 | `get_node_info` | YES | `GET /claude-code/workflow` + `/object_info` |
| 5 | `get_status` | NO | `GET /queue`, `/system_stats`, `/history` |
| 6 | `run` | YES | `POST /claude-code/graph-command` |
| 7 | `edit_graph` | YES | `POST /claude-code/graph-command` |
| 8 | `view_image` | YES | `GET /claude-code/workflow` + `GET /view` |
| 9 | `center_on_node` | YES | `POST /claude-code/graph-command` |
| 10 | `search_custom_nodes` | NO | `GET https://api.comfy.org/nodes/search` |
| 11 | `install_custom_node` | NO | `git clone` on server filesystem |
| 12 | `uninstall_custom_node` | NO | `shutil.rmtree` on server filesystem |
| 13 | `update_custom_node` | NO | `git pull` on server filesystem |
| 14 | `download_model` | NO | `wget`/`curl`/`urllib` to download files |

Tools 11-14 only work if the MCP server runs ON the same machine as ComfyUI (they access the filesystem directly). For remote setups, these won't work unless you run the MCP server on the remote machine too.
