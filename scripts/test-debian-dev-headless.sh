#!/usr/bin/env bash
set -euo pipefail

source_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
installer="${source_dir}/scripts/debian-dev-headless-install.sh"
role_dir="${source_dir}/pkg/debian-dev-headless"
test_root="$(mktemp -d)"
trap 'rm -rf -- "$test_root"' EXIT

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

expect_failure() {
  local label="$1"
  local expected="$2"
  shift 2
  if "$@" >"${test_root}/${label}.out" 2>&1; then
    fail "${label} unexpectedly succeeded"
  fi
  grep -Fq -- "$expected" "${test_root}/${label}.out" ||
    fail "${label} did not report: ${expected}"
}

new_fixture() {
  local name="$1"
  local fixture="${test_root}/fixtures/${name}"
  mkdir -p "${test_root}/fixtures"
  cp -a "${role_dir}" "$fixture"
  printf '%s\n' "$fixture"
}

make_zip() {
  local output="$1"
  shift
  python3 - "$output" "$@" <<'PY'
import pathlib
import sys
import zipfile

output = pathlib.Path(sys.argv[1])
with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as archive:
    for name in sys.argv[2:]:
        path = pathlib.Path(name)
        archive.write(path, arcname=path.name)
PY
}

snapshot_tree() {
  local root="$1"
  (
    cd "$root"
    find . -mindepth 1 -print0 |
      sort -z |
      while IFS= read -r -d '' entry; do
        relative="${entry#./}"
        mode="$(stat -c '%a' -- "$entry")"
        if [ -L "$entry" ]; then
          printf 'L|%s|%s|%s\n' "$mode" "$relative" "$(readlink -- "$entry")"
        elif [ -f "$entry" ]; then
          digest="$(sha256sum -- "$entry")"
          printf 'F|%s|%s|%s\n' "$mode" "$relative" "${digest%% *}"
        elif [ -d "$entry" ]; then
          printf 'D|%s|%s\n' "$mode" "$relative"
        else
          printf 'O|%s|%s\n' "$mode" "$relative"
        fi
      done
  )
}

managed_for_role() {
  local role="$1"
  local root="${test_root}/roles/${role}"
  mkdir -p "${root}/home" "${root}/cache" "${root}/config"
  HOME="${root}/home" XDG_CONFIG_HOME="${root}/config" CHEZMOI_ROLE="$role" \
    chezmoi init --source "$source_dir" --config-path "${root}/chezmoi.toml" --no-tty
  local chezmoi_cmd=(
    chezmoi
    --config "${root}/chezmoi.toml"
    --source "$source_dir"
    --destination "${root}/home"
    --cache "${root}/cache"
    --persistent-state "${root}/state"
  )
  HOME="${root}/home" XDG_CONFIG_HOME="${root}/config" CHEZMOI_ROLE="$role" \
    "${chezmoi_cmd[@]}" managed --path-style=relative >"${root}/managed"
  HOME="${root}/home" XDG_CONFIG_HOME="${root}/config" CHEZMOI_ROLE="$role" \
    "${chezmoi_cmd[@]}" execute-template <"${source_dir}/dot_zshrc.tmpl" \
    >"${root}/zshrc"
  zsh -n "${root}/zshrc"
}

assert_managed() {
  local role="$1"
  local target="$2"
  grep -Fqx -- "$target" "${test_root}/roles/${role}/managed" ||
    fail "${role} must manage ${target}"
}

assert_unmanaged_prefix() {
  local role="$1"
  local prefix="$2"
  if grep -Eq "^${prefix}(/|$)" "${test_root}/roles/${role}/managed"; then
    fail "${role} must not manage ${prefix}"
  fi
}

bash -n "${source_dir}/bootstrap.sh" "$installer" "$0"
"$installer" --verify-manifests
grep -Fqx '"aqua:pulumi/pulumi" = "3.253.0"' \
  "${role_dir}/mise.toml" ||
  fail 'Pulumi pin does not match the homelab execution gate'
grep -Fqx '"aqua:siderolabs/talos" = "1.13.6"' \
  "${role_dir}/mise.toml" ||
  fail 'Talos pin does not match the homelab execution gate'
grep -Fqx '"aqua:kubernetes/kubernetes/kubectl" = "1.36.2"' \
  "${role_dir}/mise.toml" ||
  fail 'kubectl pin does not match the homelab execution gate'
grep -Fqx '"aqua:cilium/cilium-cli" = "0.19.2"' \
  "${role_dir}/mise.toml" ||
  fail 'Cilium CLI pin does not match the homelab execution gate'

if rg -n '(^|[[:space:]])sudo([[:space:]]|$)' "$installer" >/dev/null; then
  fail 'the split installer must not depend on sudo'
fi
if rg -n 'debian-dev-headless' "${source_dir}/bootstrap.sh" >/dev/null; then
  fail 'the curl-capable bootstrap must not route the Debian headless role'
fi
grep -Fq 'npm install -g @devcontainers/cli' "${source_dir}/bootstrap.sh" ||
  fail 'macOS bootstrap must retain npm ownership for devcontainers CLI'

for role in macos arch fedora container debian-dev-headless; do
  managed_for_role "$role"
  managed_file="${test_root}/roles/${role}/managed"
  if grep -Eq '^(AGENTS\.md|README\.md|TESTING\.md|bootstrap\.sh|openspec|scripts|pkg|archive|assets|\.codex)(/|$)' \
    "$managed_file"; then
    fail "${role} exposes repository metadata"
  fi
done

assert_managed macos .config/aerospace/aerospace.toml
assert_unmanaged_prefix macos '\.config/niri'
assert_unmanaged_prefix macos '\.config/noctalia'
assert_unmanaged_prefix macos '\.bashrc'

assert_managed arch .config/niri/config.kdl
assert_managed arch .config/noctalia/settings.json
assert_unmanaged_prefix arch '\.config/aerospace'

assert_unmanaged_prefix fedora '\.config/aerospace'
assert_unmanaged_prefix fedora '\.config/niri'
assert_unmanaged_prefix fedora '\.config/noctalia'
assert_unmanaged_prefix fedora '\.bashrc'

for role in container debian-dev-headless; do
  assert_unmanaged_prefix "$role" '\.ssh'
  assert_unmanaged_prefix "$role" '\.config/secrets\.env'
  assert_unmanaged_prefix "$role" '\.config/chezmoi/key\.txt'
  assert_unmanaged_prefix "$role" '\.config/aerospace'
  assert_unmanaged_prefix "$role" '\.config/ghostty'
  assert_unmanaged_prefix "$role" '\.config/niri'
  assert_unmanaged_prefix "$role" '\.config/noctalia'
  assert_unmanaged_prefix "$role" '\.Documents'
  assert_unmanaged_prefix "$role" '\.local'
