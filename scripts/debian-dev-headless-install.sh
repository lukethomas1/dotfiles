#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf '%s\n' \
    'Usage: debian-dev-headless-install.sh --system|--user|--dry-run|--verify-manifests'
}

mode=
case "${1:-}" in
  --system) mode=system ;;
  --user) mode=user ;;
  --dry-run) mode=dry-run ;;
  --verify-manifests) mode=verify-manifests ;;
  --help|-h) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac
[ "$#" -le 1 ] || { usage >&2; exit 2; }

source_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
role_dir="${source_dir}/pkg/debian-dev-headless"
local_bin="${HOME}/.local/bin"

require_file() {
  [ -f "$1" ] || { printf 'ERROR: missing role input: %s\n' "$1" >&2; exit 1; }
}

for role_input in debian-snapshot.env packages.txt mise.toml mise.lock vendor-tools.tsv tool-catalog.tsv onepassword.env bun-tools/package.json bun-tools/bun.lock; do
  require_file "${role_dir}/${role_input}"
done

verify_manifests() {
  local invalid=0
  rg -n 'latest|/latest/|npm (install|i)|npm@|pnpm|yarn' "${role_dir}" && invalid=1 || true
  rg -n '(^|[[:space:]])(docker|podman|containerd|dockerd|nerdctl|tmux|zellij)([[:space:]]|$)' \
    "${role_dir}/packages.txt" "${role_dir}/mise.toml" "${role_dir}/bun-tools/package.json" && invalid=1 || true
  awk -F'|' 'BEGIN { ok=1 } /^[[:space:]]*#/ || NF==0 { next } NF!=7 || $6 !~ /^[0-9a-f]{64}$/ { ok=0 } END { exit ok ? 0 : 1 }' \
    "${role_dir}/vendor-tools.tsv" || invalid=1
  awk -F'|' 'BEGIN { ok=1 } /^[[:space:]]*#/ || NF==0 { next } NF!=4 || seen[$2]++ { ok=0 } END { exit ok ? 0 : 1 }' \
    "${role_dir}/tool-catalog.tsv" || invalid=1
  [ "$invalid" -eq 0 ] || { echo 'ERROR: role manifest validation failed' >&2; exit 1; }
  echo 'debian-dev-headless manifests are pinned, complete, and engine-free'
}

verify_manifests
[ "$mode" = verify-manifests ] && exit 0

if [ "$mode" = dry-run ]; then
  echo 'Dry run: no package, download, home, shell, or credential changes will be made.'
  echo '  configure signed Debian snapshot from debian-snapshot.env'
  echo '  install exact packages from packages.txt'
  echo '  verify and install exact vendor artifacts into ~/.local/bin'
  echo '  mise install --locked from committed mise.toml and mise.lock'
  echo '  bun install --frozen-lockfile for OpenSpec and Wrangler'
  echo '  create Debian fd/bat compatibility links'
  echo '  reject container engines and competing session managers'
  exit 0
fi

[ "$(uname -m)" = x86_64 ] || { echo 'ERROR: role currently authenticates linux-x64 only' >&2; exit 1; }
. /etc/os-release
[ "${ID:-}" = debian ] && [ "${VERSION_ID:-}" = 13 ] || { echo 'ERROR: Debian 13 is required' >&2; exit 1; }

for forbidden in docker podman containerd dockerd nerdctl ctr tmux zellij; do
  command -v "$forbidden" >/dev/null 2>&1 && { printf 'ERROR: prohibited runtime/session command exists: %s\n' "$forbidden" >&2; exit 1; }
done

if [ "$mode" = system ]; then
  [ "$(id -u)" -eq 0 ] || {
    echo 'ERROR: --system must run as root before the user phase' >&2
    exit 1
  }
  . "${role_dir}/debian-snapshot.env"
  snapshot_file="$(mktemp)"
  trap 'rm -f "${snapshot_file}"' EXIT
  {
    printf 'Types: deb\nURIs: https://snapshot.debian.org/archive/debian/%s/\nSuites: %s\nComponents: %s\nSigned-By: /usr/share/keyrings/debian-archive-keyring.gpg\nCheck-Valid-Until: no\n\n' \
      "$DEBIAN_SNAPSHOT_TIMESTAMP" "$DEBIAN_SUITE" "$DEBIAN_COMPONENTS"
    printf 'Types: deb\nURIs: https://snapshot.debian.org/archive/debian-security/%s/\nSuites: %s\nComponents: %s\nSigned-By: /usr/share/keyrings/debian-archive-keyring.gpg\nCheck-Valid-Until: no\n' \
      "$DEBIAN_SNAPSHOT_TIMESTAMP" "$DEBIAN_SECURITY_SUITE" "$DEBIAN_COMPONENTS"
  } > "$snapshot_file"
  install -Dm644 "$snapshot_file" \
    /etc/apt/sources.list.d/homelab-debian-snapshot.sources
  apt-get update
  sed '/^[[:space:]]*#/d; /^[[:space:]]*$/d' \
    "${role_dir}/packages.txt" |
    xargs apt-get install -y --no-install-recommends
  echo 'debian-dev-headless system packages reconciled; run --user unprivileged'
  exit 0
