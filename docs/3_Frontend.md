# File 3: Frontend (`js/claude-code.js`)

## Where It Runs
**In YOUR LOCAL browser** — loaded as a ComfyUI extension when you open the ComfyUI page.

When you visit `http://localhost:3000` (or the remote URL), ComfyUI's frontend loads all extensions from `custom_nodes/*/js/`. This file is served by ComfyUI and executed in your browser.

## What It Does
Two jobs:
1. **Shows the xterm.js terminal** — a floating window where you talk to Claude
2. **Executes graph commands** — polls the backend every 200ms, picks up commands (create node, connect, etc.), and executes them on the canvas using LiteGraph's JavaScript API

Without this file, commands from the MCP server queue up and timeout after 5 seconds. The frontend is the **only thing** that can manipulate the visual canvas.

---

## Code Walkthrough (section by section)

### Section 1: Extension Registration (lines 1-40)

```javascript
import { app } from "../../scripts/app.js";

app.registerExtension({
    name: "comfy.claude-code",
    async setup() {
        await loadXtermDependencies();
        floatingWindow = createFloatingWindow();
        document.body.appendChild(floatingWindow);
        makeDraggable(floatingWindow, ...);
        makeResizable(floatingWindow);
        addMenuButton(floatingWindow);
        addContextMenuOption();
        startWorkflowSync();
    },
});
```

ComfyUI's extension system: `app.registerExtension()` registers a setup function that runs after ComfyUI loads. It:
1. Loads xterm.js dependencies from CDN
2. Creates the floating terminal window
3. Makes it draggable and resizable
4. Adds a "Claude Code" button to ComfyUI's menu bar
5. Adds a right-click context menu option
6. Starts the workflow sync and command polling loops

### Section 2: Xterm.js Dependencies (lines 42-70)

```javascript
async function loadXtermDependencies() {
    // xterm.js CSS
    // xterm.js core
    // xterm-addon-fit (auto-resize to container)
    // xterm-addon-canvas (GPU-accelerated rendering)
    // xterm-addon-unicode11 (proper character widths)
}
```

Loads terminal libraries from CDN. These make the browser terminal look and behave like a real terminal (colors, cursor, scrollback, Unicode support).

### Section 3: Floating Window UI (lines 73-440)

```javascript
function createFloatingWindow() {
```

Creates the entire terminal UI as a DOM element:
- **Header bar** — title "Claude Code", MCP status indicator (green/red dot), reload/minimize/close buttons
- **Terminal area** — `<div id="claude-terminal">` where xterm.js renders
- **CSS styles** — dark theme, resize handles on all edges and corners

**MCP Status Indicator:**
- Green dot = Comfy-Pilot backend is running
- Red dot = backend not reachable
- Yellow pulsing = checking...

**Button behaviors:**
- **x (close)** — hides the window (`display: none`)
- **- (minimize)** — collapses to just the header bar
- **↻ (reload)** — kills and reconnects the WebSocket terminal

### Section 4: Terminal Initialization (lines 442-645)

```javascript
function initTerminal(terminalContainer) {
    terminal = new Terminal({
        cursorBlink: true,
        fontSize: 13,
        theme: { background: "#0d0d0d", ... },
        scrollback: 1000,
    });
```

