#!/usr/bin/env bash
set -euo pipefail

source_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
role_dir="${source_dir}/pkg/debian-dev-headless"
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT
mkdir -p "${test_root}/home" "${test_root}/cache" "${test_root}/config"
export HOME="${test_root}/home"
export XDG_CONFIG_HOME="${test_root}/config"

bash -n "${source_dir}/bootstrap.sh" "${source_dir}/scripts/debian-dev-headless-install.sh"
"${source_dir}/scripts/debian-dev-headless-install.sh" --verify-manifests
grep -Fq -- '--system must run as root' \
  "${source_dir}/scripts/debian-dev-headless-install.sh"
grep -Fq -- '--user refuses root' \
  "${source_dir}/scripts/debian-dev-headless-install.sh"
grep -Fq 'debian-dev-headless-install.sh" --user' \
  "${source_dir}/bootstrap.sh"
if rg -n '(^|[[:space:]])sudo([[:space:]]|$)' \
  "${source_dir}/scripts/debian-dev-headless-install.sh" >/dev/null; then
  echo 'ERROR: split installer must not depend on sudo' >&2
  exit 1
fi
CHEZMOI_ROLE=debian-dev-headless chezmoi init --source "$source_dir" --config-path "${test_root}/chezmoi.toml" --no-tty
chezmoi_cmd=(chezmoi --config "${test_root}/chezmoi.toml" --source "$source_dir" --destination "${test_root}/home" --cache "${test_root}/cache" --persistent-state "${test_root}/state")
CHEZMOI_ROLE=debian-dev-headless "${chezmoi_cmd[@]}" apply --force --no-tty --refresh-externals=never --exclude encrypted --exclude scripts
find "${test_root}/home" -type f -print0 | sort -z | xargs -0 sha256sum > "${test_root}/first.sha256"
CHEZMOI_ROLE=debian-dev-headless "${chezmoi_cmd[@]}" apply --force --no-tty --refresh-externals=never --exclude encrypted --exclude scripts
find "${test_root}/home" -type f -print0 | sort -z | xargs -0 sha256sum > "${test_root}/second.sha256"
cmp "${test_root}/first.sha256" "${test_root}/second.sha256"
CHEZMOI_ROLE=debian-dev-headless "${chezmoi_cmd[@]}" verify --no-tty --refresh-externals=never --exclude encrypted --exclude scripts

if find "${test_root}/home" -type f \( -path '*/.ssh/*' -o -name '*secret*' -o -name '*.age' -o -name 'key.txt' \) -print -quit | rg -q .; then
  echo 'ERROR: secret/SSH material rendered' >&2
  exit 1
fi

for required in foundation shell-editor runtimes infrastructure delivery-security agent-repository; do
  awk -F'|' -v group="$required" '$1==group { found=1 } END { exit found ? 0 : 1 }' "${role_dir}/tool-catalog.tsv"
done
for required in bun node go python uv pulumi op incus talosctl kubectl helm kustomize flux cilium sops age restic cloudflared wrangler dagger cosign syft grype trivy gitleaks tea gh codex herdr openspec; do
  awk -F'|' -v command="$required" '$2==command { found=1 } END { exit found ? 0 : 1 }' "${role_dir}/tool-catalog.tsv"
done
awk -F'|' '$2=="node" && $3=="mise-runtime-only" { found=1 } END { exit found ? 0 : 1 }' "${role_dir}/tool-catalog.tsv"
echo 'isolated debian-dev-headless render/apply-twice, exclusion, and inventory tests passed'