done

while IFS= read -r target; do
  case "$target" in
    .bashrc|.zshrc|.zsh_plugins.txt|.gitconfig|.config|\
    .config/zsh|.config/zsh/*|\
    .config/nvim|.config/nvim/*|\
    .config/starship.toml|\
    .config/atuin|.config/atuin/*|\
    .config/herdr|.config/herdr/*)
      ;;
    *)
      fail "Debian headless target is outside the CLI allowlist: ${target}"
      ;;
  esac
done <"${test_root}/roles/debian-dev-headless/managed"

headless_root="${test_root}/roles/debian-dev-headless"
headless_cmd=(
  chezmoi
  --config "${headless_root}/chezmoi.toml"
  --source "$source_dir"
  --destination "${headless_root}/home"
  --cache "${headless_root}/cache"
  --persistent-state "${headless_root}/state"
)
HOME="${headless_root}/home" XDG_CONFIG_HOME="${headless_root}/config" \
  CHEZMOI_ROLE=debian-dev-headless \
  "${headless_cmd[@]}" apply --force --no-tty --refresh-externals=never
snapshot_tree "${headless_root}/home" >"${headless_root}/first.tree"
HOME="${headless_root}/home" XDG_CONFIG_HOME="${headless_root}/config" \
  CHEZMOI_ROLE=debian-dev-headless \
  "${headless_cmd[@]}" managed --path-style=relative >"${headless_root}/first.managed"
HOME="${headless_root}/home" XDG_CONFIG_HOME="${headless_root}/config" \
  CHEZMOI_ROLE=debian-dev-headless \
  "${headless_cmd[@]}" apply --force --no-tty --refresh-externals=never
snapshot_tree "${headless_root}/home" >"${headless_root}/second.tree"
HOME="${headless_root}/home" XDG_CONFIG_HOME="${headless_root}/config" \
  CHEZMOI_ROLE=debian-dev-headless \
  "${headless_cmd[@]}" managed --path-style=relative >"${headless_root}/second.managed"
cmp "${headless_root}/first.tree" "${headless_root}/second.tree"
cmp "${headless_root}/first.managed" "${headless_root}/second.managed"
HOME="${headless_root}/home" XDG_CONFIG_HOME="${headless_root}/config" \
  CHEZMOI_ROLE=debian-dev-headless \
  "${headless_cmd[@]}" verify --no-tty --refresh-externals=never

grep -Fq $'path = ~/.gitconfig-local' "${headless_root}/home/.gitconfig" ||
  fail 'headless Git config does not include the unmanaged local enrollment file'
printf '%s\n' \
  '[gpg]' \
  '    format = ssh' \
  '[user]' \
  '    signingkey = ~/.ssh/id_ed25519_signing.pub' \
  '[commit]' \
  '    gpgsign = true' >"${headless_root}/home/.gitconfig-local"
HOME="${headless_root}/home" \
  git config --file "${headless_root}/home/.gitconfig" --includes \
    --get commit.gpgsign |
  grep -Fqx true ||
  fail 'unmanaged local Git include did not override the unsigned baseline'
assert_unmanaged_prefix debian-dev-headless '\.gitconfig-local'

allowlist_source="${test_root}/allowlist-source"
cp -a --reflink=auto "${source_dir}" "${allowlist_source}"
printf 'must remain unmanaged\n' >"${allowlist_source}/dot_unclassified"
allowlist_root="${test_root}/allowlist-role"
mkdir -p "${allowlist_root}/home" "${allowlist_root}/config"
HOME="${allowlist_root}/home" XDG_CONFIG_HOME="${allowlist_root}/config" \
  CHEZMOI_ROLE=debian-dev-headless \
  chezmoi init --source "${allowlist_source}" \
    --config-path "${allowlist_root}/chezmoi.toml" --no-tty
HOME="${allowlist_root}/home" XDG_CONFIG_HOME="${allowlist_root}/config" \
  CHEZMOI_ROLE=debian-dev-headless \
  chezmoi --config "${allowlist_root}/chezmoi.toml" \
    --source "${allowlist_source}" \
    --destination "${allowlist_root}/home" \
    --cache "${allowlist_root}/cache" \
    --persistent-state "${allowlist_root}/state" \
    managed --path-style=relative >"${allowlist_root}/managed"
if grep -Fqx .unclassified "${allowlist_root}/managed"; then
  fail 'ignore-all headless policy admitted an unclassified source target'
fi

expect_failure unsupported-role 'unsupported CHEZMOI_ROLE' \
  env HOME="${test_root}/unsupported-home" CHEZMOI_ROLE=unknown \
  chezmoi init --source "$source_dir" --config-path "${test_root}/unsupported.toml" --no-tty

empty_config="${test_root}/empty.toml"
: >"$empty_config"
expect_failure missing-role-data 'run CHEZMOI_ROLE=<role> chezmoi init' \
  chezmoi --config "$empty_config" --source "$source_dir" \
  --destination "${test_root}/uninitialized-home" \
  --cache "${test_root}/uninitialized-cache" \
  --persistent-state "${test_root}/uninitialized-state" managed

stale_config="${test_root}/stale.toml"
printf '[data]\nrole = "debian-dev-headless"\ndistro = "debian"\n' >"$stale_config"
expect_failure stale-role-data 'stale secretless role data' \
  chezmoi --config "$stale_config" --source "$source_dir" \
  --destination "${test_root}/stale-home" --cache "${test_root}/stale-cache" \
  --persistent-state "${test_root}/stale-state" managed

default_root="${test_root}/default-source"
mkdir -p "${default_root}/home/.local/share" "${default_root}/config"
ln -s "$source_dir" "${default_root}/home/.local/share/chezmoi"
HOME="${default_root}/home" XDG_CONFIG_HOME="${default_root}/config" \
  CHEZMOI_ROLE=debian-dev-headless \
  chezmoi init --source "${default_root}/home/.local/share/chezmoi" --no-tty
grep -Fq 'role = "debian-dev-headless"' \
  "${default_root}/config/chezmoi/chezmoi.toml" ||
  fail 'default-source initialization did not create headless role data'

minimal_bin="${test_root}/minimal-bin"
mkdir -p "$minimal_bin"
ln -s "$(command -v awk)" "${minimal_bin}/awk"
ln -s "$(command -v grep)" "${minimal_bin}/grep"
ln -s "$(command -v uname)" "${minimal_bin}/uname"
expect_failure missing-validator 'required validation command is unavailable: jq' \
  env PATH="$minimal_bin" /bin/bash "$installer" --verify-manifests

fixture="$(new_fixture duplicate-vendor)"
sed -n '2p' "${fixture}/vendor-tools.tsv" >>"${fixture}/vendor-tools.tsv"
expect_failure duplicate-vendor 'vendor-tools.tsv contains an invalid' \
  env DEBIAN_DEV_HEADLESS_ROLE_DIR="$fixture" "$installer" --verify-manifests

fixture="$(new_fixture invalid-package)"
printf '%s\n' 'Docker Engine' >>"${fixture}/packages.txt"
expect_failure invalid-package 'packages.txt contains an invalid' \
  env DEBIAN_DEV_HEADLESS_ROLE_DIR="$fixture" "$installer" --verify-manifests

for permitted in docker podman containerd tmux zellij; do
  fixture="$(new_fixture "permitted-${permitted}")"
  printf '%s\n' "$permitted" >>"${fixture}/packages.txt"
  if env DEBIAN_DEV_HEADLESS_ROLE_DIR="$fixture" \
    "$installer" --verify-manifests >"${test_root}/permitted-${permitted}.out" 2>&1; then
    fail "${permitted} fixture unexpectedly passed without an inventory mapping"
  fi
  grep -Fq 'no command inventory mapping' \
    "${test_root}/permitted-${permitted}.out" ||
    fail "${permitted} was rejected by a prohibited-name policy"
done

fixture="$(new_fixture duplicate-owner)"
sed -i 's/|herdr|binary|/|jq|binary|/' "${fixture}/vendor-tools.tsv"
expect_failure duplicate-owner 'command has multiple manifest owners: jq' \
  env DEBIAN_DEV_HEADLESS_ROLE_DIR="$fixture" "$installer" --verify-manifests

fixture="$(new_fixture unsafe-member)"
sed -i 's#|codex-x86_64-unknown-linux-musl|#|../codex|#' "${fixture}/vendor-tools.tsv"
expect_failure unsafe-member 'vendor-tools.tsv contains an invalid' \
  env DEBIAN_DEV_HEADLESS_ROLE_DIR="$fixture" "$installer" --verify-manifests

fixture="$(new_fixture mise-lock-mismatch)"
sed -i 's/bun = "1.3.14"/bun = "1.3.13"/' "${fixture}/mise.toml"
expect_failure mise-lock-mismatch 'mise.lock is missing or mismatches' \
  env DEBIAN_DEV_HEADLESS_ROLE_DIR="$fixture" "$installer" --verify-manifests

fixture="$(new_fixture bun-lock-mismatch)"
sed -i 's/"wrangler": "4.114.0"/"wrangler": "4.113.0"/' "${fixture}/bun-tools/package.json"
expect_failure bun-lock-mismatch 'bun.lock does not match wrangler@4.113.0' \
  env DEBIAN_DEV_HEADLESS_ROLE_DIR="$fixture" "$installer" --verify-manifests

fixture="$(new_fixture wrong-fingerprint)"
sed -i 's/3FEF9748469ADBE15DA7CA80AC2D62742012EA22/AAAAAAAA/' \
  "${fixture}/onepassword.env"
expect_failure wrong-fingerprint 'onepassword.env is incomplete or invalid' \
  env DEBIAN_DEV_HEADLESS_ROLE_DIR="$fixture" "$installer" --verify-manifests

fixture="$(new_fixture missing-apt-command)"
sed -i '/^git$/d' "${fixture}/packages.txt"
expect_failure missing-apt-command \
  'required command has no native manifest owner: foundation|git' \
  env DEBIAN_DEV_HEADLESS_ROLE_DIR="$fixture" "$installer" --verify-manifests

fixture="$(new_fixture missing-mise-command)"
sed -i '/^go = /d' "${fixture}/mise.toml"
expect_failure missing-mise-command \
  'required command has no native manifest owner: runtimes|go' \
  env DEBIAN_DEV_HEADLESS_ROLE_DIR="$fixture" "$installer" --verify-manifests

fixture="$(new_fixture missing-vendor-command)"
sed -i '/^codex|/d' "${fixture}/vendor-tools.tsv"
expect_failure missing-vendor-command \
  'required command has no native manifest owner: agent-repository|codex' \
  env DEBIAN_DEV_HEADLESS_ROLE_DIR="$fixture" "$installer" --verify-manifests

fixture="$(new_fixture missing-bun-command)"
sed -i '\#"@fission-ai/openspec":#d' "${fixture}/bun-tools/package.json"
expect_failure missing-bun-command \
  'required command has no native manifest owner: agent-repository|openspec' \
  env DEBIAN_DEV_HEADLESS_ROLE_DIR="$fixture" "$installer" --verify-manifests

fixture="$(new_fixture missing-onepassword-entry)"
sed -i '/^ONEPASSWORD_BINARY_SHA256=/d' "${fixture}/onepassword.env"
expect_failure missing-onepassword-entry 'onepassword.env is incomplete or invalid' \
  env DEBIAN_DEV_HEADLESS_ROLE_DIR="$fixture" "$installer" --verify-manifests

debian_os="${test_root}/debian-os-release"
unsupported_os="${test_root}/unsupported-os-release"
printf 'ID=debian\nVERSION_ID=13\n' >"$debian_os"
printf 'ID=debian\nVERSION_ID=12\n' >"$unsupported_os"
dry_home="${test_root}/dry-home"
mkdir -p "$dry_home"
minimal_dry_home="${test_root}/minimal-dry-home"
mkdir -p "${minimal_dry_home}"
env HOME="${minimal_dry_home}" PATH="${minimal_bin}" \
  DEBIAN_DEV_HEADLESS_OS_RELEASE="$debian_os" \
  /bin/bash "$installer" --dry-run >"${test_root}/minimal-dry-run.out"
grep -Fq 'full jq-dependent lock and inventory validation is deferred' \
  "${test_root}/minimal-dry-run.out" ||
  fail 'minimal dry run did not report deferred full validation'
snapshot_tree "$dry_home" >"${test_root}/dry-before.tree"
HOME="$dry_home" DEBIAN_DEV_HEADLESS_OS_RELEASE="$debian_os" \
  "$installer" --dry-run >"${test_root}/dry-run.out"
snapshot_tree "$dry_home" >"${test_root}/dry-after.tree"
cmp "${test_root}/dry-before.tree" "${test_root}/dry-after.tree"
grep -Fq 'homelab-attested Debian 13 stable/security APT trust state' \
  "${test_root}/dry-run.out"
expect_failure unsupported-platform 'Debian 13 is required' \
  env HOME="$dry_home" DEBIAN_DEV_HEADLESS_OS_RELEASE="$unsupported_os" \
  "$installer" --dry-run

expect_failure system-privilege '--system must run as root' \
  env HOME="$dry_home" "$installer" --system

fake_system_bin="${test_root}/fake-system-bin"
mkdir -p "$fake_system_bin"
cat >"${fake_system_bin}/id" <<'EOF'
#!/usr/bin/env bash
printf '0\n'
EOF
cat >"${fake_system_bin}/apt-cache" <<'EOF'
#!/usr/bin/env bash
printf '  Candidate: (none)\n'
EOF
cat >"${fake_system_bin}/apt-get" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${FAKE_APT_LOG}"
EOF
cat >"${fake_system_bin}/stat" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = -c ] && [ "${2:-}" = '%U:%G:%a' ]; then
  printf 'root:root:644\n'
else
  exec /usr/bin/stat "$@"
fi
EOF
chmod +x "${fake_system_bin}/id" "${fake_system_bin}/apt-cache" \
  "${fake_system_bin}/apt-get" "${fake_system_bin}/stat"

apt_root="${test_root}/apt-root"
mkdir -p \
  "${apt_root}/etc/apt/sources.list.d" \
  "${apt_root}/etc/homelab" \
  "${apt_root}/usr/share/keyrings"
cp "$debian_os" "${apt_root}/etc/os-release"
printf '%s\n' \
  'Types: deb' \
  'URIs: https://deb.debian.org/debian' \
  'Suites: trixie trixie-updates' \
  'Components: main' \
  'Signed-By: /usr/share/keyrings/debian-archive-keyring.pgp' \
  '' \
  'Types: deb' \
  'URIs: https://security.debian.org/debian-security' \
  'Suites: trixie-security' \
  'Components: main' \
  'Signed-By: /usr/share/keyrings/debian-archive-keyring.pgp' \
  >"${apt_root}/etc/apt/sources.list.d/debian.sources"
printf 'fixture Debian archive keyring\n' \
  >"${apt_root}/usr/share/keyrings/debian-archive-keyring.pgp"
source_sha="$(sha256sum "${apt_root}/etc/apt/sources.list.d/debian.sources")"
keyring_sha="$(sha256sum "${apt_root}/usr/share/keyrings/debian-archive-keyring.pgp")"
apt_config_sha="$(
  {
    printf 'etc/apt/sources.list.d/debian.sources|%s\n' "${source_sha%% *}"
  } | sha256sum | awk '{ print $1 }'
)"
printf '%s\n' \
  'schema=1' \
  'role=debian-dev-headless' \
  'os_id=debian' \
  'version_id=13' \
  'suites=trixie,trixie-updates,trixie-security' \
  "apt_config_sha256=${apt_config_sha}" \
  "source_sha256=${source_sha%% *}" \
  "keyring_sha256=${keyring_sha%% *}" \
  >"${apt_root}/etc/homelab/developer-console-apt-trust"
chmod 0644 "${apt_root}/etc/homelab/developer-console-apt-trust"

fake_apt_log="${test_root}/fake-apt.log"
: >"$fake_apt_log"
HOME="$dry_home" PATH="${fake_system_bin}:/usr/bin:/bin" \
  FAKE_APT_LOG="$fake_apt_log" \
  "$installer" --verify-apt-attestation "$apt_root" \
  >"${test_root}/apt-verifier.out"
grep -Fq 'verified without mutation' "${test_root}/apt-verifier.out" ||
  fail 'dedicated APT verifier did not report success'
[ ! -s "$fake_apt_log" ] ||
  fail 'dedicated APT verifier invoked an APT command'

printf '# state changed after attestation\n' \
  >>"${apt_root}/etc/apt/sources.list.d/debian.sources"
: >"$fake_apt_log"
expect_failure stale-apt-trust \
  'homelab APT source identity has changed since attestation' \
  env HOME="$dry_home" PATH="${fake_system_bin}:/usr/bin:/bin" \
  FAKE_APT_LOG="$fake_apt_log" \
  "$installer" --verify-apt-attestation "$apt_root"
[ ! -s "$fake_apt_log" ] ||
  fail 'stale APT trust invoked apt-get'

for fixture_override in \
  DEBIAN_DEV_HEADLESS_APT_ROOT \
  DEBIAN_DEV_HEADLESS_OS_RELEASE \
  DEBIAN_DEV_HEADLESS_ROLE_DIR \
  DEBIAN_DEV_HEADLESS_SOURCE_DIR; do
  : >"$fake_apt_log"
  expect_failure "system-${fixture_override}" \
    "--system refuses fixture override: ${fixture_override}" \
    env HOME="$dry_home" PATH="${fake_system_bin}:/usr/bin:/bin" \
    FAKE_APT_LOG="$fake_apt_log" "${fixture_override}=$apt_root" \
    "$installer" --system
  [ ! -s "$fake_apt_log" ] ||
    fail "--system invoked APT with ${fixture_override}"
done

expect_failure user-privilege '--user refuses root' \
  env HOME="$dry_home" PATH="${fake_system_bin}:/usr/bin:/bin" \
  DEBIAN_DEV_HEADLESS_OS_RELEASE="$debian_os" "$installer" --user

user_installer="${test_root}/debian-dev-headless-user-install.sh"
compat_bin="${test_root}/trusted-debian-bin"
mkdir -p "$compat_bin"
printf '#!/usr/bin/env bash\nprintf "fd fixture\\n"\n' >"${compat_bin}/fdfind"
printf '#!/usr/bin/env bash\nprintf "bat fixture\\n"\n' >"${compat_bin}/batcat"
chmod +x "${compat_bin}/fdfind" "${compat_bin}/batcat"
cp "$installer" "$user_installer"
sed -i \
  -e "s#^debian_fd_target=/usr/bin/fdfind\$#debian_fd_target=${compat_bin}/fdfind#" \
  -e "s#^debian_bat_target=/usr/bin/batcat\$#debian_bat_target=${compat_bin}/batcat#" \
  "$user_installer"
bash -n "$user_installer"
export DEBIAN_DEV_HEADLESS_SOURCE_DIR="$source_dir"

user_fixture="$(new_fixture user-reconciliation)"
printf '%s\n' \
  '# group|command' \
  'shell-editor|mise' \
  'infrastructure|op' \
  'agent-repository|codex' \
  >"${user_fixture}/required-commands.tsv"
user_root="${test_root}/user-reconciliation"
user_home="${user_root}/home"
user_bin="${user_root}/bin"
artifacts="${user_root}/artifacts"
mkdir -p "${user_home}/.local/bin" "$user_bin" "$artifacts"

cat >"${artifacts}/mise-good" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = --version ]; then
  printf 'mise 2026.7.13\n'
elif [ "${1:-}" = install ]; then
  exit 0
elif [ "${1:-}" = exec ]; then
  shift 2
  case "${1:-}" in
    */node_modules/.bin/*) exec "$@" ;;
    *) printf '%s\n' '1.3.14 22.23.1 1.26.5 3.14.6 0.11.32 3.253.0 1.13.6 1.36.2 4.2.3 5.8.1 2.9.3 0.19.2 3.13.3 0.21.7 3.1.2 1.49.0 0.116.0 0.72.0 8.30.1 2.96.0 0.63.1 0.19.2 1.26.0 18.17.1 0.23.5 0.10.0 2.71.0' ;;
  esac
else
  exit 2
fi
EOF
cat >"${artifacts}/mise-bad" <<'EOF'
#!/usr/bin/env bash
printf 'mise 2026.7.13\n'
EOF
cat >"${artifacts}/codex-good" <<'EOF'
#!/usr/bin/env bash
printf 'codex-cli 0.145.0\n'
EOF
cat >"${artifacts}/codex-bad" <<'EOF'
#!/usr/bin/env bash
# Wrong payload that deliberately reports the pinned version.
printf 'codex-cli 0.145.0\n'
EOF
cat >"${artifacts}/op" <<'EOF'
#!/usr/bin/env bash
printf '2.35.0\n'
EOF
chmod +x "${artifacts}/mise-good" "${artifacts}/mise-bad" \
  "${artifacts}/codex-good" "${artifacts}/codex-bad" "${artifacts}/op"
tar -czf "${artifacts}/codex.tar.gz" \
  -C "$artifacts" --transform='s/codex-good/codex/' codex-good

mise_digest="$(sha256sum "${artifacts}/mise-good")"
codex_artifact_digest="$(sha256sum "${artifacts}/codex.tar.gz")"
codex_payload_digest="$(sha256sum "${artifacts}/codex-good")"
op_digest="$(sha256sum "${artifacts}/op")"
printf '%s\n' \
  '# name|version|command|format|url|artifact-sha256|archive-member|payload-sha256' \
  "mise|2026.7.13|mise|binary|https://fixtures.invalid/mise|${mise_digest%% *}|-|-" \
  >"${user_fixture}/vendor-tools.tsv"
printf '%s\n' \
  "codex|0.145.0|codex|tar.gz|https://fixtures.invalid/codex|${codex_artifact_digest%% *}|codex|${codex_payload_digest%% *}" \
  >>"${user_fixture}/vendor-tools.tsv"
sed -i \
  "s/^ONEPASSWORD_BINARY_SHA256=.*/ONEPASSWORD_BINARY_SHA256=${op_digest%% *}/" \
  "${user_fixture}/onepassword.env"
