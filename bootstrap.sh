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
    # Make zsh the default login shell. /bin/zsh ships with macOS and is
    # always in /etc/shells. chsh prompts for a password; skip if zsh is
    # already the login shell.
    if [ "$(dscl . -read "/Users/${USER}" UserShell 2>/dev/null | awk '{print $2}')" != "/bin/zsh" ]; then
      echo "Setting default shell to /bin/zsh (enter your password if prompted)..."
      chsh -s /bin/zsh || echo "WARN: chsh failed — run 'chsh -s /bin/zsh' manually."
    fi
    ;;
  Linux)
    if [ -f /etc/arch-release ]; then
      # Arch / CachyOS
      sudo pacman -S --needed --noconfirm chezmoi age
      export CHEZMOI_ROLE="arch"
    elif grep -q 'cosmic-atomic\|rpm-ostree' /etc/os-release 2>/dev/null; then
      # Fedora COSMIC Atomic (or other rpm-ostree immutable desktops)
      # Install chezmoi as standalone binary
      if ! command -v chezmoi >/dev/null; then
        echo "Installing chezmoi..."
        sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$HOME/.local/bin"
      fi
      # Install age via brew (Linuxbrew) or standalone
      if ! command -v age >/dev/null; then
        if command -v brew >/dev/null; then
          brew install age
        else
          echo "Installing Homebrew (needed for CLI tools on immutable distros)..."
          /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
          eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
          brew install age
        fi
      fi
      export CHEZMOI_ROLE="fedora"
    elif [ -f /etc/debian_version ]; then
      # Debian container — chezmoi should already be installed via Dockerfile
      if ! command -v chezmoi >/dev/null; then
        echo "ERROR: chezmoi not found. Install it first (should be in Dockerfile)."
        exit 1
      fi
      # Install zsh + starship for full dev experience
      if ! command -v zsh >/dev/null; then
        sudo apt-get update && sudo apt-get install -y zsh
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
  sudo pacman -S --needed - < "$(chezmoi source-path)/pkg/arch/pacman-desktop.txt"
  if command -v paru >/dev/null; then
    echo "Installing AUR packages..."
    paru -S --needed - < "$(chezmoi source-path)/pkg/arch/aur-desktop.txt"
  else
    echo "WARN: paru not found, skipping AUR packages"
  fi
elif [ "${CHEZMOI_ROLE}" = "fedora" ]; then
  echo "Installing CLI tools via Homebrew (Linuxbrew)..."
  # Ensure brew is available
  if ! command -v brew >/dev/null; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
  fi
  if command -v brew >/dev/null; then
    xargs brew install < "$(chezmoi source-path)/pkg/fedora/brew.txt"
  else
    echo "WARN: brew not found, install CLI tools manually"
  fi
fi

echo ""
echo "Done! Restart your shell or run: exec zsh"
echo "(First zsh launch clones antidote + plugins — give it a few seconds.)"
