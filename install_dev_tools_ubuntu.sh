#!/usr/bin/env bash
# ------------------------------
# Ubuntu Development Environment Setup Script
# Installs common development tools on a fresh Ubuntu machine:
#   * Docker Desktop + Docker Compose plugin
#   * Python 3 (latest available via apt) & pip
#   * NVM (Node Version Manager) + latest LTS Node.js
#   * Rust toolchain via rustup
#   * Git
#   * Surfshark VPN client
#
# Usage:
#   sudo bash install_dev_tools_ubuntu.sh
# ------------------------------------------

set -euo pipefail

# --- Helper functions ---------------------------------------------------------
log()    { printf "\033[1;32m[INFO] %s\033[0m\n" "$*"; }
warn()   { printf "\033[1;33m[WARN] %s\033[0m\n" "$*"; }
error()  { printf "\033[1;31m[ERROR] %s\033[0m\n" "$*"; }

require_root() {
  if [[ $EUID -ne 0 ]]; then
    error "This script must be run with root privileges. Try: sudo $0"
    exit 1
  fi
}

su_exec() {
  # Execute a command as the invoking (non-root) user if script is run with sudo.
  # Falls back to root when no SUDO_USER is present (e.g., real root session).
  local user=${SUDO_USER:-root}
  sudo -u "$user" bash -c "$1"
}

nvm_available() {
  su_exec '[ -s "$HOME/.nvm/nvm.sh" ] && . "$HOME/.nvm/nvm.sh" && command -v nvm >/dev/null 2>&1'
}

rustup_available() {
  su_exec '[ -x "$HOME/.cargo/bin/rustup" ] || command -v rustup >/dev/null 2>&1'
}

# -----------------------------------------------------------------------------
require_root

log "Updating package index & installing prerequisites..."
apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  build-essential curl ca-certificates gnupg lsb-release \
  software-properties-common apt-transport-https

# --- Core packages ------------------------------------------------------------
log "Installing Git, Python 3, and related tooling..."
DEBIAN_FRONTEND=noninteractive apt-get install -y git python3 python3-pip python3-venv

# --- Rust ---------------------------------------------------------------------
if ! rustup_available; then
  log "Installing Rust toolchain (rustup)..."
  su_exec "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path"
else
  warn "Rust already installed; skipping rustup installation."
fi

# --- NVM + Node ---------------------------------------------------------------
if ! nvm_available; then
  log "Installing NVM (Node Version Manager)..."
  su_exec "curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.5/install.sh | bash"
fi

# shellcheck disable=SC2016
su_exec '[ -s "$HOME/.nvm/nvm.sh" ] || { echo "nvm.sh not found after installation"; exit 1; }; . "$HOME/.nvm/nvm.sh" && nvm install --lts && nvm alias default lts/* && nvm use default'

# --- Docker Desktop -----------------------------------------------------------
log "Adding Docker APT repository & GPG key..."
arch=$(dpkg --print-architecture)
if [[ "$arch" != "amd64" ]]; then
  error "Docker Desktop for Ubuntu requires x86-64/amd64. Detected architecture: $arch"
  exit 1
fi

install -m 0755 -d /etc/apt/keyrings
if [[ ! -f /etc/apt/keyrings/docker.asc ]]; then
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
fi

codename=$(lsb_release -cs)
repo="deb [arch=$arch signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $codename stable"
if ! grep -q "^$repo" /etc/apt/sources.list.d/docker.list 2>/dev/null; then
  echo "$repo" | tee /etc/apt/sources.list.d/docker.list >/dev/null
fi

apt-get update -y

log "Downloading Docker Desktop DEB package..."
docker_desktop_deb=$(mktemp --suffix=.deb)
trap 'rm -f "$docker_desktop_deb"' EXIT
curl -fL https://desktop.docker.com/linux/main/amd64/docker-desktop-amd64.deb -o "$docker_desktop_deb"

log "Installing Docker Desktop from downloaded DEB package (this may take a while)..."
DEBIAN_FRONTEND=noninteractive apt-get install -y "$docker_desktop_deb" || {
  error "Docker Desktop installation failed. See log above."; exit 1; }

# Allow the invoking user to run Docker without sudo
if getent group docker >/dev/null 2>&1; then
  su_user=${SUDO_USER:-}
  if [[ -n "$su_user" ]]; then
    log "Adding $su_user to the docker group..."
    usermod -aG docker "$su_user"
  fi
fi

# --- Surfshark VPN ------------------------------------------------------------
log "Installing Surfshark VPN client..."
# Official script handles Debian-based distros (incl. Ubuntu)
su_exec "curl -f https://downloads.surfshark.com/linux/debian-install.sh --output ~/surfshark-install.sh"
su_exec "bash ~/surfshark-install.sh --quiet"

# --- Final notes --------------------------------------------------------------
log "All requested tools have been installed."
warn "For group membership changes to take effect, please log out & back in (or reboot)." 
