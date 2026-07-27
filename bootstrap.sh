#!/bin/bash
set -euo pipefail

# Dotfiles bootstrap — detects OS and installs chezmoi + dependencies
# Usage: ./bootstrap.sh [--dry-run]
# Or:    curl -sSL <raw-url>/bootstrap.sh | bash

REPO="lukethomas1/dotfiles"
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
DRY_RUN=false

usage() {
  cat <<'EOF'
Usage: ./bootstrap.sh [--dry-run]

  --dry-run  Detect the profile and print the bootstrap, package, and shell
             actions without installing, downloading, applying dotfiles, or
             changing the login shell.
EOF
}

case "${1:-}" in
  "")
    ;;
  --dry-run|-n)
    DRY_RUN=true
    ;;
  --help|-h)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

if [ "$#" -gt 1 ]; then
  usage >&2
  exit 2
fi

dry_run_source_dir() {
  if [ -d "${SCRIPT_DIR}/pkg" ]; then
    printf '%s\n' "${SCRIPT_DIR}"
  elif [ -d "${HOME}/.local/share/chezmoi/pkg" ]; then
    printf '%s\n' "${HOME}/.local/share/chezmoi"
  else
    printf '\n'
  fi
}

dry_run_manifest() {
  local command_prefix="$1"
  local manifest="$2"

  if [ ! -f "${manifest}" ]; then
    echo "  ${command_prefix} <packages from ${manifest}>"
    return
  fi

  sed '/^[[:space:]]*#/d; /^[[:space:]]*$/d' "${manifest}" | \
    while IFS= read -r package; do
      echo "  ${command_prefix} ${package}"
    done
}

install_arch_1password_cli() {
  local source_dir="$1"
  local version_file="${source_dir}/pkg/arch/1password-cli.version"
  local version
  local arch
  local target="/usr/local/bin/op"

  if [ ! -f "${version_file}" ]; then
    echo "ERROR: 1Password CLI version file not found: ${version_file}" >&2
    exit 1
  fi

  version="$(tr -d '[:space:]' < "${version_file}")"
  case "${version}" in
    [0-9]*.[0-9]*.[0-9]*)
      ;;
    *)
      echo "ERROR: Invalid 1Password CLI version: ${version}" >&2
      exit 1
      ;;
  esac

  case "$(uname -m)" in
    x86_64)
      arch="amd64"
      ;;
    aarch64)
      arch="arm64"
      ;;
    *)
      echo "ERROR: Unsupported architecture for 1Password CLI: $(uname -m)" >&2
      exit 1
      ;;
  esac

  if [ -x "${target}" ] && [ "$("${target}" --version)" = "${version}" ]; then
    echo "1Password CLI ${version} is already installed."
    return
  fi

  echo "Installing 1Password CLI ${version}..."
  (
    local_temp_dir="$(mktemp -d)"
    trap 'rm -rf "${local_temp_dir}"' EXIT

    curl --fail --location --silent --show-error \
      "https://cache.agilebits.com/dist/1P/op2/pkg/v${version}/op_linux_${arch}_v${version}.zip" \
      --output "${local_temp_dir}/op.zip"
    bsdtar -xf "${local_temp_dir}/op.zip" -C "${local_temp_dir}"
    curl --fail --location --silent --show-error \
      https://downloads.1password.com/linux/keys/1password.asc | \
      gpg --batch --import
    gpg --batch --verify "${local_temp_dir}/op.sig" "${local_temp_dir}/op"

    sudo groupadd -f onepassword-cli
    sudo install -Dm755 "${local_temp_dir}/op" "${target}"
    sudo chgrp onepassword-cli "${target}"
    sudo chmod g+s "${target}"
  )

  if [ "$("${target}" --version)" != "${version}" ]; then
    echo "ERROR: 1Password CLI verification failed after installation." >&2
    exit 1
  fi
}

