## 1. Characterization and Safety Tests

- [ ] 1.1 Extend the isolated harness to initialize an empty home explicitly and record complete files, symlinks, directory modes, and managed targets across two applies.
- [ ] 1.2 Add a five-role managed-target test that rejects repository metadata and enforces the exact Debian headless CLI allowlist without `--exclude encrypted`.
- [ ] 1.3 Add copied-fixture negative tests for missing validator commands, malformed or duplicate manifest fields, prohibited declared tools, unsafe archive members, mismatched versions or locks, and a wrong 1Password fingerprint.
- [ ] 1.4 Add dry-run characterization that proves role and platform selection uses the same reachable path as real execution and performs no download or mutation.

## 2. Role and Deployment Contract

- [ ] 2.1 Refactor Chezmoi initialization to validate the five supported roles, derive distro without a second contradictory prompt, and expose `secretless` and `headless` booleans.
- [ ] 2.2 Replace repeated container/headless compound template conditions with the derived role capabilities.
- [ ] 2.3 Implement the Debian headless CLI allowlist and exclude AeroSpace, Niri, Noctalia, Ghostty, Obsidian, repository metadata, SSH, encrypted secrets, and the Age identity.
- [ ] 2.4 Render every role in isolation and confirm existing macOS, Arch, Fedora, and container target ownership is unchanged except for global repository-metadata exclusions.

## 3. Debian System Package Ownership

- [ ] 3.1 Remove `debian-snapshot.env`, snapshot-source generation, and the generated-source prerequisite from the installer and tests.
- [ ] 3.2 Keep `packages.txt` as the native additive package-name manifest and validate uniqueness, package-name syntax, and prohibited declarations using only pre-APT base commands.
- [ ] 3.3 Make `--system` require root and Debian 13, run signed APT metadata refresh against homelab-owned configuration, verify every package has a candidate, and install the declared set without modifying sources or keyrings.
- [ ] 3.4 Update system-phase dry-run output and failure messages for missing candidates, unsupported platforms, and wrong privilege.

## 4. Native User-Tool Reconciliation

- [ ] 4.1 Remove `tool-catalog.tsv` and derive a unique command inventory from the mise, vendor, 1Password, Bun, compatibility-link, and Debian declarations.
- [ ] 4.2 Split validation into base structural checks and full user/CI checks with explicit command preflights and fail-closed status propagation.
- [ ] 4.3 Harden vendor rows with allowed formats, HTTPS URLs, full SHA-256 values, safe command/member paths, unique owners, and bidirectional version checks.
- [ ] 4.4 Commit the expected 1Password fingerprint and reject its release signature unless the imported key matches `3FEF9748469ADBE15DA7CA80AC2D62742012EA22`.
- [ ] 4.5 Prepend and directly inspect the managed local-bin path, install through temporary targets, post-verify exact versions before replacement, and clean all temporary paths through one exit trap.
- [ ] 4.6 Keep reconciliation additive, stop rejecting pre-existing engines or session managers, and verify a second user-phase run performs no unnecessary replacement.

## 5. Shared Shell Supply Chain

- [ ] 5.1 Add managed Zsh metadata for Antidote commit `4913257e0ae3fee2a77e7189e526fe55b6ff9536`.
- [ ] 5.2 Add the five approved `pin:<SHA>` plugin commits to `.zsh_plugins.txt` and validate every declaration has a full revision.
- [ ] 5.3 Reconcile Antidote to the committed revision only when absent or mismatched, and degrade to a usable shell with a warning when the required fetch is unavailable.
- [ ] 5.4 Syntax-render Zsh configuration for all roles and test pinned, mismatched, and offline startup paths without modifying the real home.

## 6. Bootstrap and Documentation

- [ ] 6.1 Remove Debian headless execution and dry-run routing from the curl-capable main bootstrap while preserving all established platform branches.
- [ ] 6.2 Revert the macOS npm-to-Bun change and confirm macOS documentation and dry-run output again match npm ownership.
- [ ] 6.3 Document the canonical local-checkout sequence: root `--system`, unprivileged `--user`, role-aware `chezmoi init --source <checkout> --no-tty`, then separate `chezmoi apply`.
- [ ] 6.4 Document rolling Debian package semantics, exact user-tool semantics, additive removal policy, homelab trust ownership, and credential non-enrollment.

## 7. Final Validation and Rollout Evidence

- [ ] 7.1 Run `git diff --check`, Bash syntax checks, all isolated and negative tests, apply-twice verification, and strict OpenSpec validation.
- [ ] 7.2 Resolve official Arch package names with `pacman -Sp` if implementation changes any Arch package manifest.
- [ ] 7.3 Run the documented system and user phases in a disposable Debian 13 console with homelab-provided APT trust and record sanitized package and command-version evidence.
- [ ] 7.4 Initialize and apply the role only in the disposable console, verify the exact secretless CLI target set, and document rollback without deleting packages, credentials, instances, or retained volumes.
- [ ] 7.5 Open a separate homelab specification follow-up reconciling rolling Debian packages here with any exact OpenSSH or Mosh wording in the developer-console contract.