Creates the xterm.js terminal instance with:
- Dark theme matching ComfyUI
- Canvas renderer (faster than DOM)
- Unicode 11 support (for Claude Code's box-drawing characters)
- Custom keyboard shortcuts (Alt+arrows for word navigation, Shift+Enter for multiline input)

**Input handling:**
```javascript
terminal.onData((data) => {
    websocket.send(JSON.stringify({ type: "i", d: data }));
});
```
Every keystroke is sent to the backend's WebSocket as `{"type": "i", "d": "a"}`. The backend writes it to the PTY, which feeds it to `claude` CLI.

**Output handling:**
```javascript
websocket.onmessage = (event) => {
    if (data[0] === 'o') {
        terminal.write(data.slice(1));
    }
};
```
Output from the PTY comes back as `"o" + text`. The `"o"` prefix is a fast-path marker (avoids JSON parsing overhead for the hot path).

### Section 5: WebSocket Connection (lines 665-746)

```javascript
function connectWebSocket() {
    const protocol = window.location.protocol === "https:" ? "wss:" : "ws:";
    const wsUrl = `${protocol}//${window.location.host}/ws/claude-terminal`;
    websocket = new WebSocket(wsUrl);
```

Connects to the backend's terminal WebSocket. On open:
1. Clears the terminal
2. Fits the terminal to its container
3. Sends the terminal dimensions (`resize` message) — this triggers the backend to spawn the `claude` process
4. Sends resize again after delays (300ms, 800ms, 1500ms) to force Claude to redraw properly

### Section 6: Dragging and Resizing (lines 748-882)

```javascript
function makeDraggable(element, handle) { ... }
function makeResizable(element) { ... }
```

Standard drag-and-drop and resize implementations:
- Drag by the header bar, constrained to viewport
- Resize from any edge or corner (8 handles), minimum 400x300px
- Debounced terminal re-fit after resize

### Section 7: MCP Status Check (lines 965-997)

```javascript
async function checkMcpStatus() {
    const response = await fetch("/claude-code/mcp-status");
    const data = await response.json();
    if (data.connected) {
        indicator.className = "mcp-indicator connected"; // green
    } else {
        indicator.className = "mcp-indicator disconnected"; // red
    }
}
```

Hits `GET /claude-code/mcp-status` on the backend. Only runs when you click the MCP indicator (no polling). Shows green if backend responds with `connected: true`.

### Section 8: Workflow Sync — CRITICAL (lines 999-1051)

```javascript
function startWorkflowSync() {
    syncWorkflow();
    setInterval(syncWorkflow, 2000);      // Sync canvas every 2 seconds
    pollGraphCommands();
    setInterval(pollGraphCommands, 200);   // Poll commands every 200ms
}
```

Two intervals start when the extension loads:

**Every 2 seconds — `syncWorkflow()`:**
```javascript
async function syncWorkflow() {
    const workflow = app.graph.serialize();  // Get full canvas state
    // Simple hash to skip if unchanged
    await fetch("/claude-code/workflow", {
        method: "POST",
        body: JSON.stringify({
            workflow: workflow,
            timestamp: Date.now(),
        }),
    });
}
```
Serializes the entire canvas (all nodes, positions, connections, widget values) and POSTs it to the backend. The hash check avoids sending if nothing changed.

**Every 200ms — `pollGraphCommands()`:**
```javascript
async function pollGraphCommands() {
    const response = await fetch("/claude-code/graph-command");
    const data = await response.json();
    if (data.command) {
        const result = await executeGraphCommand(data.command);
        await fetch("/claude-code/graph-command", {
            method: "POST",
            body: JSON.stringify({
                command_id: data.command.id,
                result: result
            })
        });
    }
}
```
Polls the backend for pending commands. If there's one, executes it and sends the result back. This is the **heartbeat** of the whole system — 5 times per second, asking "anything for me to do?"

### Section 9: Graph Command Execution — THE HANDS (lines 1076-1400+)

```javascript
async function executeGraphCommand(command) {
    const { action, params } = command;
    switch (action) {
```

This is where commands actually happen on the canvas. Each case uses LiteGraph's JavaScript API:

**`create_node`:**
```javascript
const node = LiteGraph.createNode(params.type);  // Create the node object
node.pos = findFreePosition(targetX, targetY);    // Avoid collisions
if (params.title) node.title = params.title;
app.graph.add(node);                              // Add to canvas
app.graph.setDirtyCanvas(true, true);             // Trigger redraw
return { status: "created", node_id: node.id, pos: node.pos, size: node.size };
```

**`delete_node`:**
```javascript
const node = app.graph.getNodeById(nodeId);
app.graph.remove(node);
```

**`set_node_property`:**
```javascript
for (const widget of node.widgets) {
    if (widget.name === params.property_name) {
        widget.value = params.value;
        if (widget.callback) widget.callback(params.value, ...);
    }
}
```
Finds the widget by name (e.g., "steps", "cfg", "image") and sets its value. Calls the callback so the UI updates.

**`connect_nodes`:**
```javascript
const link = fromNode.connect(params.from_slot, toNode, params.to_slot);
```
LiteGraph's built-in method to wire two nodes together.

**`disconnect_nodes`:**
```javascript
const linkId = toNode.inputs[params.to_slot].link;
app.graph.removeLink(linkId);
```

**`move_node`:**
Supports both absolute positioning (`x, y`) and relative positioning (`relative_to: "5", direction: "below", gap: 30`).

**`queue_prompt`:**
```javascript
await app.queuePrompt(0, 1);
```
Queues the workflow from the frontend side (important — this uses the browser's `client_id`, so preview images show up in the UI).

**`get_workflow_api`:**
```javascript
const workflowApi = await app.graphToPrompt();
return { workflow_api: workflowApi };
```
Converts the visual graph to API format (the format ComfyUI's execution engine needs). This is called by the MCP server before queuing a prompt.

**`center_on_node`:**
```javascript
app.canvas.centerOnNode(node);
```
Pans the viewport to show a specific node.

**Collision avoidance (in `create_node`):**
```javascript
const findFreePosition = (startX, startY) => {
    const collider = checkCollision(x, y, nodeWidth, nodeHeight);
    if (!collider) return [x, y];
    // Try right, below, left, above — expanding outward
    for (let distance = 1; distance <= 10; distance++) {
        for (const [dx, dy] of directions) {
            const tryX = startX + dx * (nodeWidth + gap) * distance;
            if (!checkCollision(tryX, tryY, ...)) return [tryX, tryY];
        }
    }
};
```
When placing a new node, checks if it overlaps with existing nodes and nudges it to a free spot.

---

## Key Timings

| What | Interval | Purpose |
|------|----------|---------|
| Workflow sync | Every 2000ms | Keep backend's canvas state up to date |
| Command polling | Every 200ms | Pick up new commands from MCP server |
| Command execution | ~10-50ms | LiteGraph API calls are fast |
| Total roundtrip (Claude → canvas) | ~200-400ms | From tool call to visible change |
