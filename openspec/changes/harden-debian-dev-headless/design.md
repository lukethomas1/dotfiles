## Context

The WIP profile combines Chezmoi role changes, a root package phase, an
unprivileged tool phase, multiple lock formats, and shared shell behavior. Its
current code writes homelab-owned APT configuration, overstates snapshot
reproducibility, deploys non-headless content, duplicates inventory, fails open
when `rg` is missing, and documents a first apply without prior initialization.

Homelab already defines the developer console as a private, non-root,
secretless supervision host whose root filesystem is replaceable. It owns the
account, network, SSH service, trust, access, and retained storage. This
repository owns developer packages, unprivileged tools, and user configuration.

The desired flow is:

```text
homelab: Debian 13 + attested APT trust + account/access
                         |
                         v
local checkout --system (root, additive APT packages)
                         |
                         v
                 --user (pinned user tools)
                         |
                         v
       chezmoi init(role=headless) -> chezmoi apply
                         |
                         v
             exact secretless CLI target set
```

## Goals / Non-Goals

**Goals:**

- Establish one owner and one native source of truth for every installed item.
- Make the headless first-install workflow executable from an empty home.
- Enforce a small CLI-only managed target set and secretless boundary.
- Fail closed on missing validators or unauthenticated artifacts.
- Keep system reconciliation privilege-separated and user reconciliation
  deterministic and repeatable.
- Pin the shared Antidote/plugin supply chain across every profile.

**Non-Goals:**

- Managing homelab-owned APT sources, keyrings, account, SSH daemon, network,
  mounts, DNS, access policy, or retained volumes.
- Uninstalling undeclared software or enforcing absence of pre-existing
  container/session tools.
- Enrolling credentials or exercising real system/apply mutations in normal
  repository tests.

## Decisions

### 1. Homelab attests trust; this repository owns additive package selection

The system phase will delete its snapshot-source generation and require a
root-owned `/etc/homelab/developer-console-apt-trust` attestation for the
signed Debian 13 APT configuration already present on the host. The attestation
records its schema, role, operating system, rolling suites, and source/keyring
state identities. The system phase rejects a stale or malformed attestation,
runs `apt-get update`, verifies a candidate for every package, then installs
the package-name manifest additively.

Fixture-root attestation checks use a dedicated
`--verify-apt-attestation <absolute-root>` mode that never invokes APT. The
live `--system` phase rejects fixture root, alternate OS-release, and alternate
role-manifest overrides and always validates the real host before mutation.

The attestation is a narrow cross-repository interface: homelab remains free to
organize source files but must prove that the currently active source and
keyring state still matches its policy. Parsing origin policy independently in
both repositories was rejected because APT signature enforcement and
repository selection are homelab's authority. A frozen snapshot was rejected
in favor of timely rolling stable/security updates.

### 2. Exact pinning remains mandatory above the Debian package layer

Mise, Bun, direct vendor downloads, 1Password, Antidote, and Zsh plugins remain
exactly pinned. The committed 1Password public key must match fingerprint
`3FEF9748469ADBE15DA7CA80AC2D62742012EA22` before its signature is trusted.
Only regular `op` and `op.sig` archive members are streamed to private
temporary files, and GPG `VALIDSIG` status must identify that fingerprint as
the actual signer or primary key. The authenticated `op` payload also has a
committed SHA-256 identity.

The durable console matches the homelab repository's protected client
versions: Pulumi `3.253.0`, Talos `1.13.6`, kubectl `1.36.2`, and Cilium CLI
`0.19.2`. Cilium CLI is distinct from the cluster's Cilium `1.19.6`
chart/application version. Upgrading these clients requires a coordinated
homelab compatibility change rather than an independent dotfiles bump.

Antidote will use commit `4913257e0ae3fee2a77e7189e526fe55b6ff9536`
from a managed `.config/zsh/antidote.version`. Plugin declarations will use
Antidote's `pin:<SHA>` syntax with these known-working commits:

- zsh-abbr: `889f4772c12b9dbe4965bbd56f2572af0a28fa3b`
- zsh-job-queue: `b1657094313d598434e38f9ef6e2d10107f58c45`
- fast-syntax-highlighting: `3d574ccf48804b10dca52625df13da5edae7f553`
- zsh-autosuggestions: `85919cd1ffa7d2d5412f6d3fe437ebdbeeec4fc5`
- zsh-completions: `f63d0e642261e40dfaadfcef478ef338e1aa315f`

Shell startup compares the local Antidote revision, fetches only when missing
or mismatched, and degrades with a warning rather than breaking the shell when
offline. A portable adjacent lock serializes clone, fetch, and checkout so
concurrent shells cannot nest or corrupt the checkout. A missing PID receives
the normal bounded initialization grace, ownership is accepted only after PID
publication and readback, and release removes only a lock still owned by the
current shell.

### 3. Native manifests replace the duplicate tool catalog