install -m755 "${artifacts}/mise-bad" "${user_home}/.local/bin/mise"
install -m755 "${artifacts}/codex-bad" "${user_home}/.local/bin/codex"
install -m755 "${artifacts}/op" "${user_home}/.local/bin/op"
printf '#!/usr/bin/env bash\nprintf "untrusted fd\\n"\n' \
  >"${user_home}/.local/bin/fdfind"
printf '#!/usr/bin/env bash\nprintf "untrusted bat\\n"\n' \
  >"${user_home}/.local/bin/batcat"
chmod +x \
  "${user_home}/.local/bin/fdfind" \
  "${user_home}/.local/bin/batcat"

bun_identity="$(
  sha256sum \
    "${user_fixture}/bun-tools/package.json" \
    "${user_fixture}/bun-tools/bun.lock" |
    sha256sum |
    awk '{ print $1 }'
)"
bun_prefix="${user_home}/.local/share/homelab-bun-tools/${bun_identity}"
mkdir -p "${bun_prefix}/node_modules/.bin"
cat >"${bun_prefix}/node_modules/.bin/openspec" <<'EOF'
#!/usr/bin/env bash
printf '1.6.0\n'
EOF
cat >"${bun_prefix}/node_modules/.bin/wrangler" <<'EOF'
#!/usr/bin/env bash
printf '4.114.0\n'
EOF
chmod +x \
  "${bun_prefix}/node_modules/.bin/openspec" \
  "${bun_prefix}/node_modules/.bin/wrangler"

