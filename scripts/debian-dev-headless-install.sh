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

script_dir="${BASH_SOURCE[0]%/*}"
[ "$script_dir" != "${BASH_SOURCE[0]}" ] || script_dir=.
source_dir="$(CDPATH= cd -- "${script_dir}/.." && pwd)"
role_dir="${DEBIAN_DEV_HEADLESS_ROLE_DIR:-${source_dir}/pkg/debian-dev-headless}"
os_release_file="${DEBIAN_DEV_HEADLESS_OS_RELEASE:-/etc/os-release}"
local_bin="${HOME}/.local/bin"
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

for role_input in packages.txt mise.toml mise.lock vendor-tools.tsv onepassword.env bun-tools/package.json bun-tools/bun.lock; do
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
    $0 ~ /^(docker|podman|containerd|docker-ce|docker.io|nerdctl|tmux|zellij)$/ { ok=0 }
    END { exit ok ? 0 : 1 }
  ' "${role_dir}/packages.txt" ||
    die 'packages.txt contains an invalid, duplicate, or prohibited package'
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
    NF!=7 { ok=0; next }
    !safe_name($1) || $2 !~ /^[0-9]+(\.[0-9]+)+$/ || !safe_name($3) { ok=0 }
    seen_tool[$1]++ || seen_command[$3]++ { ok=0 }
    $3 ~ /^(docker|podman|containerd|dockerd|nerdctl|ctr|tmux|zellij)$/ { ok=0 }
    $4 !~ /^(binary|tar\.gz)$/ { ok=0 }
    $5 !~ /^https:\/\// { ok=0 }
    $6 !~ /^[0-9a-f]+$/ || length($6)!=64 { ok=0 }
    $4=="binary" && $7!="-" { ok=0 }
    $4=="tar.gz" && !safe_member($7) { ok=0 }
    END { exit ok ? 0 : 1 }
  ' "${role_dir}/vendor-tools.tsv" ||
    die 'vendor-tools.tsv contains an invalid, duplicate, prohibited, or unsafe row'
}

verify_onepassword_manifest() {
  awk -F= '
    BEGIN { ok=1 }
    /^[[:space:]]*#/ || NF==0 { next }
    NF!=2 { ok=0; next }
    !($1 ~ /^ONEPASSWORD_(CLI_VERSION|SIGNING_KEY_URL|ARTIFACT_BASE|SIGNING_KEY_FINGERPRINT)$/) { ok=0 }
    seen[$1]++ { ok=0 }
    $1=="ONEPASSWORD_CLI_VERSION" && $2 !~ /^[0-9]+\.[0-9]+\.[0-9]+$/ { ok=0 }
    ($1=="ONEPASSWORD_SIGNING_KEY_URL" || $1=="ONEPASSWORD_ARTIFACT_BASE") &&
      $2 !~ /^https:\/\/[A-Za-z0-9._~:\/?&=%+-]+$/ { ok=0 }
    $1=="ONEPASSWORD_SIGNING_KEY_FINGERPRINT" &&
      ($2!="3FEF9748469ADBE15DA7CA80AC2D62742012EA22") { ok=0 }
    END {
      required[1]="ONEPASSWORD_CLI_VERSION"
      required[2]="ONEPASSWORD_SIGNING_KEY_URL"
      required[3]="ONEPASSWORD_ARTIFACT_BASE"
      required[4]="ONEPASSWORD_SIGNING_KEY_FINGERPRINT"
      for (i=1; i<=4; i++) if (seen[required[i]]!=1) ok=0
      exit ok ? 0 : 1
    }
  ' "${role_dir}/onepassword.env" ||
    die 'onepassword.env is incomplete or invalid'
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
  done < "${role_dir}/packages.txt"

  while IFS='|' read -r key version; do
    [ -n "$key" ] || continue
    command_name="$(mise_command_for_key "$key")" ||
      die "no command inventory mapping for mise tool: ${key}"
    printf '%s|mise:%s@%s\n' "$command_name" "$key" "$version"
  done < <(mise_config_entries)

  awk -F'|' '!/^[[:space:]]*#/ && NF { print $3 "|vendor:" $1 "@" $2 }' \
    "${role_dir}/vendor-tools.tsv"
  printf '%s\n' 'op|signed-vendor:1password'
  printf '%s\n' 'openspec|bun:@fission-ai/openspec' 'wrangler|bun:wrangler'
  printf '%s\n' 'fd|compat:fd-find' 'bat|compat:bat'
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

verify_full_manifests() {
  require_commands jq sort
  verify_mise_lock
  verify_bun_lock
  verify_unique_inventory
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

verify_base_manifests

if [ "$mode" = verify-manifests ]; then
  verify_full_manifests
  echo 'debian-dev-headless native manifests are pinned, consistent, and fail-closed'
  exit 0
fi

verify_platform

if [ "$mode" = dry-run ]; then
  verify_full_manifests
  echo 'Dry run: no package, download, home, shell, or credential changes will be made.'
  echo '  require homelab-owned signed Debian 13 stable/security APT trust'
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
  [ "$(id -u)" -eq 0 ] ||
    die '--system must run as root before the user phase'
  require_commands apt-get apt-cache

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
require_commands chmod curl dpkg-query gpg grep install ln mkdir mktemp mv rm sha256sum tar unzip

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

install_verified_command() {
  local source_path="$1"
  local command_name="$2"
  local version="$3"
  staged_path="${local_bin}/.${command_name}.new.$$"

  install -m755 "$source_path" "$staged_path"
  version_matches "$staged_path" "$version" || {
    die "staged ${command_name} does not report version ${version}"
  }
  mv -f -- "$staged_path" "${local_bin}/${command_name}"
  staged_path=
}

while IFS='|' read -r tool version command_name format url digest member; do
  case "$tool" in ''|'#'*) continue ;; esac
  if [ -x "${local_bin}/${command_name}" ] &&
     version_matches "${local_bin}/${command_name}" "$version"; then
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
      ;;
    *)
      die "unsupported vendor format for ${tool}: ${format}"
      ;;
  esac

  install_verified_command "$candidate" "$command_name" "$version"
