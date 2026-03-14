#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

#############################################
# Load config
#############################################

if [ -f "$SCRIPT_DIR/.env-config" ]; then
    source "$SCRIPT_DIR/.env-config"
else
    echo "ERROR: .env-config not found in $SCRIPT_DIR"
    exit 1
fi

#############################################
# Verify shared drive is mounted
#############################################

if ! mountpoint -q "$SHARE_DIR" 2>/dev/null; then
    # Fallback: check for a known file on the drive
    if [ ! -f "$SCRIPT_DIR/.env-config" ]; then
        echo "ERROR: $SHARE_DIR does not appear to be mounted."
        echo "Mount the shared drive first, then re-run this script."
        exit 1
    fi
fi

echo "===== VPS Setup Starting ====="
echo "Shared drive: $SHARE_DIR"

#############################################
# Migrate & symlink Claude credentials FIRST
# (must happen before Claude Code runs)
#############################################

# Create credentials dir on shared drive if needed
if [ ! -d "$CLAUDE_CREDS_DIR" ]; then
    echo "Creating credentials directory at $CLAUDE_CREDS_DIR..."
    sudo mkdir -p "$CLAUDE_CREDS_DIR"
    sudo chown "$(id -u):$(id -g)" "$CLAUDE_CREDS_DIR"
fi

# If ~/.claude exists and is NOT a symlink, migrate its contents
if [ -d "$HOME/.claude" ] && [ ! -L "$HOME/.claude" ]; then
    echo "Migrating existing ~/.claude to shared drive..."
    BACKUP_NAME="$HOME/.claude.backup.$(date +%Y%m%d%H%M%S)"
    cp -a "$HOME/.claude" "$BACKUP_NAME"
    echo "Backup created at $BACKUP_NAME"

    # Copy contents to shared drive (don't overwrite existing files)
    cp -a -n "$HOME/.claude/." "$CLAUDE_CREDS_DIR/"
    rm -rf "$HOME/.claude"
fi

# Create symlink if not already correct
if [ -L "$HOME/.claude" ]; then
    CURRENT_TARGET="$(readlink -f "$HOME/.claude")"
    EXPECTED_TARGET="$(readlink -f "$CLAUDE_CREDS_DIR")"
    if [ "$CURRENT_TARGET" = "$EXPECTED_TARGET" ]; then
        echo "~/.claude symlink already correct."
    else
        echo "Updating ~/.claude symlink..."
        rm "$HOME/.claude"
        ln -s "$CLAUDE_CREDS_DIR" "$HOME/.claude"
        echo "~/.claude -> $CLAUDE_CREDS_DIR"
    fi
else
    ln -s "$CLAUDE_CREDS_DIR" "$HOME/.claude"
    echo "~/.claude -> $CLAUDE_CREDS_DIR"
fi

#############################################
# Install git if not present
#############################################

if command -v git >/dev/null 2>&1; then
    echo "Git already installed: $(git --version)"
else
    echo "Installing Git..."
    sudo apt-get update -qq
    sudo apt-get install -y git
    echo "Git installed: $(git --version)"
fi

#############################################
# Install Node.js if not present
#############################################

if command -v node >/dev/null 2>&1; then
    echo "Node.js already installed: $(node --version)"
else
    echo "Installing Node.js ${NODE_VERSION}.x..."
    curl -fsSL "https://deb.nodesource.com/setup_${NODE_VERSION}.x" | sudo -E bash -
    sudo apt-get install -y nodejs
    echo "Node.js installed: $(node --version)"
fi

#############################################
# Install Claude Code CLI on shared drive
#############################################

CLAUDE_INSTALL_DIR="$SHARE_DIR/claude-code"

if [ -f "$CLAUDE_INSTALL_DIR/node_modules/.bin/claude" ]; then
    echo "Claude Code already installed on shared drive."
else
    echo "Installing Claude Code CLI to $CLAUDE_INSTALL_DIR..."
    sudo mkdir -p "$CLAUDE_INSTALL_DIR"
    sudo chown "$(id -u):$(id -g)" "$CLAUDE_INSTALL_DIR"
    cd "$CLAUDE_INSTALL_DIR"
    npm init -y >/dev/null 2>&1
    npm install @anthropic-ai/claude-code
    cd "$SCRIPT_DIR"
    echo "Claude Code installed on shared drive."
fi

export PATH="$CLAUDE_INSTALL_DIR/node_modules/.bin:$PATH"

#############################################
# Install Miniconda on shared drive if not present
#############################################

export PATH="$CONDA_DIR/bin:$PATH"

if [ -d "$CONDA_DIR/bin" ]; then
    echo "Miniconda already installed on shared drive."
else
    echo "Installing Miniconda to $CONDA_DIR..."
    wget -q https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O /tmp/miniconda.sh
    sudo bash /tmp/miniconda.sh -b -p "$CONDA_DIR"
    sudo chown -R "$(id -u):$(id -g)" "$CONDA_DIR"
    rm /tmp/miniconda.sh
    echo "Miniconda installed."
fi

#############################################
# Install NVIDIA drivers and CUDA toolkit
#############################################

if command -v nvidia-smi >/dev/null 2>&1; then
    echo "NVIDIA driver already installed:"
    nvidia-smi --query-gpu=driver_version,name --format=csv,noheader
else
    echo "Installing NVIDIA drivers..."
    sudo apt-get update -qq
    sudo apt-get install -y ubuntu-drivers-common
    sudo ubuntu-drivers install
    echo "NVIDIA driver installed. A reboot may be required."
fi

if command -v nvcc >/dev/null 2>&1; then
    echo "CUDA toolkit already installed: $(nvcc --version | grep 'release' | awk '{print $6}')"
else
    echo "Installing CUDA toolkit..."
    sudo apt-get update -qq
    sudo apt-get install -y nvidia-cuda-toolkit
    echo "CUDA toolkit installed."
fi

#############################################
# Accept Conda TOS
#############################################

echo "Accepting Conda Terms of Service..."
"$CONDA_DIR/bin/conda" tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main 2>/dev/null || true
"$CONDA_DIR/bin/conda" tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r 2>/dev/null || true

#############################################
# Done
#############################################

echo ""
echo "===== VPS Setup Complete ====="
echo ""
echo "Next steps:"
echo "  source $SHARE_DIR/activate.sh"
echo "  conda activate <env_name>"
echo ""
