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
expect_failure missing-validator 'required validation command is unavailable: jq' \
  env PATH="$minimal_bin" /bin/bash "$installer" --verify-manifests

fixture="$(new_fixture duplicate-vendor)"
sed -n '2p' "${fixture}/vendor-tools.tsv" >>"${fixture}/vendor-tools.tsv"
expect_failure duplicate-vendor 'vendor-tools.tsv contains an invalid' \
  env DEBIAN_DEV_HEADLESS_ROLE_DIR="$fixture" "$installer" --verify-manifests

fixture="$(new_fixture prohibited-package)"
printf '%s\n' docker >>"${fixture}/packages.txt"
expect_failure prohibited-package 'packages.txt contains an invalid' \
  env DEBIAN_DEV_HEADLESS_ROLE_DIR="$fixture" "$installer" --verify-manifests

fixture="$(new_fixture duplicate-owner)"
sed -i 's/|herdr|binary|/|jq|binary|/' "${fixture}/vendor-tools.tsv"
expect_failure duplicate-owner 'command has multiple manifest owners: jq' \
  env DEBIAN_DEV_HEADLESS_ROLE_DIR="$fixture" "$installer" --verify-manifests

fixture="$(new_fixture unsafe-member)"
sed -i 's#|codex-x86_64-unknown-linux-musl$#|../codex#' "${fixture}/vendor-tools.tsv"
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
sed -i 's/3FEF9748469ADBE15DA7CA80AC2D62742012EA22/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA/' \
  "${fixture}/onepassword.env"
expect_failure wrong-fingerprint 'onepassword.env is incomplete or invalid' \
  env DEBIAN_DEV_HEADLESS_ROLE_DIR="$fixture" "$installer" --verify-manifests

debian_os="${test_root}/debian-os-release"
unsupported_os="${test_root}/unsupported-os-release"
printf 'ID=debian\nVERSION_ID=13\n' >"$debian_os"
printf 'ID=debian\nVERSION_ID=12\n' >"$unsupported_os"
dry_home="${test_root}/dry-home"
mkdir -p "$dry_home"
snapshot_tree "$dry_home" >"${test_root}/dry-before.tree"
HOME="$dry_home" DEBIAN_DEV_HEADLESS_OS_RELEASE="$debian_os" \
  "$installer" --dry-run >"${test_root}/dry-run.out"
snapshot_tree "$dry_home" >"${test_root}/dry-after.tree"
cmp "${test_root}/dry-before.tree" "${test_root}/dry-after.tree"
grep -Fq 'homelab-owned signed Debian 13 stable/security APT trust' \
  "${test_root}/dry-run.out"
expect_failure unsupported-platform 'Debian 13 is required' \
  env HOME="$dry_home" DEBIAN_DEV_HEADLESS_OS_RELEASE="$unsupported_os" \
  "$installer" --dry-run

expect_failure system-privilege '--system must run as root' \
  env HOME="$dry_home" DEBIAN_DEV_HEADLESS_OS_RELEASE="$debian_os" \
  "$installer" --system

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
chmod +x "${fake_system_bin}/id" "${fake_system_bin}/apt-cache" \
  "${fake_system_bin}/apt-get"
fake_apt_log="${test_root}/fake-apt.log"
: >"$fake_apt_log"
expect_failure missing-candidate 'no APT candidate is available for package: bash' \
  env HOME="$dry_home" PATH="${fake_system_bin}:/usr/bin:/bin" \
  FAKE_APT_LOG="$fake_apt_log" DEBIAN_DEV_HEADLESS_OS_RELEASE="$debian_os" \
  "$installer" --system
grep -Fqx update "$fake_apt_log" ||
  fail 'candidate test did not refresh metadata'
if grep -Fq install "$fake_apt_log"; then
  fail 'candidate failure invoked bulk package installation'
fi

expect_failure user-privilege '--user refuses root' \
  env HOME="$dry_home" PATH="${fake_system_bin}:/usr/bin:/bin" \
  DEBIAN_DEV_HEADLESS_OS_RELEASE="$debian_os" "$installer" --user

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

echo 'debian-dev-headless isolated, role-boundary, negative, dry-run, and shell-pin tests passed'