done < "${role_dir}/vendor-tools.tsv"

manifest_value() {
  local key="$1"
  awk -F= -v key="$key" '$1==key { print substr($0, index($0, "=")+1); exit }' \
    "${role_dir}/onepassword.env"
}
ONEPASSWORD_CLI_VERSION="$(manifest_value ONEPASSWORD_CLI_VERSION)"
ONEPASSWORD_SIGNING_KEY_URL="$(manifest_value ONEPASSWORD_SIGNING_KEY_URL)"
ONEPASSWORD_SIGNING_KEY_FINGERPRINT="$(manifest_value ONEPASSWORD_SIGNING_KEY_FINGERPRINT)"
ONEPASSWORD_ARTIFACT_BASE="$(manifest_value ONEPASSWORD_ARTIFACT_BASE)"
if [ ! -x "${local_bin}/op" ] ||
   ! version_matches "${local_bin}/op" "$ONEPASSWORD_CLI_VERSION"; then
  op_dir="${temp_root}/onepassword"
  mkdir -p "${op_dir}/gnupg"
  chmod 700 "${op_dir}/gnupg"
  curl --fail --location --silent --show-error \
    "${ONEPASSWORD_ARTIFACT_BASE}/op_linux_amd64_v${ONEPASSWORD_CLI_VERSION}.zip" \
    --output "${op_dir}/op.zip"
  unzip -q "${op_dir}/op.zip" -d "$op_dir"
  curl --fail --location --silent --show-error \
    "$ONEPASSWORD_SIGNING_KEY_URL" --output "${op_dir}/1password.asc"
  GNUPGHOME="${op_dir}/gnupg" gpg --batch --import "${op_dir}/1password.asc"
  signing_fingerprint="$(
    GNUPGHOME="${op_dir}/gnupg" gpg --batch --with-colons --fingerprint |
      awk -F: '$1=="fpr" { print $10; exit }'
  )"
  [ "$signing_fingerprint" = "$ONEPASSWORD_SIGNING_KEY_FINGERPRINT" ] ||
    die "unexpected 1Password signing-key fingerprint: ${signing_fingerprint:-missing}"
  GNUPGHOME="${op_dir}/gnupg" gpg --batch --verify "${op_dir}/op.sig" "${op_dir}/op"
  install_verified_command "${op_dir}/op" op "$ONEPASSWORD_CLI_VERSION"
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

command -v fdfind >/dev/null && ln -sfn "$(command -v fdfind)" "${local_bin}/fd"
command -v batcat >/dev/null && ln -sfn "$(command -v batcat)" "${local_bin}/bat"

echo 'debian-dev-headless software reconciliation complete; credentials remain unenrolled'