fi

[ "$mode" = user ] || { usage >&2; exit 2; }
[ "$(id -u)" -ne 0 ] || {
  echo 'ERROR: --user refuses root; user-owned tools must remain unprivileged' >&2
  exit 1
}
[ -f /etc/apt/sources.list.d/homelab-debian-snapshot.sources ] || {
  echo 'ERROR: authenticated system phase has not completed' >&2
  exit 1
}
while IFS= read -r package; do
  case "$package" in ''|'#'*) continue ;; esac
  dpkg-query -W -f='${db:Status-Abbrev}\n' "$package" 2>/dev/null |
    grep -qx 'ii ' || {
      printf 'ERROR: system package is absent: %s\n' "$package" >&2
      exit 1
    }
done < "${role_dir}/packages.txt"

mkdir -p "$local_bin"
while IFS='|' read -r tool version command_name format url digest member; do
  case "$tool" in ''|'#'*) continue ;; esac
  if command -v "$command_name" >/dev/null 2>&1 && "$command_name" --version 2>&1 | rg -q "${version}"; then
    continue
  fi
  artifact="$(mktemp)"
  curl --fail --location --silent --show-error "$url" --output "$artifact"
  printf '%s  %s\n' "$digest" "$artifact" | sha256sum --check
  if [ "$format" = binary ]; then
    install -m755 "$artifact" "${local_bin}/${command_name}"
  elif [ "$format" = tar.gz ]; then
    extract_dir="$(mktemp -d)"
    tar -xzf "$artifact" -C "$extract_dir" "$member"
    install -m755 "${extract_dir}/${member}" "${local_bin}/${command_name}"
    rm -rf "$extract_dir"
  else
    printf 'ERROR: unsupported vendor format for %s\n' "$tool" >&2
    exit 1
  fi
  rm -f "$artifact"
done < "${role_dir}/vendor-tools.tsv"

. "${role_dir}/onepassword.env"
if ! command -v op >/dev/null 2>&1 || [ "$(op --version)" != "$ONEPASSWORD_CLI_VERSION" ]; then
  op_dir="$(mktemp -d)"
  curl --fail --location --silent --show-error \
    "${ONEPASSWORD_ARTIFACT_BASE}/op_linux_amd64_v${ONEPASSWORD_CLI_VERSION}.zip" -o "${op_dir}/op.zip"
  unzip -q "${op_dir}/op.zip" -d "$op_dir"
  GNUPGHOME="${op_dir}/gnupg"; export GNUPGHOME; mkdir -m700 "$GNUPGHOME"
  curl --fail --location --silent --show-error "$ONEPASSWORD_SIGNING_KEY_URL" | gpg --batch --import
  gpg --batch --verify "${op_dir}/op.sig" "${op_dir}/op"
  install -m755 "${op_dir}/op" "${local_bin}/op"
  rm -rf "$op_dir"
  unset GNUPGHOME
fi

mkdir -p "${HOME}/.config/mise"
install -m644 "${role_dir}/mise.toml" "${HOME}/.config/mise/config.toml"
install -m644 "${role_dir}/mise.lock" "${HOME}/.config/mise/config.lock"
"${local_bin}/mise" install --locked

bun_prefix="${HOME}/.local/share/homelab-bun-tools"
mkdir -p "$bun_prefix"
install -m644 "${role_dir}/bun-tools/package.json" "$bun_prefix/package.json"
install -m644 "${role_dir}/bun-tools/bun.lock" "$bun_prefix/bun.lock"
(cd "$bun_prefix" && "${local_bin}/mise" exec -- bun install --frozen-lockfile --production)
for bun_command in openspec wrangler; do
  ln -sfn "${bun_prefix}/node_modules/.bin/${bun_command}" "${local_bin}/${bun_command}"
done

command -v fdfind >/dev/null && ln -sfn "$(command -v fdfind)" "${local_bin}/fd"
command -v batcat >/dev/null && ln -sfn "$(command -v batcat)" "${local_bin}/bat"

for forbidden in docker podman containerd dockerd nerdctl ctr tmux zellij; do
  command -v "$forbidden" >/dev/null 2>&1 && { printf 'ERROR: prohibited command activated: %s\n' "$forbidden" >&2; exit 1; }
done
echo 'debian-dev-headless software reconciliation complete; credentials remain unenrolled'
