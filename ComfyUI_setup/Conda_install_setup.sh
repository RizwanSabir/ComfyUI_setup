#!/bin/bash

set -e

echo "===== Starting Setup ====="

#############################################
# Variables
#############################################

CONDA_DIR="$HOME/workspace/ComfyUI-setup/miniconda"
ENV_NAME="comfy"

#############################################
# Add Conda to PATH (IMPORTANT)
#############################################

export PATH="$CONDA_DIR/bin:$PATH"

if [ -f "$CONDA_DIR/etc/profile.d/conda.sh" ]; then
    source "$CONDA_DIR/etc/profile.d/conda.sh"
fi

#############################################
# Install Miniconda if Missing
#############################################

if [ ! -d "$CONDA_DIR/bin" ]; then
    echo "Installing Miniconda..."

    wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O miniconda.sh

    bash miniconda.sh -b -p "$CONDA_DIR"

    rm miniconda.sh
else
    echo "Miniconda already installed ✔"
fi

#############################################
# Accept Conda TOS
#############################################

echo "Accepting Conda Terms of Service..."

$CONDA_DIR/bin/conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main || true
$CONDA_DIR/bin/conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r || true

#############################################
# Verify Conda
#############################################

if ! command -v conda >/dev/null 2>&1; then
    echo "Conda not working"
    exit 1
fi

echo "Conda working ✔"

#############################################
# Create Environment
#############################################

if conda env list | grep -q "$ENV_NAME"; then
    echo "Environment exists → Activating"
else
    echo "Creating environment..."
    conda create -n $ENV_NAME python=3.13 -y
fi

echo "Activating environment..."
source activate $ENV_NAME || conda activate $ENV_NAME

