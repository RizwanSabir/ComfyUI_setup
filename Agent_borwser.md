# Agent Browser Setup Prompt for AI

Copy and paste the following prompt to any AI agent to set up agent-browser in this project:

---

## PROMPT START

You are setting up **agent-browser** — a headless/GUI browser automation CLI for AI agents — in the current project directory.

### Step 1: Install the Package

```bash
npm install agent-browser
```

### Step 2: Install Chromium Browser

```bash
npx agent-browser install
```

On Linux, also install system dependencies (requires sudo):

```bash
sudo npx agent-browser install --with-deps
# OR manually:
sudo npx playwright install-deps chromium
```

### Step 3: Install the Skill for Claude Code

```bash
npx skills add vercel-labs/agent-browser --project --yes --skill agent-browser
```

This installs the skill to `.agents/skills/agent-browser/` and symlinks it into `.claude/skills/`.

### Step 4: Create Project Config

Create `agent-browser.json` in the project root with these defaults:

```json
{
  "headed": true
}
```

This makes GUI mode the default so the browser window is always visible.

### Step 5: Verify Installation

Run these commands to confirm everything works:

```bash
# Open a test page in GUI mode
npx agent-browser --headed open https://example.com

# Take a screenshot
npx agent-browser screenshot test.png

# Get the accessibility tree (shows clickable elements with @refs)
npx agent-browser snapshot

# Close the browser
npx agent-browser close
```

### How to Use agent-browser

#### Opening Pages
```bash
npx agent-browser --headed open <url>        # GUI mode (visible window)
npx agent-browser open <url>                  # Headless mode (no window)
```

#### Finding Elements
```bash
npx agent-browser snapshot                    # Get accessibility tree with @refs
```

#### Interacting with Elements
```bash
npx agent-browser click @e2                   # Click element by ref
npx agent-browser fill @e3 "text"             # Fill input field
npx agent-browser type @e3 "text"             # Type into element
npx agent-browser select @e4 "option"         # Select dropdown
npx agent-browser check @e5                   # Check checkbox
npx agent-browser press Enter                 # Press keyboard key
npx agent-browser hover @e2                   # Hover over element
```

#### Scrolling
```bash
npx agent-browser scroll down 500             # Scroll down 500px
npx agent-browser scroll up 300               # Scroll up 300px
npx agent-browser scroll left 200
npx agent-browser scroll right 200
```

#### Screenshots & Info
```bash
npx agent-browser screenshot page.png         # Screenshot
npx agent-browser screenshot page.png --full-page  # Full page screenshot
npx agent-browser pdf output.pdf              # Save as PDF
npx agent-browser get text                    # Get page text
npx agent-browser get html                    # Get page HTML
npx agent-browser get title                   # Get page title
npx agent-browser get url                     # Get current URL
```

#### Navigation
```bash
npx agent-browser back                        # Go back
npx agent-browser forward                     # Go forward
npx agent-browser reload                      # Reload page
```

#### Mouse Control (for iframes/captchas not in accessibility tree)
```bash
npx agent-browser mouse move 215 336          # Move mouse to coordinates
npx agent-browser mouse down                  # Mouse button down
npx agent-browser mouse up                    # Mouse button up
npx agent-browser mouse wheel 100             # Scroll wheel
```

#### Tabs
```bash
npx agent-browser tab list                    # List open tabs
npx agent-browser tab new                     # New tab
npx agent-browser tab 2                       # Switch to tab 2
npx agent-browser tab close                   # Close current tab
```

#### JavaScript Execution
```bash
npx agent-browser eval "document.title"
npx agent-browser eval "document.querySelector('#myElement').textContent"
```

#### Session Management
```bash
npx agent-browser close                       # Close browser session
```

#### Authentication / Cookies
```bash
npx agent-browser cookies get                 # Get all cookies
npx agent-browser cookies set --name "key" --value "val" --domain "example.com"
npx agent-browser cookies clear               # Clear all cookies
npx agent-browser storage local get           # Get localStorage
```

#### Network
```bash
npx agent-browser network requests            # View network requests
npx agent-browser set headers '{"Authorization": "Bearer token"}'
npx agent-browser set credentials user pass   # HTTP Basic Auth
```

### Environment Variables (Optional)

```bash
export AGENT_BROWSER_SESSION=default           # Default session name
export AGENT_BROWSER_DEFAULT_TIMEOUT=30000     # Timeout in ms
export AGENT_BROWSER_ALLOWED_DOMAINS=example.com  # Domain allowlist
```

### Workflow Pattern for AI Agents

Always follow this pattern when automating browser tasks:

1. **Open** the page: `npx agent-browser --headed open <url>`
2. **Snapshot** to discover elements: `npx agent-browser snapshot`
3. **Screenshot** to visually verify: `npx agent-browser screenshot /tmp/page.png`
4. **Interact** using refs from snapshot: `npx agent-browser click @e2`
5. **Snapshot again** after each interaction to get updated refs
6. **Close** when done: `npx agent-browser close`

> Refs like `@e2` change after every page navigation or DOM update. Always take a fresh `snapshot` before interacting.

## PROMPT END
