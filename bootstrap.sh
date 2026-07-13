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

KARABINER_CLI="/Library/Application Support/org.pqrs/Karabiner-Elements/bin/karabiner_cli"

# Are Karabiner's background services alive?
#
# Deliberately matched on the org.pqrs install prefix rather than a process name.
# The names churn between major versions — v13/v14 ran a `karabiner_grabber`
# binary, which 16.x replaced with a root "Karabiner-Core-Service" — and a check
# pinned to a name that no longer exists fails closed, blocking a bootstrap whose
# permissions are in fact perfectly fine.
karabiner_running() {
  pgrep -f 'org\.pqrs' >/dev/null 2>&1
}

# Launch the apps whose permissions must be granted by hand. Launching is what
# actually raises the approval prompts; neither can be approved from a script.
# Idempotent: harmless once already approved and running.
prompt_macos_permissions() {
  local launched=false

  if [ -d "/Applications/Karabiner-Elements.app" ] && ! karabiner_running; then
    echo "Launching Karabiner-Elements (first run requests driver approval)..."
    open -ga "Karabiner-Elements" || true
    launched=true
  fi

  if [ -d "/Applications/AeroSpace.app" ] && ! aerospace list-monitors >/dev/null 2>&1; then
    echo "Launching AeroSpace (first run requests Accessibility)..."
    open -ga "AeroSpace" || true
    launched=true
  fi

  # Give the apps a moment to register their extensions and raise their prompts,
  # so the preflight below reports the real state rather than a startup race.
  if [ "${launched}" = true ]; then
    sleep 5
  fi
}