`packages.txt`, `mise.toml` plus `mise.lock`, `vendor-tools.tsv`,
`onepassword.env`, and Bun's `package.json` plus `bun.lock` are authoritative.
`tool-catalog.tsv` and `debian-snapshot.env` are removed. Validation builds the
inventory from native declarations and checks ownership and version agreement
bidirectionally. A small `required-commands.tsv` contains only functional group
and command names; it independently proves the promised command floor without
duplicating versions or installation ownership.

A custom all-in-one manifest was rejected because it would require generating
and reviewing native lock formats. Keeping the catalog was rejected because it
duplicates version and ownership data without installing anything.

### 4. Validation is phased and fail-closed

The pre-APT system checks use only Bash and base `grep`/`awk` functionality.
Full user/CI validation explicitly preflights commands such as `jq`, `rg`,
`sha256sum`, and format-specific tools. Missing commands return nonzero; no
`|| true` path may turn validator failure into success.

Negative tests operate on copied fixtures so missing required commands,
malformed fields, unsafe archive members, duplicate owners, mismatched locks,
wrong fingerprints, wrong signers, and wrong installed payloads can be
exercised without altering authoritative manifests. Pre-system `--dry-run`
uses only base validation, reports that full checks are deferred, and remains
usable before `jq` is installed.

### 5. Headless deployment is an allowlist

Chezmoi data retains `role` and `distro` and adds derived `secretless` and
`headless` booleans after strict role validation. The headless role manages
only Bash, Zsh, pinned plugin metadata, Git, Neovim, Starship, Atuin, and Herdr
configuration. All desktop, terminal-emulator, Obsidian, repository metadata,
SSH, encrypted secret, and Age identity targets are excluded.

The headless ignore template starts by ignoring every source target and then
unignores only the approved roots and descendants. The managed-target test
remains defense in depth. This was selected over accumulating negative desktop
exceptions because new source content must not silently expand a durable
secretless console.

The managed Git configuration ends with an include of `~/.gitconfig-local`.
The secretless baseline keeps signing disabled; manual enrollment creates a
unique per-console SSH signing key and enables SSH signing only in that
unmanaged root-local file.

### 6. Installer modes stay explicit

The dedicated installer retains `--system`, `--user`, `--dry-run`, and
`--verify-manifests`, plus a non-mutating
`--verify-apt-attestation <absolute-root>` mode. The root and user phases
reject the wrong effective user.
The user phase prepends and directly verifies the managed local-bin path, uses
one global temporary-directory trap, rejects links and non-regular managed
targets, verifies installed payload digests, installs via temporary targets,
and post-verifies versions before replacement.

The curl-capable main bootstrap removes its headless execution branch because
it cannot supply companion manifests or perform the explicit privilege
handoff. Documentation requires a local checkout, both installer phases,
role-aware `chezmoi init --source <checkout> --no-tty`, and a separate apply.

Debian compatibility commands use only the fixed package paths
`/usr/bin/fdfind` and `/usr/bin/batcat`. Correct links are retained, incorrect
links are atomically repaired, and regular files, directories, or other
unexpected destination objects are preserved with a fail-closed error.

### 7. Existing profiles retain ownership

The accidental macOS npm-to-Bun change is reverted. macOS, Arch, Fedora, and
container package flows otherwise remain unchanged. Shared shell pinning is the
only intentional cross-profile runtime change.

## Risks / Trade-offs

- **Rolling APT versions weaken temporal reproducibility** → Record that the
  package set, not exact Debian versions, is reproducible here; homelab remains
  responsible for image/root reproducibility and requires a follow-up spec
  clarification for pinned OpenSSH/Mosh language.
- **Candidate-only checks trust homelab source selection** → Preserve exclusive
  APT trust ownership, require its current state attestation, and fail when
  Debian 13 or any required candidate is absent; do not create a second
  source-policy authority here.
- **First shell startup still needs network access** → Pin all Git identities,
  skip unavailable plugins with a clear warning, and keep the base shell usable.
- **Additive reconciliation leaves removed software installed** → Avoid
  destructive cross-owner cleanup; report undeclared managed-path artifacts
  for manual review instead.
- **WIP baseline contains known defects** → Keep remediation isolated in this
  change so the baseline commit remains a recovery checkpoint, not a release
  recommendation.

## Migration Plan

1. Refactor templates, ignores, manifests, installer, shared shell pins, tests,
   and documentation without applying to a real home.
2. Run strict OpenSpec, syntax, negative-boundary, five-role render, and
   apply-twice validation.
3. Exercise `--system` and `--user` on a disposable Debian 13 console with
   homelab-provided APT trust.
4. Initialize and apply the role on that disposable console, verify the exact
   managed set and command versions, then promote the same reviewed change to
   the durable console.
5. Roll back by reverting the implementation commit and restoring the prior
   Chezmoi source revision; do not remove packages, credentials, instances, or
   retained volumes automatically.

## Open Questions

None. The ownership, update, deployment, pinning, reconciliation, and
compatibility decisions are fixed by this proposal.
