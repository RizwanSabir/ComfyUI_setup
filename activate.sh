#!/bin/bash
#
# Source this file to activate conda from the shared drive:
#   source /data/share78/activate.sh
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load config
if [ -f "$SCRIPT_DIR/.env-config" ]; then
    source "$SCRIPT_DIR/.env-config"
else
    echo "ERROR: .env-config not found in $SCRIPT_DIR"
    return 1 2>/dev/null || exit 1
fi

# Verify conda exists
if [ ! -f "$CONDA_DIR/bin/conda" ]; then
    echo "ERROR: Conda not found at $CONDA_DIR"
    echo "Run 'bash $SHARE_DIR/setup-vps.sh' first."
    return 1 2>/dev/null || exit 1
fi

# Add Claude Code to PATH (from shared drive)
CLAUDE_INSTALL_DIR="$SHARE_DIR/claude-code"
if [ -d "$CLAUDE_INSTALL_DIR/node_modules/.bin" ]; then
    export PATH="$CLAUDE_INSTALL_DIR/node_modules/.bin:$PATH"
fi

# Add conda to PATH
export PATH="$CONDA_DIR/bin:$PATH"

# Source conda shell integration
if [ -f "$CONDA_DIR/etc/profile.d/conda.sh" ]; then
    source "$CONDA_DIR/etc/profile.d/conda.sh"
fi

# Confirmation
echo "Conda activated: $(conda --version)"
echo ""
echo "Available environments:"
conda env list 2>/dev/null | grep -v "^#" | grep -v "^$"
echo ""
echo "Use: conda activate <env_name>"
