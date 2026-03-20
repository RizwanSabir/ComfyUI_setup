# ComfyUI Workflow Explorer — Prompt for Claude

Copy everything below the line and paste it into Claude Code.

## How to Use

1. Place your ComfyUI workflow JSON in `input/input.json`
   - Export from ComfyUI: **Save (API Format)** for API format, or **Export** for frontend format
   - Both formats are supported automatically
2. Copy everything below the line
3. Paste into Claude Code
4. Claude will read the JSON, research each node type online, and generate `playground.html`
5. Open `playground.html` in your browser (just double-click — works with file:// protocol)
6. Click nodes to see details and copy prompts for deeper Q&A with Claude

---

```
Build a ComfyUI Workflow Explorer. Read the workflow JSON, research every node, and generate an interactive HTML playground.

## Step 1: Read and Parse the Workflow

Read the file `input/input.json`. This is a ComfyUI workflow JSON. It may be in one of two formats:

**Format detection:**
- If the JSON has a top-level `nodes` array → it's **frontend format**
  - Each node is in the `nodes` array with fields: `id`, `type` (this is the class_type), `pos`, `inputs`, `outputs`, `widgets_values`
  - Connections are in a separate `links` array: each link is `[linkId, originNodeId, originSlot, targetNodeId, targetSlot, type]`
  - Position data is in `pos: [x, y]` on each node
- If the JSON has numeric string keys at the top level (e.g., `"3"`, `"4"`) → it's **API format**
  - Each key is a node ID, value has `class_type` and `inputs`
  - Connections are encoded in inputs: `"model": ["4", 0]` means "input 'model' comes from node 4, output slot 0"
  - No position data — use auto-layout

Parse whichever format is detected into the same normalized structure.

For each node in the JSON:

- Extract the node ID (the key in the top-level object)
- Extract `class_type` — this is the node type name
- Extract all `inputs` — each input is either a static value OR a connection `[sourceNodeId, outputIndex]`
- Build a connection map: for every input that is an array `[id, index]`, record that this node receives data from node `id` at output slot `index`

Create a complete list of:
1. All unique node types (`class_type` values)
2. All connections between nodes (which node outputs feed into which node inputs)
3. All static input values per node

**For frontend format, build connections from the `links` array:**
Each link is `[linkId, originNodeId, originSlot, targetNodeId, targetSlot, type]`.
Map each link to: fromNode=originNodeId, fromOutput=originSlot, toNode=targetNodeId, toInput=targetSlot, type=type.
Use the node's `inputs` array to find the input name at `targetSlot`, and the `outputs` array for the output name at `originSlot`.

## Step 2: Research Each Node Type

For each unique `class_type` found in Step 1, use WebSearch to find:

- **What the node does** — 1-2 sentence description
- **Which package it belongs to** — built-in ComfyUI, or which custom node pack (e.g., ComfyUI-Easy-Use, was-node-suite, etc.)
- **Input types** — what each input expects (MODEL, CLIP, CONDITIONING, LATENT, IMAGE, INT, FLOAT, STRING, etc.)
- **Output types** — what each output produces
- **Key parameters** — what the important settings do (e.g., steps, cfg, seed for KSampler)

Search queries to try:
- `ComfyUI [class_type] node`
- `site:github.com ComfyUI [class_type]`
- `ComfyUI [class_type] inputs outputs`

If a node is a standard built-in ComfyUI node (like KSampler, CheckpointLoaderSimple, CLIPTextEncode, VAEDecode, EmptyLatentImage, SaveImage, etc.), you likely already know what it does — still confirm with a quick search.

For custom nodes, check these repos based on the installed custom_nodes.txt:
- ComfyUI-Manager (ltdrdata)
- ComfyUI-Crystools (crystian)
- ComfyUI-Easy-Use (yolain)
- ComfyUI-iTools (MohammadAboulEla)
- ComfyUI-Studio-nodes (comfyuistudio)
- was-node-suite-comfyui (WASasquatch)
- rgthree-comfy (rgthree)
- comfyui-kjnodes (kk8bit)

## Step 3: Generate playground.html

Generate a single HTML file at `playground.html` (project root) with everything inline (HTML + CSS + JS, no external dependencies). The file must contain all the researched data embedded as a JavaScript object.

### 3.1 Embedded Data Structure

At the top of the `<script>`, embed the parsed workflow data:

```javascript
const WORKFLOW_DATA = {
  nodes: {
    "4": {
      id: "4",
      type: "CheckpointLoaderSimple",
      category: "loader",          // one of: loader, sampler, encoder, conditioning, latent, image, utility
      description: "Loads a Stable Diffusion checkpoint model file...",  // from research
      package: "ComfyUI built-in",  // from research
      inputs: {
        ckpt_name: { value: "v1-5-pruned-emaonly.safetensors", type: "static" }
      },
      outputs: [
        { name: "MODEL", type: "MODEL" },
        { name: "CLIP", type: "CLIP" },
        { name: "VAE", type: "VAE" }
      ],
      position: [x, y],  // from the workflow JSON "pos" field if available, or auto-layout
      inputTypes: { ... },   // from research: what each input expects
      outputTypes: { ... },  // from research: what each output produces
      keyParams: "..."        // from research: what important settings do
    },
    // ... all other nodes
  },
  connections: [
    { fromNode: "4", fromOutput: 0, fromOutputName: "MODEL", toNode: "3", toInput: "model", type: "MODEL" },
    { fromNode: "4", fromOutput: 1, fromOutputName: "CLIP", toNode: "6", toInput: "clip", type: "CLIP" },
    // ... all connections
  ]
};
```

### 3.2 Layout — Top Bar

```
┌──────────────────────────────────────────────────────────────────────┐
│  ComfyUI Workflow Explorer    [Zoom +] [Zoom -] [Fit] [Reset]       │
└──────────────────────────────────────────────────────────────────────┘
```

- Title: "ComfyUI Workflow Explorer"
- Zoom buttons: Zoom In (+), Zoom Out (-), Fit All (fit all nodes in view), Reset (reset zoom/pan to default)
- Show total node count: "12 nodes"

### 3.3 Layout — Canvas Area (Main)

A pannable, zoomable area that displays all nodes as positioned divs with SVG connection lines.

**Panning:** Click and drag on empty canvas area to pan. Use a CSS `transform: translate(x, y) scale(z)` on a container div.

**Zooming:** Mouse wheel to zoom in/out. Zoom buttons in top bar. Min zoom 0.3, max zoom 2.0.

**Node positioning:**
- **Frontend format**: Use the `pos: [x, y]` from each node directly
- **API format**: No position data — auto-layout using topological sort (nodes with no inputs on the left, outputs on the right, 250px horizontal spacing, 150px vertical spacing per column)

**Each node div:**
```
┌─ #4 CheckpointLoaderSimple ─────────────┐
│  ckpt_name: "v1-5-pruned-ema..."        │
│                                          │
│  ● MODEL   ● CLIP   ● VAE              │
└──────────────────────────────────────────┘
```

- **Header**: `#nodeId class_type` — background colored by category
- **Body**: Show static input values (truncated to 30 chars with `...`)
- **Output dots**: Small colored circles on the right edge, one per output, labeled
- **Input dots**: Small colored circles on the left edge, one per connected input
- Width: 220px. Font: monospace, small.

**Node category colors (header background):**
- loader: `#3b82f6` (blue)
- sampler: `#8b5cf6` (purple)
- encoder: `#14b8a6` (teal)
- conditioning: `#f97316` (orange)
- latent: `#ec4899` (pink)
- image: `#22c55e` (green)
- utility: `#6b7280` (gray)

**Categorization rules:**
- `class_type` contains `Loader` or `Load` → loader
- `class_type` contains `Sampler` or `Sample` → sampler
- `class_type` contains `Encode` or `Encoder` or `CLIP` → encoder
- `class_type` contains `Conditioning` → conditioning
- `class_type` contains `Latent` or `Empty` → latent
- `class_type` contains `Image` or `Save` or `Preview` or `Decode` → image
- Everything else → utility

**Connection lines (SVG):**
- Draw bezier curves from output dots to input dots
- Curve shape: horizontal S-curve. Control points offset horizontally by 50% of the distance between nodes
- Color by data type:
  - MODEL: `#8b5cf6` (purple)
  - CLIP: `#eab308` (yellow)
  - LATENT: `#ec4899` (pink)
  - IMAGE: `#22c55e` (green)
  - CONDITIONING: `#f97316` (orange)
  - VAE: `#ef4444` (red)
  - Other/unknown: `#6b7280` (gray)
- Line width: 2px, with subtle opacity (0.6)
- Arrow head at the receiving (input) end — small triangle marker

**Interaction:**
- **Hover node**: Node gets a subtle bright border. All connection lines to/from this node glow (opacity 1.0, width 3px). Show a small tooltip with the node description (first sentence only).
- **Click node**: Node gets a bright accent border glow (`box-shadow: 0 0 12px var(--accent)`). All OTHER nodes and connections dim to 20% opacity. Bottom panel populates with this node's details. Clicking empty canvas deselects.
- **Hover connection line**: Line glows, tooltip shows "MODEL: CheckpointLoader → KSampler"

### 3.4 Layout — Bottom Panel (Details + Prompt)

Height: 280px default, resizable via drag handle (min 100px, max 500px).

**When no node selected:**
```
Click a node to see its details and generate prompts for Claude
```

**When a node is selected, show two sections:**

**Section A — Node Details:**
```
┌─────────────────────────────────────────────────────────────────┐
│  KSampler                                    Package: Built-in  │
│                                                                  │
│  Description: Runs the diffusion sampling process. Takes a      │
│  model, positive and negative conditioning, and a latent image, │
│  then iteratively denoises for the specified number of steps.   │
│                                                                  │
│  Inputs in this workflow:                                        │
│    model ← CheckpointLoaderSimple (#4) [MODEL]                  │
│    positive ← CLIPTextEncode (#6) [CONDITIONING]                │
│    negative ← CLIPTextEncode (#7) [CONDITIONING]                │
│    latent_image ← EmptyLatentImage (#5) [LATENT]                │
│    seed = 8566257                                                │
│    steps = 20                                                    │
│    cfg = 8.0                                                     │
│    sampler_name = "euler"                                        │
│    scheduler = "normal"                                          │
│    denoise = 1.0                                                 │
│                                                                  │
│  Outputs from this node:                                         │
│    LATENT → VAEDecode (#8)                                       │
└─────────────────────────────────────────────────────────────────┘
```

- Node name large and bold, accent colored
- Package source on the right
- Description from research (full text)
- Inputs: connected inputs show source node name, ID, and type in colored badge. Static inputs show key=value.
- Outputs: show type and which node(s) receive it

**Section B — Prompt Generator:**

Two toggle buttons: **[Quick]** and **[Deep]** (Deep is default)

```
┌─ Prompt for Claude ──────────────────────────────── [Copy] ─────┐
│                                                                  │
│  Explain the KSampler node in ComfyUI in detail:                │
│  - What is its purpose?                                          │
│  - Inputs: model (MODEL), positive (CONDITIONING), negative...  │
│  - Outputs: LATENT                                               │
│  - In my workflow it connects to:                                │
│    - Receives model from CheckpointLoaderSimple (#4)            │
│    - Receives positive from CLIPTextEncode (#6)                 │
│    ...                                                           │
│  - Parameters: seed=8566257, steps=20, cfg=8.0, ...             │
│  - What do steps, cfg, sampler_name, scheduler mean?            │
│  - Best practices and common settings?                          │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

**Quick prompt template:**
```
What does {class_type} do in ComfyUI?
In my workflow (node #{id}), it receives: {list of connected inputs with source node names}.
It outputs: {list of outputs with target node names}.
Static settings: {list of key=value pairs}.
Explain briefly what this node does and its role in the pipeline.
```

**Deep prompt template:**
```
Explain the {class_type} node in ComfyUI in detail:

This is node #{id} in my workflow.

**Inputs it receives:**
{For each connected input:}
- {inputName} ({type}) from {sourceNodeType} (#{sourceNodeId})
{For each static input:}
- {inputName} = {value}

**Outputs it produces:**
{For each output:}
- {outputName} ({type}) → goes to {targetNodeType} (#{targetNodeId})

Please explain:
1. What is this node's purpose?
2. What does each input parameter mean?
3. What does each output contain?
4. How do the settings ({list param names}) affect the result?
5. Common use cases and best practices
6. What happens if I change {key params like steps, cfg, seed, etc}?
7. How does it work together with {list connected node types} in this pipeline?
8. Any tips or common mistakes to avoid?
```

**[Copy] button**: Copies the generated prompt to clipboard. Shows "Copied!" feedback for 1.5s.

**Questions mode** — a third toggle: **[Quick]** **[Deep]** **[Questions]**

When "Questions" is selected, show a list of clickable question chips that generate targeted prompts:

For the selected node, show these question chips:
- **"What does this do?"** → generates: "What does {class_type} do in ComfyUI? Give me a simple explanation."
- **"Why is it connected this way?"** → generates: "In my ComfyUI workflow, {class_type} (#{id}) receives {inputs} and sends output to {targets}. Why is it connected this way? What would happen if I changed the connections?"
- **"Best settings?"** → generates: "What are the best settings for {class_type} in ComfyUI? Currently set to: {list param=value}. What should I change for better results?"
- **"Alternatives?"** → generates: "What are alternative nodes I could use instead of {class_type} in ComfyUI? What are the trade-offs?"
- **"Common mistakes?"** → generates: "What are common mistakes when using {class_type} in ComfyUI? What should I watch out for?"
- **"ELI5"** → generates: "Explain {class_type} in ComfyUI like I'm 5 years old. What does it do in simple terms?"

Each chip, when clicked, populates the prompt box below with the generated text + shows the [Copy] button.

**Visual:** Question chips are pill-shaped buttons with subtle border, arranged in a flex-wrap row. Active chip gets accent background. The generated prompt appears in the same prompt box used by Quick/Deep modes.

### 3.5 Dark Theme CSS

```css
:root {
  --bg: #0d1117;
  --panel: #161b22;
  --border: #30363d;
  --text: #c9d1d9;
  --text-muted: #8b949e;
  --text-bright: #f0f6fc;
  --accent: #58a6ff;
  --card-bg: #1c2128;
  --hover: #21262d;
}
```

- Monospace font stack: `'SF Mono', 'Cascadia Code', 'Fira Code', 'Consolas', monospace`
- Rounded corners: 8px on cards, 5px on buttons
- Smooth transitions: 0.15s
- Scrollbar: thin 6px, matching border color
- Canvas background: subtle dot grid pattern (`radial-gradient` dots every 20px, very faint)

### 3.6 Key Implementation Notes

- **Single file**: Everything inline — HTML, CSS, JS. No external dependencies.
- **SVG for lines**: Use an SVG element that sits behind the node divs but inside the same pannable/zoomable container. Nodes are `position: absolute` divs.
- **Pan/zoom**: Apply `transform: translate(panX, panY) scale(zoom)` to a container div. Mouse wheel for zoom, mouse drag on empty space for pan.
- **Fit button**: Calculate bounding box of all nodes, set zoom and pan to fit them all in the viewport with 50px padding.
- **Responsive bottom panel**: Drag handle between canvas and panel, mousedown/mousemove/mouseup, clamp height 100-500px.
- **Node positions**: Use workflow JSON positions if available. If not, run a simple left-to-right topological layout.
- **Connection dot positions**: Calculate based on the node div's position + offset for each input/output slot.

### 3.7 "Explain All Nodes" Feature

Add an **[Explain All Nodes]** button in the top bar, next to the node count.

When clicked, generate a comprehensive prompt covering ALL nodes in the workflow:

**Template:**
```
I have a ComfyUI workflow with {N} nodes. Please explain each node and how they work together:

**Workflow nodes:**
{For each node, ordered by connection flow (topological order):}

{N}. **{class_type}** (#{id})
   - Inputs: {list connected + static inputs}
   - Outputs: {list outputs with target nodes}

**Please explain:**
1. What does each node do?
2. How do they connect together — what is the data flow from start to finish?
3. What is the overall purpose of this workflow?
4. Are there any alternative nodes or settings I could use?
5. What are the key parameters I should experiment with?
```

The [Explain All Nodes] button should also have a [Copy] button next to it. Same "Copied!" feedback as the per-node copy.

**Workflow-level question chips:**

When no specific node is selected, show these clickable question chips in the bottom panel (in addition to the [Explain All Nodes] button in the top bar):

- **"Workflow overview"** → "Give me a high-level overview of this ComfyUI workflow. What does it do from start to finish? Nodes: {list all nodes with types}"
- **"Optimize this workflow"** → "Here is my ComfyUI workflow: {list all nodes with connections}. How can I optimize it for better quality or speed?"
- **"What's missing?"** → "Here is my ComfyUI workflow: {list all nodes}. Are there any useful nodes I should add? What's missing?"
- **"Explain the data flow"** → "Trace the data flow through my ComfyUI workflow step by step: {list nodes in topological order with connections between them}"

These chips appear in the bottom panel when no node is selected, replacing the placeholder text.

## Important

- The output `playground.html` must be completely self-contained — all data, styles, and scripts inline
- Do NOT use any CDN links, external libraries, or fetch calls
- All node research data must be embedded as JavaScript objects in the HTML
- The file should work by simply opening it in any browser (`file:///` protocol)
- Make sure SVG connection lines render correctly with the pan/zoom transform

## Verification

After generating playground.html, verify:
1. Open it in a browser — all nodes should render as positioned divs
2. SVG connection lines should connect the correct nodes with colored bezier curves
3. Click each node — bottom panel should show description, inputs, outputs, and prompt
4. [Copy] button should copy prompt to clipboard
5. [Quick], [Deep], [Questions] toggles should show different prompt formats
6. Question chips in Questions mode should generate targeted prompts
7. [Explain All Nodes] button should generate the full workflow prompt
8. Workflow-level question chips should appear when no node is selected
9. Zoom (mouse wheel) and pan (drag empty space) should work smoothly
10. [Fit] button should fit all nodes in view with padding
```
