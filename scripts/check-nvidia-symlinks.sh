#!/usr/bin/env bash
# ============================================================================
# NVIDIA /dev/char/ Symlink Check
#
# Checks if /dev/char/ symlinks exist for NVIDIA devices. Without these,
# long-running containers lose GPU access when the host runs
# "systemctl daemon-reload" (triggered by automatic package updates, etc.).
#
# This is NVIDIA's official workaround using nvidia-ctk.
# See: https://github.com/NVIDIA/nvidia-container-toolkit/issues/48
#
# Usage:
#   bash scripts/check-nvidia-symlinks.sh          # Check only
#   sudo bash scripts/check-nvidia-symlinks.sh --fix  # Check and fix
# ============================================================================

set -euo pipefail

FIX_MODE=false
if [[ "${1:-}" == "--fix" ]]; then
    FIX_MODE=true
fi

# Skip silently if no NVIDIA GPU
if ! command -v nvidia-smi &> /dev/null; then
    exit 0
fi

# Check if symlinks exist
if ls /dev/char/195:* &> /dev/null 2>&1; then
    echo "[GPU] /dev/char/ symlinks: OK"
    exit 0
fi

# --- Symlinks missing ---

if $FIX_MODE; then
    if [[ $EUID -ne 0 ]]; then
        echo "ERROR: --fix requires root. Run: sudo bash $0 --fix"
        exit 1
    fi
    if ! command -v nvidia-ctk &> /dev/null; then
        echo "ERROR: nvidia-ctk not found. Install NVIDIA Container Toolkit first."
        exit 1
    fi

    echo "[GPU] Creating /dev/char/ symlinks..."
    nvidia-ctk system create-dev-char-symlinks --create-all

    echo "[GPU] Creating udev rule for persistence..."
    echo 'ACTION=="add", DEVPATH=="/bus/pci/drivers/nvidia", RUN+="/usr/bin/nvidia-ctk system create-dev-char-symlinks --create-all"' \
        > /lib/udev/rules.d/71-nvidia-dev-char.rules
    udevadm control --reload-rules

    echo "[GPU] Done. Verify: ls /dev/char/195:*"
    exit 0
fi

# --- Warning mode ---

cat <<'MESSAGE'

================================================================
  WARNING: NVIDIA /dev/char/ symlinks not found
================================================================

  Long-running GPU containers will lose GPU access when the host
  runs "systemctl daemon-reload" (triggered automatically by
  package updates, logrotate, etc.).

  This is a known Docker + systemd cgroup v2 issue.
  NVIDIA provides an official fix via nvidia-ctk.

  Run this command on the HOST (not inside the container):

    sudo nvidia-ctk system create-dev-char-symlinks --create-all

  To persist across host reboots, also run:

    echo 'ACTION=="add", DEVPATH=="/bus/pci/drivers/nvidia", RUN+="/usr/bin/nvidia-ctk system create-dev-char-symlinks --create-all"' \
      | sudo tee /lib/udev/rules.d/71-nvidia-dev-char.rules
    sudo udevadm control --reload-rules

  Or use the shortcut:

    sudo bash scripts/check-nvidia-symlinks.sh --fix

  Details: https://github.com/NVIDIA/nvidia-container-toolkit/issues/48

================================================================

MESSAGE