print_dry_run_plan() {
  local role="$1"
  local source_dir
  local onepassword_cli_version

  source_dir="$(dry_run_source_dir)"

  echo "Dry run: no changes will be made."
  echo "Role: ${role}"
  echo
  echo "Bootstrap actions:"
  case "${role}" in
    macos)
      if ! command -v brew >/dev/null; then
        echo "  install Homebrew"
      fi
      echo "  brew install chezmoi age"
      echo "  ensure /bin/zsh is the login shell"
      ;;
    arch)
      echo "  shelly upgrade --no-confirm (only if confirmed)"
      echo "  shelly install --no-confirm chezmoi age"
      ;;
    fedora)
      if ! command -v chezmoi >/dev/null; then
        echo "  install chezmoi"
      fi
      if ! command -v age >/dev/null; then
        echo "  install age (using Linuxbrew when needed)"
      fi
      ;;
    container)
      echo "  require chezmoi from the container image"
      echo "  install zsh and starship only when missing"
      ;;
  esac

  if [ "${role}" != "container" ]; then
    echo "  require ~/.config/chezmoi/key.txt before applying encrypted files"
  fi

  if [ -d "${HOME}/.local/share/chezmoi/.git" ]; then
    echo "  chezmoi update"
  else
    echo "  chezmoi init --apply ${REPO}"
  fi

  echo
  echo "Package and configuration actions:"
  if [ -z "${source_dir}" ]; then
    echo "  package manifests are unavailable until the dotfiles repository is cloned"
    return
  fi

  case "${role}" in
    macos)
      echo "  brew bundle --file=${source_dir}/pkg/macos/Brewfile"
      echo "  npm install -g @devcontainers/cli (when npm is available)"
      ;;
    arch)
      dry_run_manifest "shelly install --no-confirm" "${source_dir}/pkg/arch/pacman-desktop.txt"
      echo "  import the 1Password signing key when 1password is declared"
      dry_run_manifest "shelly aur install" "${source_dir}/pkg/arch/aur-desktop.txt"
      if [ -f "${source_dir}/pkg/arch/1password-cli.version" ]; then
        onepassword_cli_version="$(tr -d '[:space:]' < "${source_dir}/pkg/arch/1password-cli.version")"
        echo "  install signed 1Password CLI ${onepassword_cli_version} in /usr/local/bin/op"
      fi
      echo "  flatpak remote-add --if-not-exists --user flathub <Flathub remote>"
      dry_run_manifest "flatpak install --user --noninteractive flathub" "${source_dir}/pkg/arch/flatpak-desktop.txt"
      echo "  install Firefox 1Password policy in /etc/firefox/policies/policies.json"
      echo "  ensure zsh is the login shell after installation"
      ;;
    fedora)
      dry_run_manifest "brew install" "${source_dir}/pkg/fedora/brew.txt"
      ;;
    container)
      echo "  skip host package manifests; the Dockerfile owns container packages"
      ;;
  esac
}

OS="$(uname -s)"

echo "Detected OS: ${OS}"

if [ "${DRY_RUN}" = true ]; then
  case "$OS" in
    Darwin)
      print_dry_run_plan "macos"
      ;;
    Linux)
      if [ -f /etc/arch-release ]; then
        print_dry_run_plan "arch"
      elif grep -q 'cosmic-atomic\|rpm-ostree' /etc/os-release 2>/dev/null; then
        print_dry_run_plan "fedora"
      elif [ -f /etc/debian_version ]; then
        print_dry_run_plan "container"
      else
        echo "ERROR: Unsupported Linux distro" >&2
        exit 1
      fi
      ;;
    *)
      echo "ERROR: Unsupported OS: ${OS}" >&2
      exit 1
      ;;
  esac
  exit 0
fi

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
      # Full Arch upgrades are intentionally opt-in. Package installation is
      # still safe without one, and this keeps routine bootstrap runs focused
      # on reconciling the declared host configuration.
      read -r -p "Run a full CachyOS system upgrade now? [y/N] " upgrade_response || true
      case "${upgrade_response:-}" in
        y|Y|yes|YES)
          shelly upgrade --no-confirm
          ;;
        *)
          echo "Skipping full system upgrade."
          ;;
      esac
      shelly install --no-confirm chezmoi age
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
  echo "Installing Arch host packages..."
  sed '/^[[:space:]]*#/d; /^[[:space:]]*$/d' \
    "$(chezmoi source-path)/pkg/arch/pacman-desktop.txt" | xargs shelly install --no-confirm
  echo "Installing Arch host AUR packages..."
  # The official 1Password AUR package verifies vendor-signed downloads. Import
  # its documented signing key before Shelly invokes makepkg.
  if grep -qx '1password' "$(chezmoi source-path)/pkg/arch/aur-desktop.txt"; then
    curl -fsSL https://downloads.1password.com/linux/keys/1password.asc | \
      gpg --batch --import
  fi
  sed '/^[[:space:]]*#/d; /^[[:space:]]*$/d' \
    "$(chezmoi source-path)/pkg/arch/aur-desktop.txt" | xargs shelly aur install

  install_arch_1password_cli "$(chezmoi source-path)"

  echo "Installing desktop applications from Flathub..."
  flatpak remote-add --if-not-exists --user flathub \
    https://dl.flathub.org/repo/flathub.flatpakrepo
  sed '/^[[:space:]]*#/d; /^[[:space:]]*$/d' \
    "$(chezmoi source-path)/pkg/arch/flatpak-desktop.txt" | \
    xargs -r flatpak install --user --noninteractive flathub

  echo "Configuring Firefox 1Password extension..."
  sudo install -Dm644 \
    "$(chezmoi source-path)/assets/firefox/policies.json" \
    /etc/firefox/policies/policies.json

  # Set the login shell after zsh has been installed. This requires the user's
  # password and is harmless on subsequent bootstrap runs.
  zsh_path="$(command -v zsh)"
  current_shell="$(getent passwd "${USER}" | cut -d: -f7)"
  if [ "${current_shell}" != "${zsh_path}" ]; then
    echo "Setting default shell to ${zsh_path} (enter your password if prompted)..."
    chsh -s "${zsh_path}" || echo "WARN: chsh failed — run 'chsh -s ${zsh_path}' manually."
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
