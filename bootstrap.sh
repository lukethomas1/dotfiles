#!/bin/bash
set -euo pipefail

# Dotfiles bootstrap — detects OS and installs chezmoi + dependencies
# Usage: ./bootstrap.sh
# Or:    curl -sSL <raw-url>/bootstrap.sh | bash

REPO="lukethomas1/dotfiles"
OS="$(uname -s)"

echo "Detected OS: ${OS}"

case "$OS" in
  Darwin)
    # macOS
    command -v brew >/dev/null || {
      echo "Installing Homebrew..."
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
      eval "$(/opt/homebrew/bin/brew shellenv)"
    }
    brew install chezmoi age
    export CHEZMOI_ROLE="macos"
    ;;
  Linux)
    if [ -f /etc/arch-release ]; then
      # Arch / CachyOS
      sudo pacman -S --needed --noconfirm chezmoi age
      export CHEZMOI_ROLE="arch"
    elif [ -f /etc/debian_version ]; then
      # Debian container — chezmoi should already be installed via Dockerfile
      if ! command -v chezmoi >/dev/null; then
        echo "ERROR: chezmoi not found. Install it first (should be in Dockerfile)."
        exit 1
      fi
      # Install fish + starship for full dev experience
      if ! command -v fish >/dev/null; then
        sudo apt-get update && sudo apt-get install -y fish
      fi
      if ! command -v starship >/dev/null; then
        curl -sS https://starship.rs/install.sh | sh -s -- -y
      fi
      export CHEZMOI_ROLE="container"
    else
      echo "ERROR: Unsupported Linux distro"
      exit 1
    fi
    ;;
  *)
    echo "ERROR: Unsupported OS: ${OS}"
    exit 1
    ;;
esac

echo "Role: ${CHEZMOI_ROLE}"

# Check for age key (not required for containers)
if [ ! -f ~/.config/chezmoi/key.txt ]; then
  if [ "${CHEZMOI_ROLE}" = "container" ]; then
    echo "No age key found — skipping secrets (container profile)."
  else
    echo "ERROR: Age key not found at ~/.config/chezmoi/key.txt"
    echo "Copy your key from a secure source, then re-run."
    exit 1
  fi
fi

# Init + apply
if [ -d ~/.local/share/chezmoi/.git ]; then
  echo "Updating dotfiles..."
  chezmoi update
else
  echo "Initializing dotfiles..."
  chezmoi init --apply "${REPO}"
fi

# Install packages (skip for containers — Dockerfile handles it)
if [ "${CHEZMOI_ROLE}" = "macos" ]; then
  echo "Installing Homebrew packages..."
  brew bundle --file="$(chezmoi source-path)/pkg/macos/Brewfile"
  # npm globals (not available via brew)
  if command -v npm >/dev/null; then
    echo "Installing npm globals..."
    npm install -g @devcontainers/cli 2>/dev/null || sudo npm install -g @devcontainers/cli
  fi
elif [ "${CHEZMOI_ROLE}" = "arch" ]; then
  echo "Installing pacman packages..."
  sudo pacman -S --needed - < "$(chezmoi source-path)/pkg/arch/pacman-arch.txt"
  if command -v paru >/dev/null; then
    echo "Installing AUR packages..."
    paru -S --needed - < "$(chezmoi source-path)/pkg/arch/aur-arch.txt"
  else
    echo "WARN: paru not found, skipping AUR packages"
  fi
fi

echo ""
echo "Done! Restart your shell or run: exec fish"