cat >"${user_bin}/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
url=
output=
while (($#)); do
  case "$1" in
    --output) output="$2"; shift 2 ;;
    http*) url="$1"; shift ;;
    *) shift ;;
  esac
done
printf '%s\n' "$url" >>"${FAKE_DOWNLOAD_LOG}"
case "$url" in
  */mise) cp "${FAKE_ARTIFACT_ROOT}/mise-good" "$output" ;;
  */codex) cp "${FAKE_ARTIFACT_ROOT}/codex.tar.gz" "$output" ;;
  *) printf 'ERROR: unexpected fixture URL %s\n' "$url" >&2; exit 1 ;;
esac
EOF
cat >"${user_bin}/dpkg-query" <<'EOF'
#!/usr/bin/env bash
printf 'ii \n'
EOF
chmod +x "${user_bin}/curl" "${user_bin}/dpkg-query"

download_log="${user_root}/downloads"
: >"$download_log"
HOME="$user_home" PATH="${user_bin}:/usr/bin:/bin" \
  FAKE_DOWNLOAD_LOG="$download_log" FAKE_ARTIFACT_ROOT="$artifacts" \
  DEBIAN_DEV_HEADLESS_ROLE_DIR="$user_fixture" \
  DEBIAN_DEV_HEADLESS_OS_RELEASE="$debian_os" \
  "$user_installer" --user