# Gate the dotfiles apply on the permissions that only a human can grant.
#
# This is deliberately a hard stop, not a warning. Every AeroSpace binding lives
# on alt-cmd-* — the chord Karabiner makes Caps Lock emit (see KEYBINDINGS.md).
# Applying the dotfiles before Karabiner is running would leave the machine in its
# worst possible state: a window manager that answers no key at all, and no
# obvious reason why. Better to stop and say so.
preflight_macos() {
  local blockers=0

  echo "Checking macOS permissions..."

  if [ ! -d "/Applications/Karabiner-Elements.app" ]; then
    blockers=$((blockers + 1))
    cat <<'EOF'

  [ ] Karabiner-Elements is not installed.
      Caps Lock is the window-manager modifier; Karabiner is what makes it emit
      Alt+Cmd. Without it, no AeroSpace keybinding works.
      Fix: brew install --cask karabiner-elements
EOF
  else
    # An approved driver extension reports "[activated enabled]".
    # One still awaiting approval reports "[activated waiting for user]".
    if ! systemextensionsctl list 2>/dev/null | grep -i karabiner | \
         grep -q 'activated enabled'; then
      blockers=$((blockers + 1))
      cat <<'EOF'

  [ ] Karabiner's driver extension is not approved.
      Fix: System Settings > General > Login Items & Extensions > Driver Extensions
           Enable "Karabiner-DriverKit-VirtualHIDDevice".
           Restart if macOS asks.
EOF
    fi

    # Karabiner's background services must be running to claim the keyboard.
    #
    # Note: do NOT go looking for Karabiner in System Settings > Input Monitoring.
    # It usually is not listed there at all — granting Accessibility covers input
    # monitoring for it, per pqrs.org's own installation guide. Chasing that
    # missing entry is a dead end.
    if ! karabiner_running; then
      blockers=$((blockers + 1))
      cat <<'EOF'

  [ ] Karabiner's background services are not running.
      Fix: System Settings > General > Login Items & Extensions
             Allow background items for "Karabiner-Elements".
           System Settings > Privacy & Security > Accessibility
             Enable "Karabiner-Elements". (This also covers Input Monitoring —
             Karabiner will not appear in the Input Monitoring list, and does
             not need to.)
           Then launch Karabiner-Elements.
EOF
    elif [ -x "${KARABINER_CLI}" ] && \
         ! "${KARABINER_CLI}" --show-current-profile-name >/dev/null 2>&1; then
      blockers=$((blockers + 1))
      cat <<'EOF'

  [ ] Karabiner is running but not responding to karabiner_cli.
      Fix: quit and relaunch Karabiner-Elements. If it persists, restart.
EOF
    fi
  fi

  if [ ! -d "/Applications/AeroSpace.app" ]; then
    blockers=$((blockers + 1))
    cat <<'EOF'

  [ ] AeroSpace is not installed.
      Fix: brew install --cask nikitabobko/tap/aerospace
EOF
  elif ! aerospace list-monitors >/dev/null 2>&1; then
    # The CLI can only talk to a running server, and the server cannot run
    # without Accessibility. A successful query proves the grant.
    blockers=$((blockers + 1))
    cat <<'EOF'

  [ ] AeroSpace is not responding — its Accessibility grant is missing.
      Fix: System Settings > Privacy & Security > Accessibility
           Enable "AeroSpace", then relaunch it.
EOF
  fi

  if [ "${blockers}" -gt 0 ]; then
    cat <<EOF

────────────────────────────────────────────────────────────────────────────
Bootstrap stopped: ${blockers} item(s) above need your approval.

Your dotfiles were NOT applied, on purpose. The AeroSpace keybindings all sit
on Caps Lock, which emits nothing until Karabiner is running — so applying now
would hand you a window manager that responds to no key at all.

Grant the items above, then run this script again. It is idempotent, and it
will pick up where it left off.
────────────────────────────────────────────────────────────────────────────
EOF
    exit 1
  fi

  echo "  All macOS permissions granted."

  # A second Caps Lock remap here silently fights Karabiner, and is the usual
  # cause of "Karabiner isn't working".
  if defaults -currentHost read -g com.apple.keyboard.modifiermapping >/dev/null 2>&1; then
    echo "  WARN: System Settings > Keyboard > Modifier Keys has a custom mapping."
    echo "        If Caps Lock misbehaves, reset it to 'Caps Lock' and let"
    echo "        Karabiner own the remap. See KEYBINDINGS.md."
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
    echo "  chezmoi git -- pull --ff-only   (fetch source only; apply comes last)"
  else
    echo "  chezmoi init ${REPO}            (fetch source only; apply comes last)"
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
      echo "  launch Karabiner-Elements and AeroSpace to raise their permission prompts"
      echo "  PREFLIGHT GATE: abort unless the Karabiner driver extension, Input"
      echo "    Monitoring, and AeroSpace Accessibility are all granted"
      echo "  retire any unmanaged ~/.config/ghostty/config"
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

  echo
  echo "Finally:"
  echo "  chezmoi apply"
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

# Fetch the source WITHOUT applying it. Packages are installed first, so that
# configuration never lands on a machine that cannot yet honour it — on macOS the
# keybindings are useless (and confusing) until Karabiner and AeroSpace hold their
# permissions. The single `chezmoi apply` happens at the very end.
if [ -d ~/.local/share/chezmoi/.git ]; then
  echo "Updating dotfiles source..."
  chezmoi git -- pull --ff-only || \
    echo "WARN: could not fast-forward the source; using the local copy as-is."
else
  echo "Fetching dotfiles source..."
  chezmoi init "${REPO}"
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

# macOS: the packages are installed, so their permission prompts can now be
# raised. Stop here if anything is still unapproved — see preflight_macos().
if [ "${CHEZMOI_ROLE}" = "macos" ]; then
  prompt_macos_permissions
  preflight_macos
fi

echo "Applying dotfiles..."
chezmoi apply

# The pre-chezmoi Ghostty config. Ghostty reads both `config` and `config.ghostty`
# and merges them, so a stale unmanaged `config` silently contributes settings
# chezmoi cannot see. Retire it once, keeping a copy.
if [ "${CHEZMOI_ROLE}" = "macos" ] && [ -f "${HOME}/.config/ghostty/config" ]; then
  echo "Retiring the unmanaged ~/.config/ghostty/config (backed up alongside it)..."
  mv "${HOME}/.config/ghostty/config" "${HOME}/.config/ghostty/config.pre-chezmoi.bak"
fi

echo ""
echo "Done! Restart your shell or run: exec zsh"
echo "(First zsh launch clones antidote + plugins — give it a few seconds.)"

if [ "${CHEZMOI_ROLE}" = "macos" ]; then
  cat <<'EOF'

Two things do not take effect until you act:
  - Restart Ghostty            (to pick up the freed Cmd keys)
  - Log out and back in        (screenshot shortcuts: Ctrl+Shift+1/2/3)

Then sanity-check the keyboard:
  Cmd+T      -> a herdr tab, NOT a Ghostty tab
  Caps+H/L   -> move window focus
  Caps+1..9  -> switch workspace
  Alt+B      -> readline word-motion in the shell
EOF
fi
