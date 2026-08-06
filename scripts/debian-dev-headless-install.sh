#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf '%s\n' \
    'Usage: debian-dev-headless-install.sh --system|--user|--dry-run|--verify-manifests|--verify-apt-attestation <absolute-root>'
}

mode=
apt_verification_root=
case "${1:-}" in
  --system) mode=system ;;
  --user) mode=user ;;
  --dry-run) mode=dry-run ;;
  --verify-manifests) mode=verify-manifests ;;
  --verify-apt-attestation)
    mode=verify-apt-attestation
    [ "$#" -eq 2 ] || { usage >&2; exit 2; }
    case "$2" in
      /*) apt_verification_root="${2%/}" ;;
      *) printf 'ERROR: APT verification root must be absolute\n' >&2; exit 2 ;;
    esac
    ;;
  --help|-h) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac
if [ "$mode" != verify-apt-attestation ]; then
  [ "$#" -le 1 ] || { usage >&2; exit 2; }
fi

script_dir="${BASH_SOURCE[0]%/*}"
[ "$script_dir" != "${BASH_SOURCE[0]}" ] || script_dir=.
source_dir="${DEBIAN_DEV_HEADLESS_SOURCE_DIR:-$(CDPATH= cd -- "${script_dir}/.." && pwd)}"
if [ "$mode" = system ]; then
  for fixture_override in \
    DEBIAN_DEV_HEADLESS_APT_ROOT \
    DEBIAN_DEV_HEADLESS_OS_RELEASE \
    DEBIAN_DEV_HEADLESS_ROLE_DIR \
    DEBIAN_DEV_HEADLESS_SOURCE_DIR; do
    [ -z "${!fixture_override+x}" ] ||
      {
        printf 'ERROR: --system refuses fixture override: %s\n' \
          "$fixture_override" >&2
        exit 1
      }
  done
  role_dir="${source_dir}/pkg/debian-dev-headless"
  os_release_file=/etc/os-release
elif [ "$mode" = verify-apt-attestation ]; then
  role_dir="${DEBIAN_DEV_HEADLESS_ROLE_DIR:-${source_dir}/pkg/debian-dev-headless}"
  os_release_file="${apt_verification_root}/etc/os-release"
else
  role_dir="${DEBIAN_DEV_HEADLESS_ROLE_DIR:-${source_dir}/pkg/debian-dev-headless}"
  os_release_file="${DEBIAN_DEV_HEADLESS_OS_RELEASE:-/etc/os-release}"
fi
local_bin="${HOME}/.local/bin"
debian_fd_target=/usr/bin/fdfind
debian_bat_target=/usr/bin/batcat
temp_root=
staged_path=

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  if [ -n "${staged_path}" ] &&
     { [ -e "${staged_path}" ] || [ -L "${staged_path}" ]; }; then
    rm -f -- "${staged_path}"
  fi
  if [ -n "${temp_root}" ] && [ -d "${temp_root}" ]; then
    rm -rf -- "${temp_root}"
  fi
}
trap cleanup EXIT

require_file() {
  [ -f "$1" ] || die "missing role input: $1"
}

require_commands() {
  local command_name
  for command_name in "$@"; do
    command -v "${command_name}" >/dev/null 2>&1 ||
      die "required validation command is unavailable: ${command_name}"
  done
}

for role_input in \
  packages.txt \
  required-commands.tsv \
  mise.toml \
  mise.lock \
  vendor-tools.tsv \
  onepassword.env \
  onepassword.asc \
  bun-tools/package.json \
  bun-tools/bun.lock; do
  require_file "${role_dir}/${role_input}"
done
require_file "${source_dir}/dot_zsh_plugins.txt"
require_file "${source_dir}/dot_config/zsh/antidote.version"

verify_package_manifest() {
  awk '
    BEGIN { ok=1 }
    /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
    $0 !~ /^[a-z0-9][a-z0-9+.-]*$/ { ok=0 }
    seen[$0]++ { ok=0 }
    END { exit ok ? 0 : 1 }
  ' "${role_dir}/packages.txt" ||
    die 'packages.txt contains an invalid or duplicate package'
}

verify_required_commands_manifest() {
  awk -F'|' '
    BEGIN { ok=1 }
    /^[[:space:]]*#/ || NF==0 { next }
    NF!=2 { ok=0; next }
    $1 !~ /^[a-z][a-z0-9-]*$/ { ok=0 }
    $2 !~ /^[A-Za-z0-9][A-Za-z0-9._+-]*$/ { ok=0 }
    seen[$2]++ { ok=0 }
    END { exit ok ? 0 : 1 }
  ' "${role_dir}/required-commands.tsv" ||
    die 'required-commands.tsv contains an invalid or duplicate command'
}

verify_vendor_manifest() {
  awk -F'|' '
    function safe_name(value) {
      return value ~ /^[A-Za-z0-9][A-Za-z0-9._+-]*$/
    }
    function safe_member(value) {
      return value ~ /^[A-Za-z0-9._+\/-]+$/ &&
             value !~ /^\// &&
             value !~ /(^|\/)\.\.(\/|$)/
    }
    BEGIN { ok=1 }
    /^[[:space:]]*#/ || NF==0 { next }
    NF!=8 { ok=0; next }
    !safe_name($1) || $2 !~ /^[0-9]+(\.[0-9]+)+$/ || !safe_name($3) { ok=0 }
    seen_tool[$1]++ || seen_command[$3]++ { ok=0 }
    $4 !~ /^(binary|tar\.gz)$/ { ok=0 }
    $5 !~ /^https:\/\// { ok=0 }
    $6 !~ /^[0-9a-f]+$/ || length($6)!=64 { ok=0 }
    $4=="binary" && ($7!="-" || $8!="-") { ok=0 }
    $4=="tar.gz" && (!safe_member($7) || $8 !~ /^[0-9a-f]+$/ || length($8)!=64) { ok=0 }
    END { exit ok ? 0 : 1 }
  ' "${role_dir}/vendor-tools.tsv" ||
    die 'vendor-tools.tsv contains an invalid, duplicate, or unsafe row'
}

verify_onepassword_manifest() {
  awk -F= '
    BEGIN { ok=1 }
    /^[[:space:]]*#/ || NF==0 { next }
    NF!=2 { ok=0; next }
    !($1 ~ /^ONEPASSWORD_(CLI_VERSION|ARTIFACT_BASE|SIGNING_KEY_FINGERPRINT|BINARY_SHA256)$/) { ok=0 }
    seen[$1]++ { ok=0 }
    $1=="ONEPASSWORD_CLI_VERSION" && $2 !~ /^[0-9]+\.[0-9]+\.[0-9]+$/ { ok=0 }
    $1=="ONEPASSWORD_ARTIFACT_BASE" &&
      $2 !~ /^https:\/\/[A-Za-z0-9._~:\/?&=%+-]+$/ { ok=0 }
    $1=="ONEPASSWORD_SIGNING_KEY_FINGERPRINT" &&
      ($2 !~ /^[0-9A-F]+$/ || length($2)!=40) { ok=0 }
    $1=="ONEPASSWORD_BINARY_SHA256" &&
      ($2 !~ /^[0-9a-f]+$/ || length($2)!=64) { ok=0 }
    END {
      required[1]="ONEPASSWORD_CLI_VERSION"
      required[2]="ONEPASSWORD_ARTIFACT_BASE"
      required[3]="ONEPASSWORD_SIGNING_KEY_FINGERPRINT"
      required[4]="ONEPASSWORD_BINARY_SHA256"
      for (i=1; i<=4; i++) if (seen[required[i]]!=1) ok=0
      exit ok ? 0 : 1
    }
  ' "${role_dir}/onepassword.env" ||
    die 'onepassword.env is incomplete or invalid'
}

verify_onepassword_public_key() {
  local expected actual
  expected="$(
    awk -F= '$1=="ONEPASSWORD_SIGNING_KEY_FINGERPRINT" { print $2; exit }' \
      "${role_dir}/onepassword.env"
  )"
  actual="$(
    gpg --batch --no-autostart --show-keys --with-colons --fingerprint \
      "${role_dir}/onepassword.asc" 2>/dev/null |
      awk -F: '
        $1=="pub" { primary=1; count++ }
        primary && $1=="fpr" { print $10; primary=0 }
        END { if (count!=1) exit 1 }
      '
  )" || die 'committed 1Password key must contain exactly one primary key'
  [ "$actual" = "$expected" ] ||
    die "committed 1Password public key fingerprint differs: ${actual:-missing}"
}

verify_zsh_pins() {
  awk '
    BEGIN { ok=1 }
    /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
    {
      pin_count=0
      for (i=1; i<=NF; i++) {
        if ($i ~ /^pin:/) {
          pin_count++
          sha=substr($i, 5)
          if (length(sha)!=40 || sha !~ /^[0-9a-f]+$/) ok=0
        }
      }
      if (pin_count!=1) ok=0
    }
    END { exit ok ? 0 : 1 }
  ' "${source_dir}/dot_zsh_plugins.txt" ||
    die 'every Zsh plugin must have one full pin:<SHA> declaration'

  awk '
    NR==1 && length($0)==40 && $0 ~ /^[0-9a-f]+$/ { ok=1 }
    NR>1 || !ok { exit 1 }
  ' "${source_dir}/dot_config/zsh/antidote.version" ||
    die 'Antidote must have one full committed revision'
}

verify_base_manifests() {
  require_commands awk grep
  verify_package_manifest
  verify_required_commands_manifest
  verify_vendor_manifest
  verify_onepassword_manifest
  verify_zsh_pins

  if grep -En 'latest|/latest/|npm (install|i)|npm@|pnpm|yarn' \
    "${role_dir}/mise.toml" \
    "${role_dir}/vendor-tools.tsv" \
    "${role_dir}/onepassword.env" \
    "${role_dir}/bun-tools/package.json" >/dev/null; then
    die 'a floating or competing package declaration was found'
  fi
}

mise_config_entries() {
  awk '
    function trim(value) {
      sub(/^[[:space:]]+/, "", value)
      sub(/[[:space:]]+$/, "", value)
      return value
    }
    /^\[tools\]$/ { in_tools=1; next }
    in_tools && /^\[/ { exit }
    in_tools && /^[^#].*=/ {
      split_at=index($0, "=")
      key=trim(substr($0, 1, split_at-1))
      value=trim(substr($0, split_at+1))
      gsub(/^"|"$/, "", key)
      gsub(/^"|"$/, "", value)
      print key "|" value
    }
  ' "${role_dir}/mise.toml"
}

mise_lock_entries() {
  awk '
    /^\[\[tools\./ {
      key=$0
      sub(/^\[\[tools\./, "", key)
      sub(/\]\]$/, "", key)
      gsub(/^"|"$/, "", key)
      current=key
      next
    }
    current!="" && /^version = / {
      value=$0
      sub(/^version = "/, "", value)
      sub(/"$/, "", value)
      print current "|" value
      current=""
    }
  ' "${role_dir}/mise.lock"
}

mise_command_for_key() {
  case "$1" in
    bun|go|node|python|uv) printf '%s\n' "$1" ;;
    aqua:pulumi/pulumi) echo pulumi ;;
    aqua:siderolabs/talos) echo talosctl ;;
    aqua:kubernetes/kubernetes/kubectl) echo kubectl ;;
    aqua:helm/helm) echo helm ;;
    aqua:kubernetes-sigs/kustomize) echo kustomize ;;
    aqua:fluxcd/flux2) echo flux ;;
    aqua:cilium/cilium-cli) echo cilium ;;
    aqua:getsops/sops) echo sops ;;
    aqua:dagger/dagger) echo dagger ;;
    aqua:sigstore/cosign) echo cosign ;;
    aqua:anchore/syft) echo syft ;;
    aqua:anchore/grype) echo grype ;;
    aqua:aquasecurity/trivy) echo trivy ;;
    aqua:gitleaks/gitleaks) echo gitleaks ;;
    aqua:cli/cli) echo gh ;;
    aqua:jesseduffield/lazygit) echo lazygit ;;
    aqua:dandavison/delta) echo delta ;;
    aqua:starship/starship) echo starship ;;
    aqua:atuinsh/atuin) echo atuin ;;
    aqua:eza-community/eza) echo eza ;;
    aqua:ajeetdsouza/zoxide) echo zoxide ;;
    *) return 1 ;;
  esac
}

package_command_for_name() {
  case "$1" in
    bash|zsh|curl|git|mosh|rsync|tar|zip|unzip|openssl|sqlite3|make|traceroute|jq|yq|chezmoi|direnv|fzf|age|restic)
      printf '%s\n' "$1"
      ;;
    git-lfs) echo git-lfs ;;
    openssh-client) echo ssh ;;
    xz-utils) echo xz ;;
    gnupg) echo gpg ;;
    pkg-config) echo pkg-config ;;
    dnsutils) echo dig ;;
    iproute2) echo ip ;;
    iputils-ping) echo ping ;;
    netcat-openbsd) echo nc ;;
    ripgrep) echo rg ;;
    fd-find) echo fdfind ;;
    bat) echo batcat ;;
    neovim) echo nvim ;;
    incus-client) echo incus ;;
    ca-certificates|coreutils|build-essential) return 0 ;;
    *) return 1 ;;
  esac
}

emit_command_inventory() {
  local package key version command_name

  while IFS= read -r package; do
    case "$package" in ''|'#'*) continue ;; esac
    command_name="$(package_command_for_name "$package")" ||
      die "no command inventory mapping for Debian package: ${package}"
    [ -n "$command_name" ] && printf '%s|apt:%s\n' "$command_name" "$package"
    case "$package" in
      fd-find) printf '%s\n' 'fd|compat:fd-find' ;;
      bat) printf '%s\n' 'bat|compat:bat' ;;
    esac
  done < "${role_dir}/packages.txt"

  while IFS='|' read -r key version; do
    [ -n "$key" ] || continue
    command_name="$(mise_command_for_key "$key")" ||
      die "no command inventory mapping for mise tool: ${key}"
    printf '%s|mise:%s@%s\n' "$command_name" "$key" "$version"
  done < <(mise_config_entries)

  awk -F'|' '!/^[[:space:]]*#/ && NF { print $3 "|vendor:" $1 "@" $2 }' \
    "${role_dir}/vendor-tools.tsv"
  if [ -n "$(manifest_value_from "${role_dir}/onepassword.env" ONEPASSWORD_CLI_VERSION)" ]; then
    printf '%s\n' 'op|signed-vendor:1password'
  fi
  jq -r '
    .dependencies // {} |
    to_entries[] |
    if .key == "@fission-ai/openspec" then
      "openspec|bun:@fission-ai/openspec"
    elif .key == "wrangler" then
      "wrangler|bun:wrangler"
    else
      "bun-unknown|" + .key
    end
  ' "${role_dir}/bun-tools/package.json"
}

verify_mise_lock() {
  local config_entries lock_entries entry
  config_entries="$(mise_config_entries)"
  lock_entries="$(mise_lock_entries)"

  printf '%s\n' "$config_entries" |
    awk -F'|' '
      NF!=2 || $1=="" || $2 !~ /^[0-9]+(\.[0-9]+)+$/ || seen[$1]++ { exit 1 }
    ' ||
    die 'mise.toml contains an invalid or duplicate exact tool version'

  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    printf '%s\n' "$lock_entries" | grep -Fqx "$entry" ||
      die "mise.lock is missing or mismatches: ${entry}"
  done <<< "$config_entries"

  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    printf '%s\n' "$config_entries" | grep -Fqx "$entry" ||
      die "mise.lock contains an undeclared tool: ${entry}"
  done <<< "$lock_entries"
}

verify_bun_lock() {
  local bun_version package_manager dependency package_version lock_version
  bun_version="$(mise_config_entries | awk -F'|' '$1=="bun" { print $2 }')"
  package_manager="$(jq -er '.packageManager' "${role_dir}/bun-tools/package.json")"
  [ "$package_manager" = "bun@${bun_version}" ] ||
    die 'Bun packageManager does not match the mise Bun version'

  [ "$(jq -r '.dependencies | length' "${role_dir}/bun-tools/package.json")" -eq 2 ] ||
    die 'Bun dependencies must contain exactly OpenSpec and Wrangler'

  for dependency in '@fission-ai/openspec' wrangler; do
    package_version="$(jq -er --arg dependency "$dependency" '.dependencies[$dependency]' \
      "${role_dir}/bun-tools/package.json")"
    [[ "$package_version" =~ ^[0-9]+(\.[0-9]+)+$ ]] ||
      die "Bun dependency does not use an exact numeric version: ${dependency}"
    lock_version="$(
      awk -v dependency="\"${dependency}\":" '
        /"workspaces": \{/ { in_workspaces=1; next }
        in_workspaces && /"dependencies": \{/ { in_dependencies=1; next }
        in_dependencies && $1==dependency {
          value=$2
          gsub(/[",]/, "", value)
          print value
          exit
        }
        in_dependencies && /^[[:space:]]*},?$/ { exit }
      ' "${role_dir}/bun-tools/bun.lock"
    )"
    [ "$lock_version" = "$package_version" ] ||
      die "bun.lock does not match ${dependency}@${package_version}"
  done
}

verify_unique_inventory() {
  local inventory duplicate
  inventory="$(emit_command_inventory)"
  duplicate="$(
    printf '%s\n' "$inventory" |
      sort |
      awk -F'|' 'seen[$1]++ { print $1; exit }'
  )"
  [ -z "$duplicate" ] ||
    die "command has multiple manifest owners: ${duplicate}"
}

verify_required_inventory() {
  local inventory missing
  inventory="$(emit_command_inventory)"
  missing="$(
    awk -F'|' '
      NR==FNR {
        if ($0 !~ /^[[:space:]]*#/ && NF) inventory[$1]=1
        next
      }
      $0 !~ /^[[:space:]]*#/ && NF && !inventory[$2] {
        print $1 "|" $2
        exit
      }
    ' <(printf '%s\n' "$inventory") "${role_dir}/required-commands.tsv"
  )"
  [ -z "$missing" ] ||
    die "required command has no native manifest owner: ${missing}"
}

verify_full_manifests() {
  require_commands jq sort gpg
  verify_onepassword_public_key
  verify_unique_inventory
  verify_required_inventory
  verify_mise_lock
  verify_bun_lock
}

verify_platform() {
  local platform_id platform_version
  [ "$(uname -m)" = x86_64 ] ||
    die 'debian-dev-headless currently supports linux-x64 only'
  require_file "${os_release_file}"
  platform_id="$(
    awk -F= '$1=="ID" { value=substr($0, index($0, "=")+1); gsub(/^"|"$/, "", value); print value; exit }' \
      "${os_release_file}"
  )"
  platform_version="$(
    awk -F= '$1=="VERSION_ID" { value=substr($0, index($0, "=")+1); gsub(/^"|"$/, "", value); print value; exit }' \
      "${os_release_file}"
  )"
  [ "$platform_id" = debian ] && [ "$platform_version" = 13 ] ||
    die 'Debian 13 is required'
}

manifest_value_from() {
  local file="$1"
  local key="$2"
  awk -F= -v key="$key" '$1==key { print substr($0, index($0, "=")+1); exit }' \
    "$file"
}

compute_apt_config_digest() {
  local apt_root="$1"
  local path relative digest
  {
    while IFS= read -r -d '' path; do
      [ -f "$path" ] && [ ! -L "$path" ] ||
        die "APT configuration entry is not a regular file: ${path}"
      relative="${path#"${apt_root}"/}"
      digest="$(sha256sum "$path")"
      printf '%s|%s\n' "$relative" "${digest%% *}"
    done < <(
      find "${apt_root}/etc/apt" -maxdepth 2 \
        \( -path "${apt_root}/etc/apt/sources.list" \
           -o -path "${apt_root}/etc/apt/sources.list.d/*.list" \
           -o -path "${apt_root}/etc/apt/sources.list.d/*.sources" \) \
        -print0 |
        sort -z
    )
  } | sha256sum | awk '{ print $1 }'
}

verify_apt_trust_attestation() {
  local apt_root trust_file source_file keyring_file owner_mode
  local schema role os_id version_id suites apt_config_sha source_sha keyring_sha
  local actual
  apt_root="$1"
  trust_file="${apt_root}/etc/homelab/developer-console-apt-trust"
  source_file="${apt_root}/etc/apt/sources.list.d/debian.sources"
  keyring_file="${apt_root}/usr/share/keyrings/debian-archive-keyring.pgp"

  [ -f "$trust_file" ] && [ ! -L "$trust_file" ] ||
    die "homelab APT trust attestation is missing or unsafe: ${trust_file}"
  owner_mode="$(stat -c '%U:%G:%a' "$trust_file")"
  [ "$owner_mode" = root:root:644 ] ||
    die "homelab APT trust attestation has unsafe ownership or mode: ${owner_mode}"

  awk -F= '
    BEGIN { ok=1 }
    NF!=2 { ok=0; next }
    !($1 ~ /^(schema|role|os_id|version_id|suites|apt_config_sha256|source_sha256|keyring_sha256)$/) { ok=0 }
    seen[$1]++ { ok=0 }
    END {
      required[1]="schema"
      required[2]="role"
      required[3]="os_id"
      required[4]="version_id"
      required[5]="suites"
      required[6]="apt_config_sha256"
      required[7]="source_sha256"
      required[8]="keyring_sha256"
      for (i=1; i<=8; i++) if (seen[required[i]]!=1) ok=0
      exit ok ? 0 : 1
    }
  ' "$trust_file" ||
    die 'homelab APT trust attestation is malformed'

  schema="$(manifest_value_from "$trust_file" schema)"
  role="$(manifest_value_from "$trust_file" role)"
  os_id="$(manifest_value_from "$trust_file" os_id)"
  version_id="$(manifest_value_from "$trust_file" version_id)"
  suites="$(manifest_value_from "$trust_file" suites)"
  apt_config_sha="$(manifest_value_from "$trust_file" apt_config_sha256)"
  source_sha="$(manifest_value_from "$trust_file" source_sha256)"
  keyring_sha="$(manifest_value_from "$trust_file" keyring_sha256)"
  [ "$schema" = 1 ] &&
    [ "$role" = debian-dev-headless ] &&
    [ "$os_id" = debian ] &&
    [ "$version_id" = 13 ] &&
    [ "$suites" = trixie,trixie-updates,trixie-security ] ||
    die 'homelab APT trust attestation does not match the Debian headless contract'
  for actual in "$apt_config_sha" "$source_sha" "$keyring_sha"; do
    [[ "$actual" =~ ^[0-9a-f]{64}$ ]] ||
      die 'homelab APT trust attestation contains an invalid digest'
  done
  [ -f "$source_file" ] && [ ! -L "$source_file" ] ||
    die "attested Debian source is missing or unsafe: ${source_file}"
  [ -f "$keyring_file" ] && [ ! -L "$keyring_file" ] ||
    die "attested Debian keyring is missing or unsafe: ${keyring_file}"
  actual="$(sha256sum "$source_file")"
  [ "${actual%% *}" = "$source_sha" ] ||
    die 'homelab APT source identity has changed since attestation'
  actual="$(sha256sum "$keyring_file")"
  [ "${actual%% *}" = "$keyring_sha" ] ||
    die 'homelab APT keyring identity has changed since attestation'
  actual="$(compute_apt_config_digest "$apt_root")"
  [ "$actual" = "$apt_config_sha" ] ||
    die 'homelab APT configuration has changed since attestation'
}

verify_base_manifests

if [ "$mode" = verify-manifests ]; then
  verify_full_manifests
  echo 'debian-dev-headless native manifests are pinned, consistent, and fail-closed'
  exit 0
fi

if [ "$mode" = system ] && [ "$(id -u)" -ne 0 ]; then
  die '--system must run as root before the user phase'
fi

verify_platform

if [ "$mode" = verify-apt-attestation ]; then
  require_commands find sha256sum sort stat
  verify_apt_trust_attestation "$apt_verification_root"
  echo "Debian headless APT trust attestation verified without mutation: ${apt_verification_root:-/}"
  exit 0
fi

if [ "$mode" = dry-run ]; then
  echo 'Dry run: no package, download, home, shell, or credential changes will be made.'
  echo '  base manifest validation passed; full jq-dependent lock and inventory validation is deferred'
  echo '  require a current homelab-attested Debian 13 stable/security APT trust state'
  echo '  refresh APT metadata and verify a candidate for every package'
  echo '  install the additive package-name set from packages.txt'
  echo '  verify and install exact vendor artifacts into ~/.local/bin'
  echo '  verify the expected 1Password signing-key fingerprint and release signature'
  echo '  mise install --locked from committed mise.toml and mise.lock'
  echo '  bun install --frozen-lockfile for OpenSpec and Wrangler'
  echo '  create Debian fd/bat compatibility links'
  echo '  leave pre-existing engines and session managers untouched'
  exit 0
fi

if [ "$mode" = system ]; then
  require_commands apt-get apt-cache find sha256sum sort stat

  verify_apt_trust_attestation ""
  apt-get update

  packages=()
  while IFS= read -r package; do
    case "$package" in ''|'#'*) continue ;; esac
    candidate="$(
      apt-cache policy "$package" |
        awk '$1=="Candidate:" { print $2; exit }'
    )"
    [ -n "$candidate" ] && [ "$candidate" != '(none)' ] ||
      die "no APT candidate is available for package: ${package}"
    packages+=("$package")
  done < "${role_dir}/packages.txt"

  apt-get install -y --no-install-recommends "${packages[@]}"
  echo 'debian-dev-headless system package set reconciled; run --user unprivileged'
  exit 0
fi

[ "$mode" = user ] || { usage >&2; exit 2; }
[ "$(id -u)" -ne 0 ] ||
  die '--user refuses root; user-owned tools must remain unprivileged'

verify_full_manifests
require_commands chmod curl dpkg-query gpg grep install ln mkdir mktemp mv rm sha256sum tar unzip zipinfo

while IFS= read -r package; do
  case "$package" in ''|'#'*) continue ;; esac
  dpkg-query -W -f='${db:Status-Abbrev}\n' "$package" 2>/dev/null |
    grep -qx 'ii ' ||
    die "system package is absent: ${package}"
done < "${role_dir}/packages.txt"

mkdir -p "$local_bin"
export PATH="${local_bin}:${PATH}"
temp_root="$(mktemp -d)"

version_matches() {
  local executable="$1"
  local expected="$2"
  local output version_regex
  version_regex="${expected//./\\.}"
  output="$("${executable}" --version 2>&1 || true)"
  [[ "$output" =~ (^|[^0-9.])${version_regex}([^0-9.]|$) ]]
}

managed_target_is_safe() {
  local path="$1"
  if [ -L "$path" ] || { [ -e "$path" ] && [ ! -f "$path" ]; }; then
    die "managed command target is not a regular file: ${path}"
  fi
}

payload_matches() {
  local path="$1"
  local expected="$2"
  local actual
  [ -f "$path" ] && [ ! -L "$path" ] || return 1
  actual="$(sha256sum "$path")"
  [ "${actual%% *}" = "$expected" ]
}

installed_command_matches() {
  local path="$1"
  local version="$2"
  local digest="$3"
  managed_target_is_safe "$path"
  payload_matches "$path" "$digest" && version_matches "$path" "$version"
}

install_verified_command() {
  local source_path="$1"
  local command_name="$2"
  local version="$3"
  local expected_digest="$4"

  payload_matches "$source_path" "$expected_digest" ||
    die "authenticated payload digest does not match for ${command_name}"
  managed_target_is_safe "${local_bin}/${command_name}"
  staged_path="$(mktemp "${local_bin}/.${command_name}.new.XXXXXX")"
  install -m755 "$source_path" "$staged_path"
  payload_matches "$staged_path" "$expected_digest" ||
    die "staged ${command_name} payload identity changed"
  version_matches "$staged_path" "$version" || {
    die "staged ${command_name} does not report version ${version}"
  }
  mv -f -- "$staged_path" "${local_bin}/${command_name}"
  staged_path=
}

while IFS='|' read -r tool version command_name format url digest member payload_digest; do
  case "$tool" in ''|'#'*) continue ;; esac
  if [ "$format" = binary ]; then
    expected_payload_digest="$digest"
  else
    expected_payload_digest="$payload_digest"
  fi
  if installed_command_matches \
    "${local_bin}/${command_name}" "$version" "$expected_payload_digest"; then
    continue
  fi

  artifact="${temp_root}/${tool}.artifact"
  curl --fail --location --silent --show-error "$url" --output "$artifact"
  printf '%s  %s\n' "$digest" "$artifact" | sha256sum --check

  case "$format" in
    binary)
      candidate="$artifact"
      ;;
    tar.gz)
      extract_dir="${temp_root}/${tool}.extract"
      mkdir -p "$extract_dir"
      archive_member_count="$(
        tar -tzf "$artifact" "$member" |
          awk -v member="$member" '$0==member { count++ } END { print count+0 }'
      )"
      [ "$archive_member_count" -eq 1 ] ||
        die "archive must contain exactly one declared member for ${tool}: ${member}"
      archive_type="$(tar -tvzf "$artifact" "$member" | awk 'NR==1 { print substr($1, 1, 1) }')"
      [ "$archive_type" = - ] ||
        die "archive member for ${tool} is not a regular file: ${member}"
      tar --extract --gzip --file "$artifact" --directory "$extract_dir" \
        --no-same-owner --no-same-permissions "$member"
      candidate="${extract_dir}/${member}"
      payload_matches "$candidate" "$expected_payload_digest" ||
        die "archive member digest does not match for ${tool}: ${member}"
      ;;
    *)
      die "unsupported vendor format for ${tool}: ${format}"
      ;;
  esac

  install_verified_command \
    "$candidate" "$command_name" "$version" "$expected_payload_digest"
done < "${role_dir}/vendor-tools.tsv"

manifest_value() {
  local key="$1"
  awk -F= -v key="$key" '$1==key { print substr($0, index($0, "=")+1); exit }' \
    "${role_dir}/onepassword.env"
}
ONEPASSWORD_CLI_VERSION="$(manifest_value ONEPASSWORD_CLI_VERSION)"
ONEPASSWORD_SIGNING_KEY_FINGERPRINT="$(manifest_value ONEPASSWORD_SIGNING_KEY_FINGERPRINT)"
ONEPASSWORD_ARTIFACT_BASE="$(manifest_value ONEPASSWORD_ARTIFACT_BASE)"
ONEPASSWORD_BINARY_SHA256="$(manifest_value ONEPASSWORD_BINARY_SHA256)"
if ! installed_command_matches \
  "${local_bin}/op" "$ONEPASSWORD_CLI_VERSION" "$ONEPASSWORD_BINARY_SHA256"; then
  op_dir="${temp_root}/onepassword"
  mkdir -p "${op_dir}/gnupg"
  chmod 700 "${op_dir}/gnupg"
  curl --fail --location --silent --show-error \
    "${ONEPASSWORD_ARTIFACT_BASE}/op_linux_amd64_v${ONEPASSWORD_CLI_VERSION}.zip" \
    --output "${op_dir}/op.zip"
  archive_members="$(unzip -Z1 "${op_dir}/op.zip" | sort)"
  [ "$archive_members" = $'op\nop.sig' ] ||
    die '1Password archive must contain only op and op.sig'
  for op_member in op op.sig; do
    archive_type="$(
      zipinfo -l "${op_dir}/op.zip" "$op_member" |
        awk '$0 ~ /^[dlcbps-][rwx-]{9}/ { print substr($1, 1, 1); exit }'
    )"
    [ "$archive_type" = - ] ||
      die "1Password archive member is not a regular file: ${op_member}"
    unzip -p "${op_dir}/op.zip" "$op_member" >"${op_dir}/${op_member}"
  done
  GNUPGHOME="${op_dir}/gnupg" gpg --batch --no-autostart \
    --import "${role_dir}/onepassword.asc"
  signing_fingerprint="$(
    GNUPGHOME="${op_dir}/gnupg" gpg --batch --no-autostart \
      --with-colons --fingerprint |
      awk -F: '
        $1=="pub" { primary=1; count++ }
        primary && $1=="fpr" { print $10; primary=0 }
        END { if (count!=1) exit 1 }
      '
  )" || die 'committed 1Password key must contain exactly one primary key'
  [ "$signing_fingerprint" = "$ONEPASSWORD_SIGNING_KEY_FINGERPRINT" ] ||
    die "unexpected 1Password signing-key fingerprint: ${signing_fingerprint:-missing}"
  signature_status="$(
    GNUPGHOME="${op_dir}/gnupg" gpg --batch --no-autostart --status-fd 1 \
      --verify "${op_dir}/op.sig" "${op_dir}/op" 2>/dev/null
  )" || die '1Password release signature verification failed'
  valid_signer="$(
    printf '%s\n' "$signature_status" |
      awk -v expected="$ONEPASSWORD_SIGNING_KEY_FINGERPRINT" '
        $1=="[GNUPG:]" && $2=="VALIDSIG" {
          count++
          if ($3==expected || $12==expected) matched++
        }
        END {
          if (count==1 && matched==1) print expected
          else exit 1
        }
      '
  )" || die '1Password release signature was not made by the committed key'
  [ "$valid_signer" = "$ONEPASSWORD_SIGNING_KEY_FINGERPRINT" ] ||
    die '1Password release signature signer is ambiguous'
  payload_matches "${op_dir}/op" "$ONEPASSWORD_BINARY_SHA256" ||
    die '1Password authenticated payload digest does not match'
  install_verified_command \
    "${op_dir}/op" op "$ONEPASSWORD_CLI_VERSION" "$ONEPASSWORD_BINARY_SHA256"
fi

mkdir -p "${HOME}/.config/mise"
install -m644 "${role_dir}/mise.toml" "${HOME}/.config/mise/config.toml"
install -m644 "${role_dir}/mise.lock" "${HOME}/.config/mise/config.lock"
"${local_bin}/mise" install --locked

mise_version_output() {
  local command_name="$1"
  case "$command_name" in
    go) "${local_bin}/mise" exec -- go version ;;
    kubectl) "${local_bin}/mise" exec -- kubectl version --client ;;
    helm) "${local_bin}/mise" exec -- helm version --short ;;
    talosctl) "${local_bin}/mise" exec -- talosctl version --client ;;
    cilium) "${local_bin}/mise" exec -- cilium version --client ;;
    dagger) "${local_bin}/mise" exec -- dagger version ;;
    gitleaks) "${local_bin}/mise" exec -- gitleaks version ;;
    *) "${local_bin}/mise" exec -- "$command_name" --version ;;
  esac 2>&1
}

while IFS='|' read -r key version; do
  [ -n "$key" ] || continue
  command_name="$(mise_command_for_key "$key")"
  version_regex="${version//./\\.}"
  output="$(mise_version_output "$command_name" || true)"
  [[ "$output" =~ (^|[^0-9.])${version_regex}([^0-9.]|$) ]] ||
    die "mise command ${command_name} does not report version ${version}"
done < <(mise_config_entries)

openspec_version="$(jq -r '.dependencies["@fission-ai/openspec"]' "${role_dir}/bun-tools/package.json")"
wrangler_version="$(jq -r '.dependencies.wrangler' "${role_dir}/bun-tools/package.json")"
bun_identity="$(
  sha256sum "${role_dir}/bun-tools/package.json" "${role_dir}/bun-tools/bun.lock" |
    sha256sum |
    awk '{ print $1 }'
)"
bun_root="${HOME}/.local/share/homelab-bun-tools"
bun_prefix="${bun_root}/${bun_identity}"

bun_command_matches() {
  local executable="$1"
  local expected="$2"
  local output version_regex
  version_regex="${expected//./\\.}"
  output="$("${local_bin}/mise" exec -- "$executable" --version 2>&1 || true)"
  [[ "$output" =~ (^|[^0-9.])${version_regex}([^0-9.]|$) ]]
}

if ! [ -x "${bun_prefix}/node_modules/.bin/openspec" ] ||
   ! bun_command_matches "${bun_prefix}/node_modules/.bin/openspec" "$openspec_version" ||
   ! [ -x "${bun_prefix}/node_modules/.bin/wrangler" ] ||
   ! bun_command_matches "${bun_prefix}/node_modules/.bin/wrangler" "$wrangler_version"; then
  bun_stage="${temp_root}/bun-tools"
  mkdir -p "$bun_stage"
  install -m644 "${role_dir}/bun-tools/package.json" "$bun_stage/package.json"
  install -m644 "${role_dir}/bun-tools/bun.lock" "$bun_stage/bun.lock"
  (cd "$bun_stage" && "${local_bin}/mise" exec -- bun install --frozen-lockfile --production)
  bun_command_matches "${bun_stage}/node_modules/.bin/openspec" "$openspec_version" ||
    die "staged openspec does not report version ${openspec_version}"
  bun_command_matches "${bun_stage}/node_modules/.bin/wrangler" "$wrangler_version" ||
    die "staged wrangler does not report version ${wrangler_version}"
  mkdir -p "$bun_root"
  if [ -e "$bun_prefix" ]; then
    bun_prefix="${bun_root}/${bun_identity}.$$"
  fi
  mv -- "$bun_stage" "$bun_prefix"
fi

for command_version in "openspec|${openspec_version}" "wrangler|${wrangler_version}"; do
  command_name="${command_version%%|*}"
  version="${command_version#*|}"
  bun_command_matches "${bun_prefix}/node_modules/.bin/${command_name}" "$version" ||
    die "Bun command ${command_name} does not report version ${version}"
done
for bun_command in openspec wrangler; do
  staged_path="${local_bin}/.${bun_command}.new.$$"
  ln -s "${bun_prefix}/node_modules/.bin/${bun_command}" "$staged_path"
  mv -fT -- "$staged_path" "${local_bin}/${bun_command}"
  staged_path=
done

reconcile_debian_compatibility_link() {
  local command_name="$1"
  local trusted_target="$2"
  local destination="${local_bin}/${command_name}"
  local current_target

  [ -f "$trusted_target" ] && [ ! -L "$trusted_target" ] &&
    [ -x "$trusted_target" ] ||
    die "trusted Debian compatibility target is missing or unsafe: ${trusted_target}"

  if [ -L "$destination" ]; then
    current_target="$(readlink "$destination")"
    [ "$current_target" = "$trusted_target" ] && return
  elif [ -e "$destination" ]; then
    die "Debian compatibility target already exists and is not a symlink: ${destination}"
  fi

  staged_path="${local_bin}/.${command_name}.new.$$"
  [ ! -e "$staged_path" ] && [ ! -L "$staged_path" ] ||
    die "staged Debian compatibility target already exists: ${staged_path}"
  ln -s "$trusted_target" "$staged_path"
  mv -fT -- "$staged_path" "$destination"
  staged_path=

  [ -L "$destination" ] &&
    [ "$(readlink "$destination")" = "$trusted_target" ] &&
    [ -x "$destination" ] ||
    die "Debian compatibility link failed post-install verification: ${destination}"
}

require_commands readlink
reconcile_debian_compatibility_link fd "$debian_fd_target"
reconcile_debian_compatibility_link bat "$debian_bat_target"

echo 'debian-dev-headless software reconciliation complete; credentials remain unenrolled'