cmp "${artifacts}/mise-good" "${user_home}/.local/bin/mise"
cmp "${artifacts}/codex-good" "${user_home}/.local/bin/codex"
cmp "${user_fixture}/mise.lock" "${user_home}/.config/mise/mise.lock"
[[ ! -e "${user_home}/.config/mise/config.lock" ]] ||
  fail 'Mise lock was installed under an ignored filename'
[[ "$(readlink "${user_home}/.local/bin/fd")" = "${compat_bin}/fdfind" ]] ||
  fail 'fd compatibility link trusted a PATH-shadowing command'
[[ "$(readlink "${user_home}/.local/bin/bat")" = "${compat_bin}/batcat" ]] ||
  fail 'bat compatibility link trusted a PATH-shadowing command'
[[ "$(wc -l <"$download_log")" == 2 ]] ||
  fail 'wrong-payload reconciliation did not download exactly two artifacts'

ln -sfn "${user_home}/.local/bin/fdfind" "${user_home}/.local/bin/fd"
HOME="$user_home" PATH="${user_bin}:/usr/bin:/bin" \
  FAKE_DOWNLOAD_LOG="$download_log" FAKE_ARTIFACT_ROOT="$artifacts" \
  DEBIAN_DEV_HEADLESS_ROLE_DIR="$user_fixture" \
  DEBIAN_DEV_HEADLESS_OS_RELEASE="$debian_os" \
  "$user_installer" --user
