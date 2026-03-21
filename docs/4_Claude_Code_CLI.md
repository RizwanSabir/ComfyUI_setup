# File 4: Claude Code CLI (the Brain)

## Where It Runs
**Your LOCAL machine** — in your terminal, or inside the embedded xterm.js terminal in the browser.

Claude Code is Anthropic's official CLI tool. It's the AI brain that understands your natural language and decides which MCP tools to call.

## What It Is
It's NOT part of the Comfy-Pilot codebase — it's a separate binary you install:
```bash
curl -fsSL https://claude.ai/install.sh | bash
```

It lives at `~/.claude/` and is invoked as `claude` from the terminal.

## What It Does
1. **Receives your natural language** — "build me a workflow that loads an image and previews it"
2. **Reads its MCP config** — knows it has 15 ComfyUI tools available
3. **Launches the MCP server** — spawns `python3 mcp_server.py` as a child process
4. **Decides which tools to call** — AI reasoning: "I need to search for LoadImage node, create it, create PreviewImage, connect them"
5. **Sends tool calls** — writes JSON-RPC to the MCP server's stdin
6. **Receives results** — reads JSON-RPC from the MCP server's stdout
7. **Shows you the result** — "I've created a LoadImage node connected to PreviewImage"

Without Claude Code, the MCP server exists but nobody calls it. Like a kitchen with no chef.

---

## How It Connects to the MCP Server

### Configuration

Claude Code reads MCP server configs from `~/.claude.json` (or per-project settings):

```json
{
    "mcpServers": {
        "comfyui": {
            "command": "python3",
            "args": ["/path/to/Comfy-Pilot/mcp_server.py"]
        }
    }
}
```

You register it with:
```bash
claude mcp add comfyui python3 /path/to/Comfy-Pilot/mcp_server.py
```

### What Happens on Startup

1. You type `claude` in your terminal
2. Claude Code reads its config, sees the `comfyui` MCP server
3. It spawns: `python3 /path/to/mcp_server.py`
4. Sends `initialize` request → gets back server capabilities
5. Sends `tools/list` request → gets back all 15 tool definitions
6. Now Claude knows what tools it has and can use them

### The Tool Call Flow

When you say "create a LoadImage node":

```
YOU: "create a LoadImage node"
         │
         ▼
CLAUDE CODE (AI thinks):
  "I should use the edit_graph tool with action=create, node_type=LoadImage"
         │
         ▼
CLAUDE CODE writes to MCP server stdin:
  {"jsonrpc": "2.0", "id": 1, "method": "tools/call",
   "params": {"name": "edit_graph", "arguments": {
     "operations": [{"action": "create", "node_type": "LoadImage",
                     "title": "Load Image", "pos_x": 200, "pos_y": 200}]
   }}}
         │
         ▼
MCP SERVER processes it:
  - Validates "LoadImage" exists in object_info
  - POSTs to /claude-code/graph-command
  - Waits for frontend to execute and return result
         │
         ▼
MCP SERVER writes to stdout:
  {"jsonrpc": "2.0", "id": 1, "result": {
    "content": [{"type": "text", "text": "ok: 1/1\ncreated: 5"}]
  }}
         │
         ▼
CLAUDE CODE reads the result and tells you:
  "I created a LoadImage node (ID: 5) at position (200, 200)"
```

---

## Two Ways to Run Claude Code

### 1. Standalone Terminal (your local terminal)
```bash
cd /path/to/project
claude
```
You talk to Claude in your regular terminal. It has the MCP tools. But you also need a browser open to the ComfyUI page for graph commands to work.

### 2. Embedded Terminal (inside ComfyUI browser)
When you open ComfyUI with Comfy-Pilot installed, a floating terminal window appears in the browser. This runs `claude` inside a PTY (pseudo-terminal) on the server, streamed to your browser via WebSocket.

The flow:
```
Browser xterm.js → WebSocket → Backend PTY → claude CLI → MCP server → HTTP → Backend → Frontend JS
```

Both ways use the same MCP server and tools. The difference is just where the terminal UI lives.

---

## What Claude Sees (Tool Definitions)

When Claude Code asks the MCP server "what tools do you have?", it gets back 15 tool definitions. Here's what Claude sees for the key ones:

### `edit_graph` — Claude sees:
```
"Edit workflow graph with batched operations.
 Actions: create, delete, move, resize, set, connect, disconnect.
 Operations execute in order; 'create' returns node_id for chaining."
```
With a schema defining `operations` as a list of objects with `action` + params.

### `get_workflow` — Claude sees:
```
"Get the current workflow from ComfyUI.
 Returns full node graph with all nodes, connections, and widget values."
```

### `run` — Claude sees:
```
"Run workflow or interrupt current generation.
 action='queue' to run, 'interrupt' to stop."
```

### `view_image` — Claude sees:
```
"View an image from a Preview Image or Save Image node.
 Returns the image as base64 so you can see it."
```

Claude uses these descriptions to decide which tool to call for each situation. The better the descriptions, the better Claude's tool selection.

---

## Example: Full Conversation Flow

**You:** "Load A.jpg and preview it"

**Claude thinks:**
1. First I need to know what node types are available → calls `get_node_types(search="LoadImage")`
2. LoadImage exists with IMAGE output on slot 0 → calls `edit_graph` with:
   - Create LoadImage at (200, 200), title "Load Image", ref "loader"
   - Create PreviewImage at (600, 200), title "Preview", ref "preview"
   - Set "loader" property "image" to "A.jpg"
   - Connect "loader" slot 0 → "preview" slot 0
3. All created successfully → calls `run(action="queue")` to execute
4. Workflow runs → calls `view_image()` to see the result
5. Returns base64 image → Claude describes what it sees

**Total tool calls:** 4 (search, edit, run, view)
**Total time:** ~3-5 seconds