[[ "$(wc -l <"$download_log")" == 2 ]] ||
  fail 'second user reconciliation downloaded already verified artifacts'
[[ "$(readlink "${user_home}/.local/bin/fd")" = "${compat_bin}/fdfind" ]] ||
  fail 'incorrect fd compatibility link was not repaired'

rm "${user_home}/.local/bin/fd"
mkdir "${user_home}/.local/bin/fd"
expect_failure compatibility-directory-collision \
  'Debian compatibility target already exists and is not a symlink' \
  env HOME="$user_home" PATH="${user_bin}:/usr/bin:/bin" \
  FAKE_DOWNLOAD_LOG="$download_log" FAKE_ARTIFACT_ROOT="$artifacts" \
  DEBIAN_DEV_HEADLESS_ROLE_DIR="$user_fixture" \
  DEBIAN_DEV_HEADLESS_OS_RELEASE="$debian_os" \
  "$user_installer" --user
[[ -d "${user_home}/.local/bin/fd" ]] ||
  fail 'fd compatibility collision was not preserved'
rmdir "${user_home}/.local/bin/fd"
ln -s "${compat_bin}/fdfind" "${user_home}/.local/bin/fd"

rm "${user_home}/.local/bin/bat"
printf 'preserve user bat target\n' >"${user_home}/.local/bin/bat"
expect_failure compatibility-file-collision \
  'Debian compatibility target already exists and is not a symlink' \
  env HOME="$user_home" PATH="${user_bin}:/usr/bin:/bin" \
  FAKE_DOWNLOAD_LOG="$download_log" FAKE_ARTIFACT_ROOT="$artifacts" \
  DEBIAN_DEV_HEADLESS_ROLE_DIR="$user_fixture" \
  DEBIAN_DEV_HEADLESS_OS_RELEASE="$debian_os" \
  "$user_installer" --user
grep -Fqx 'preserve user bat target' "${user_home}/.local/bin/bat" ||
  fail 'bat compatibility collision was modified'
rm "${user_home}/.local/bin/bat"
ln -s "${compat_bin}/batcat" "${user_home}/.local/bin/bat"

rm "${user_home}/.local/bin/mise"
ln -s "${artifacts}/mise-bad" "${user_home}/.local/bin/mise"
expect_failure unsafe-managed-symlink \
  'managed command target is not a regular file' \
  env HOME="$user_home" PATH="${user_bin}:/usr/bin:/bin" \
  FAKE_DOWNLOAD_LOG="$download_log" FAKE_ARTIFACT_ROOT="$artifacts" \
  DEBIAN_DEV_HEADLESS_ROLE_DIR="$user_fixture" \
  DEBIAN_DEV_HEADLESS_OS_RELEASE="$debian_os" \
  "$user_installer" --user

op_fixture="$(new_fixture onepassword-verification)"
cp "${user_fixture}/required-commands.tsv" "${op_fixture}/required-commands.tsv"
cp "${user_fixture}/vendor-tools.tsv" "${op_fixture}/vendor-tools.tsv"
op_root="${test_root}/onepassword-verification"
op_home="${op_root}/home"
op_bin="${op_root}/bin"
op_artifacts="${op_root}/artifacts"
mkdir -p "$op_root"
cp -a "${user_home}" "${op_home}"
rm -f "${op_home}/.local/bin/mise" "${op_home}/.local/bin/op"
install -m755 "${artifacts}/mise-good" "${op_home}/.local/bin/mise"
mkdir -p "$op_bin" "$op_artifacts"
expected_fingerprint=298F7485D24F445609BE221F467E0816F054CF42
cp "${source_dir}/scripts/testdata/onepassword-expected.asc" \
  "${op_fixture}/onepassword.asc"
cat >"${op_artifacts}/op" <<'EOF'
#!/usr/bin/env bash
printf '2.35.0\n'
EOF
chmod +x "${op_artifacts}/op"
cp "${source_dir}/scripts/testdata/onepassword-expected.sig" \
  "${op_artifacts}/op.sig"
make_zip "${op_artifacts}/op.zip" \
  "${op_artifacts}/op" "${op_artifacts}/op.sig"
op_payload_digest="$(sha256sum "${op_artifacts}/op")"
sed -i \
  -e "s/^ONEPASSWORD_SIGNING_KEY_FINGERPRINT=.*/ONEPASSWORD_SIGNING_KEY_FINGERPRINT=${expected_fingerprint}/" \
  -e 's#^ONEPASSWORD_ARTIFACT_BASE=.*#ONEPASSWORD_ARTIFACT_BASE=https://fixtures.invalid/op#' \
  -e "s/^ONEPASSWORD_BINARY_SHA256=.*/ONEPASSWORD_BINARY_SHA256=${op_payload_digest%% *}/" \
  "${op_fixture}/onepassword.env"
op_bun_identity="$(
  sha256sum \
    "${op_fixture}/bun-tools/package.json" \
    "${op_fixture}/bun-tools/bun.lock" |
    sha256sum |
    awk '{ print $1 }'
)"
op_bun_prefix="${op_home}/.local/share/homelab-bun-tools/${op_bun_identity}"
mkdir -p "${op_bun_prefix}/node_modules/.bin"
install -m755 "${bun_prefix}/node_modules/.bin/openspec" \
  "${op_bun_prefix}/node_modules/.bin/openspec"
install -m755 "${bun_prefix}/node_modules/.bin/wrangler" \
  "${op_bun_prefix}/node_modules/.bin/wrangler"

cat >"${op_bin}/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
output=
while (($#)); do
  case "$1" in
    --output) output="$2"; shift 2 ;;
    *) shift ;;
  esac
done
cp "${FAKE_OP_ZIP}" "$output"
EOF
cp "${user_bin}/dpkg-query" "${op_bin}/dpkg-query"
chmod +x "${op_bin}/curl" "${op_bin}/dpkg-query"

HOME="$op_home" PATH="${op_bin}:/usr/bin:/bin" \
  FAKE_OP_ZIP="${op_artifacts}/op.zip" \
  DEBIAN_DEV_HEADLESS_ROLE_DIR="$op_fixture" \
  DEBIAN_DEV_HEADLESS_OS_RELEASE="$debian_os" \
  "$user_installer" --user
cmp "${op_artifacts}/op" "${op_home}/.local/bin/op"

printf 'unexpected archive member\n' >"${op_artifacts}/README"
make_zip "${op_artifacts}/op-extra.zip" \
  "${op_artifacts}/op" "${op_artifacts}/op.sig" "${op_artifacts}/README"
rm "${op_home}/.local/bin/op"
expect_failure unsafe-op-archive \
  '1Password archive must contain only op and op.sig' \
  env HOME="$op_home" PATH="${op_bin}:/usr/bin:/bin" \
  FAKE_OP_ZIP="${op_artifacts}/op-extra.zip" \
  DEBIAN_DEV_HEADLESS_ROLE_DIR="$op_fixture" \
  DEBIAN_DEV_HEADLESS_OS_RELEASE="$debian_os" \
  "$user_installer" --user

cp "${source_dir}/scripts/testdata/onepassword-other.sig" \
  "${op_artifacts}/op.sig"
make_zip "${op_artifacts}/op-other-signer.zip" \
  "${op_artifacts}/op" "${op_artifacts}/op.sig"
cat "${source_dir}/scripts/testdata/onepassword-other.asc" \
  >>"${op_fixture}/onepassword.asc"
expect_failure extra-op-signer \
  'committed 1Password key must contain exactly one primary key' \
  env HOME="$op_home" PATH="${op_bin}:/usr/bin:/bin" \
  FAKE_OP_ZIP="${op_artifacts}/op-other-signer.zip" \
  DEBIAN_DEV_HEADLESS_ROLE_DIR="$op_fixture" \
  DEBIAN_DEV_HEADLESS_OS_RELEASE="$debian_os" \
  "$user_installer" --user

snapshot_tree "$dry_home" >"${test_root}/bootstrap-before.tree"
HOME="$dry_home" CHEZMOI_ROLE=debian-dev-headless \
  "${source_dir}/bootstrap.sh" --dry-run >"${test_root}/bootstrap-dry.out"
snapshot_tree "$dry_home" >"${test_root}/bootstrap-after.tree"
cmp "${test_root}/bootstrap-before.tree" "${test_root}/bootstrap-after.tree"
if grep -Fq 'Role: debian-dev-headless' "${test_root}/bootstrap-dry.out"; then
  fail 'main bootstrap still advertises Debian headless'
fi

shell_root="${test_root}/shell"
shell_home="${shell_root}/home"
fake_bin="${shell_home}/.local/bin"
commit="$(tr -d '[:space:]' <"${source_dir}/dot_config/zsh/antidote.version")"
mkdir -p "$fake_bin"
cat >"${fake_bin}/git" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
directory=
if [ "${1:-}" = -C ]; then
  directory="$2"
  shift 2
fi
command_name="${1:-}"
printf '%s\n' "$command_name" >>"${ANTIDOTE_TEST_LOG}"
case "$command_name" in
  init)
    mkdir -p "${directory}/.git"
    ;;
  remote)
    ;;
  fetch)
    sleep "${ANTIDOTE_TEST_FETCH_DELAY:-0}"
    [ "${ANTIDOTE_TEST_FETCH_FAIL:-0}" != 1 ]
    ;;
  checkout)
    printf '%s\n' "$ANTIDOTE_TEST_COMMIT" >"${directory}/.fake-head"
    ;;
  rev-parse)
    cat "${directory}/.fake-head"
    ;;
  *)
    exit 2
    ;;
esac
EOF
chmod +x "${fake_bin}/git"

prepare_antidote() {
  local head="$1"
  mkdir -p "${shell_home}/.antidote/.git" "${shell_home}/.config/zsh"
  printf '%s\n' "$head" >"${shell_home}/.antidote/.fake-head"
  printf '%s\n' "$commit" >"${shell_home}/.config/zsh/antidote.version"
  printf '%s\n' 'antidote() { return 0; }' >"${shell_home}/.antidote/antidote.zsh"
}

rendered_zsh="${test_root}/roles/debian-dev-headless/zshrc"
antidote_log="${shell_root}/git.log"
prepare_antidote "$commit"
: >"$antidote_log"
HOME="$shell_home" ANTIDOTE_TEST_LOG="$antidote_log" ANTIDOTE_TEST_COMMIT="$commit" \
  PATH="${fake_bin}:/usr/bin:/bin" zsh -dfc 'source "$1"' _ "$rendered_zsh"
if grep -Fqx fetch "$antidote_log"; then
  fail 'matching Antidote checkout fetched unnecessarily'
fi

prepare_antidote 0000000000000000000000000000000000000000
: >"$antidote_log"
HOME="$shell_home" ANTIDOTE_TEST_LOG="$antidote_log" ANTIDOTE_TEST_COMMIT="$commit" \
  PATH="${fake_bin}:/usr/bin:/bin" zsh -dfc 'source "$1"' _ "$rendered_zsh"
grep -Fqx "$commit" "${shell_home}/.antidote/.fake-head" ||
  fail 'mismatched Antidote checkout was not reconciled'

rm -rf -- "${shell_home}/.antidote"
mkdir -p "${shell_home}/.antidote"
printf '%s\n' preserve >"${shell_home}/.antidote/user-file"
: >"$antidote_log"
HOME="$shell_home" ANTIDOTE_TEST_LOG="$antidote_log" ANTIDOTE_TEST_COMMIT="$commit" \
  PATH="${fake_bin}:/usr/bin:/bin" \
  zsh -dfc 'source "$1"' _ "$rendered_zsh" >"${shell_root}/non-git.out" 2>&1
grep -Fq 'exists but is not a Git checkout' "${shell_root}/non-git.out" ||
  fail 'non-Git Antidote path did not warn'
grep -Fqx preserve "${shell_home}/.antidote/user-file" ||
  fail 'non-Git Antidote path was modified'

rm -rf -- "${shell_home}/.antidote"
mkdir -p "${shell_home}/.config/zsh"
printf '%s\n' "$commit" >"${shell_home}/.config/zsh/antidote.version"
: >"$antidote_log"
HOME="$shell_home" ANTIDOTE_TEST_LOG="$antidote_log" ANTIDOTE_TEST_COMMIT="$commit" \
  ANTIDOTE_TEST_FETCH_FAIL=1 PATH="${fake_bin}:/usr/bin:/bin" \
  zsh -dfc 'source "$1"' _ "$rendered_zsh" >"${shell_root}/offline.out" 2>&1
grep -Fq 'WARN: pinned Antidote is unavailable' "${shell_root}/offline.out" ||
  fail 'offline Antidote startup did not warn'
[ ! -e "${shell_home}/.antidote" ] ||
  fail 'offline Antidote startup left a partial checkout'

rm -rf -- "${shell_home}/.antidote" "${shell_home}/.antidote.lock"
: >"$antidote_log"
HOME="$shell_home" ANTIDOTE_TEST_LOG="$antidote_log" ANTIDOTE_TEST_COMMIT="$commit" \
  ANTIDOTE_TEST_LOCK_PUBLISH_DELAY=0.2 ANTIDOTE_TEST_FETCH_DELAY=0.2 \
  PATH="${fake_bin}:/usr/bin:/bin" \
  zsh -dfc 'source "$1"' _ "$rendered_zsh" >"${shell_root}/concurrent-1.out" 2>&1 &
first_shell_pid=$!
for _ in {1..100}; do
  [[ -d "${shell_home}/.antidote.lock" &&
     ! -e "${shell_home}/.antidote.lock/pid" ]] && break
  sleep 0.01
done
[[ -d "${shell_home}/.antidote.lock" &&
   ! -e "${shell_home}/.antidote.lock/pid" ]] ||
  fail 'Antidote publication-gap fixture was not reached'
HOME="$shell_home" ANTIDOTE_TEST_LOG="$antidote_log" ANTIDOTE_TEST_COMMIT="$commit" \
  ANTIDOTE_TEST_FETCH_DELAY=0.2 PATH="${fake_bin}:/usr/bin:/bin" \
  zsh -dfc 'source "$1"' _ "$rendered_zsh" >"${shell_root}/concurrent-2.out" 2>&1 &
second_shell_pid=$!
wait "$first_shell_pid" "$second_shell_pid"
[[ "$(grep -c '^fetch$' "$antidote_log")" == 1 ]] ||
  fail 'concurrent Antidote startup performed more than one fetch'
[[ ! -e "${shell_home}/.antidote.lock" ]] ||
  fail 'concurrent Antidote startup left its lock behind'
if find "${shell_home}/.antidote" -mindepth 1 -maxdepth 1 \
  -name 'antidote.*' -print -quit | grep -q .; then
  fail 'concurrent Antidote startup nested a temporary checkout'
fi

rm -rf -- "${shell_home}/.antidote"
mkdir -p "${shell_home}/.antidote.lock"
printf '99999999\n' >"${shell_home}/.antidote.lock/pid"
: >"$antidote_log"
HOME="$shell_home" ANTIDOTE_TEST_LOG="$antidote_log" ANTIDOTE_TEST_COMMIT="$commit" \
  PATH="${fake_bin}:/usr/bin:/bin" \
  zsh -dfc 'source "$1"' _ "$rendered_zsh"
[[ -d "${shell_home}/.antidote/.git" && ! -e "${shell_home}/.antidote.lock" ]] ||
  fail 'stale Antidote lock was not safely recovered'

rm -rf -- "${shell_home}/.antidote"
mkdir -p "${shell_home}/.antidote.lock"
: >"$antidote_log"
HOME="$shell_home" ANTIDOTE_TEST_LOG="$antidote_log" ANTIDOTE_TEST_COMMIT="$commit" \
  ANTIDOTE_LOCK_MAX_ATTEMPTS=2 ANTIDOTE_LOCK_WAIT_SECONDS=0.01 \
  PATH="${fake_bin}:/usr/bin:/bin" \
  zsh -dfc 'source "$1"' _ "$rendered_zsh"
[[ -d "${shell_home}/.antidote/.git" && ! -e "${shell_home}/.antidote.lock" ]] ||
  fail 'abandoned ownerless Antidote lock was not recovered after its grace'

sleep 30 &
live_lock_pid=$!
mkdir -p "${shell_home}/.antidote.lock"
printf '%s\n' "$live_lock_pid" >"${shell_home}/.antidote.lock/pid"
HOME="$shell_home" ANTIDOTE_TEST_LOG="$antidote_log" ANTIDOTE_TEST_COMMIT="$commit" \
  ANTIDOTE_LOCK_MAX_ATTEMPTS=1 ANTIDOTE_LOCK_WAIT_SECONDS=0.01 \
  PATH="${fake_bin}:/usr/bin:/bin" \
  zsh -dfc 'source "$1"' _ "$rendered_zsh" >"${shell_root}/live-lock.out" 2>&1
kill "$live_lock_pid"
wait "$live_lock_pid" 2>/dev/null || true
grep -Fq 'timed out waiting for Antidote reconciliation' \
  "${shell_root}/live-lock.out" ||
  fail 'live Antidote lock did not produce the bounded timeout warning'
[[ -d "${shell_home}/.antidote.lock" ]] ||
  fail 'live Antidote lock was incorrectly removed by a non-owner'
rm -f "${shell_home}/.antidote.lock/pid"
rmdir "${shell_home}/.antidote.lock"

rm -rf -- "${shell_home}/.antidote"
: >"$antidote_log"
HOME="$shell_home" ANTIDOTE_TEST_LOG="$antidote_log" ANTIDOTE_TEST_COMMIT="$commit" \
  ANTIDOTE_TEST_FETCH_DELAY=0.3 PATH="${fake_bin}:/usr/bin:/bin" \
  zsh -dfc 'source "$1"' _ "$rendered_zsh" \
  >"${shell_root}/changed-owner.out" 2>&1 &
changed_owner_shell_pid=$!
for _ in {1..100}; do
  [[ -f "${shell_home}/.antidote.lock/pid" ]] && break
  sleep 0.01
done
[[ -f "${shell_home}/.antidote.lock/pid" ]] ||
  fail 'Antidote changed-owner fixture did not acquire the lock'
printf '%s\n' "$$" >"${shell_home}/.antidote.lock/pid"
wait "$changed_owner_shell_pid"
grep -Fq 'lock ownership changed; preserving it' \
  "${shell_root}/changed-owner.out" ||
  fail 'Antidote release did not warn about changed ownership'
[[ -d "${shell_home}/.antidote.lock" ]] ||
  fail 'Antidote release removed another owner lock'
rm -f "${shell_home}/.antidote.lock/pid"
rmdir "${shell_home}/.antidote.lock"

echo 'debian-dev-headless isolated, role-boundary, negative, dry-run, and shell-pin tests passed'
