## 1. Characterization and Safety Tests

- [x] 1.1 Extend the isolated harness to initialize an empty home explicitly and record complete files, symlinks, directory modes, and managed targets across two applies.
- [x] 1.2 Add a five-role managed-target test that rejects repository metadata and enforces the exact Debian headless CLI allowlist without `--exclude encrypted`.
- [x] 1.3 Add copied-fixture negative tests for missing validator commands, malformed or duplicate manifest fields, prohibited declared tools, unsafe archive members, mismatched versions or locks, and a wrong 1Password fingerprint.
- [x] 1.4 Add dry-run characterization that proves role and platform selection uses the same reachable path as real execution and performs no download or mutation.

## 2. Role and Deployment Contract

- [x] 2.1 Refactor Chezmoi initialization to validate the five supported roles, derive distro without a second contradictory prompt, and expose `secretless` and `headless` booleans.
- [x] 2.2 Replace repeated container/headless compound template conditions with the derived role capabilities.
- [x] 2.3 Implement the Debian headless CLI allowlist and exclude AeroSpace, Niri, Noctalia, Ghostty, Obsidian, repository metadata, SSH, encrypted secrets, and the Age identity.
- [x] 2.4 Render every role in isolation and confirm macOS, Arch, Fedora, and container targets obey the main profile-ownership specification plus global repository-metadata exclusions.

## 3. Debian System Package Ownership

- [x] 3.1 Remove `debian-snapshot.env`, snapshot-source generation, and the generated-source prerequisite from the installer and tests.
- [x] 3.2 Keep `packages.txt` as the native additive package-name manifest and validate uniqueness and package-name syntax using only pre-APT base commands.
- [x] 3.3 Make `--system` require root and Debian 13, validate the current homelab APT trust attestation, refresh signed metadata, verify every package has a candidate, and install the declared set without modifying sources or keyrings.
- [x] 3.4 Update system-phase dry-run output and failure messages for missing candidates, unsupported platforms, and wrong privilege.

## 4. Native User-Tool Reconciliation

- [x] 4.1 Remove `tool-catalog.tsv`, derive a unique command inventory from native declarations, and enforce a separate versionless group/command completeness catalog.
- [x] 4.2 Split validation into base structural checks and full user/CI checks with explicit command preflights and fail-closed status propagation.
- [x] 4.3 Harden vendor rows with artifact and installed-payload SHA-256 identities, allowed formats, safe command/member paths, unique owners, and bidirectional version checks.
- [x] 4.4 Commit the expected 1Password public key and payload digest; safely select `op`/`op.sig` and require `VALIDSIG` to resolve to fingerprint `3FEF9748469ADBE15DA7CA80AC2D62742012EA22`.
- [x] 4.5 Reject links/non-regular managed commands, verify installed identities, repair mismatches through authenticated temporary targets, and preserve prior commands on failure.
- [x] 4.6 Keep reconciliation additive, remove console-specific engine/session-manager name bans, and verify a second user-phase run performs no unnecessary replacement.
- [x] 4.7 Make pre-system `--dry-run` base-only and explicitly defer full jq-dependent validation.

## 5. Shared Shell Supply Chain

- [x] 5.1 Add managed Zsh metadata for Antidote commit `4913257e0ae3fee2a77e7189e526fe55b6ff9536`.
- [x] 5.2 Add the five approved `pin:<SHA>` plugin commits to `.zsh_plugins.txt` and validate every declaration has a full revision.
- [x] 5.3 Reconcile Antidote to the committed revision only when absent or mismatched, and degrade to a usable shell with a warning when the required fetch is unavailable.
- [x] 5.4 Syntax-render Zsh configuration for all roles and test pinned, mismatched, and offline startup paths without modifying the real home.
- [x] 5.5 Serialize Antidote clone/fetch/checkout with a portable bounded lock and test concurrent, live-lock, and stale-lock paths.

## 6. Bootstrap and Documentation

- [x] 6.1 Remove Debian headless execution and dry-run routing from the curl-capable main bootstrap while preserving all established platform branches.
- [x] 6.2 Revert the macOS npm-to-Bun change and confirm macOS documentation and dry-run output again match npm ownership.
- [x] 6.3 Document the canonical local-checkout sequence: root `--system`, unprivileged `--user`, role-aware `chezmoi init --source <checkout> --no-tty`, then separate `chezmoi apply`.
- [x] 6.4 Document rolling Debian package semantics, exact user-tool semantics, additive removal policy, homelab trust ownership, and credential non-enrollment.
- [x] 6.5 Add the unmanaged `~/.gitconfig-local` enrollment boundary and document unique per-console SSH Git signing.
- [x] 6.6 Change the headless ignore template to ignore-all/allow-specific and prove an unclassified fixture target remains unmanaged.

## 7. Final Validation and Rollout Evidence

- [x] 7.1 Run `git diff --check`, Bash syntax checks, all isolated and negative tests, apply-twice verification, and strict OpenSpec validation.
- [x] 7.2 Resolve official Arch package names with `pacman -Sp` if implementation changes any Arch package manifest. (Not applicable: no Arch package manifest changed.)
- [x] 7.3 Run the documented system and user phases in a disposable Debian 13 console with homelab-provided APT trust and record sanitized package and command-version evidence.
- [x] 7.4 Initialize and apply the role only in the disposable console, verify the exact secretless CLI target set, and document rollback without deleting packages, credentials, instances, or retained volumes.
- [x] 7.5 Reconcile the homelab developer-console change with rolling Debian trust, the APT attestation, unique Git signing enrollment, and unrestricted reviewed tool ownership.
- [x] 7.6 Run adversarial deletion, wrong-payload, signer, ZIP, minimal dry-run, Git include, allowlist, and Antidote concurrency tests plus strict OpenSpec validation.

## 8. Adversarial Review Corrections

- [x] 8.1 Align Pulumi, Talos, kubectl, and Cilium CLI declarations and the Linux x64 Mise lock with the exact homelab compatibility gates.
- [x] 8.2 Add a dedicated non-mutating APT attestation verifier and make live `--system` reject all fixture-root, alternate-platform, and alternate-role inputs before APT execution.
- [x] 8.3 Make Antidote lock PID publication, initialization grace, and owner-matching release race-safe.
- [x] 8.4 Reconcile Debian `fd` and `bat` aliases from fixed package paths, atomically repair links, and preserve unexpected destination objects.
- [x] 8.5 Add negative and concurrency regression tests for tool pins, APT mutation isolation, the lock publication interval, ownership changes, PATH shadowing, and alias collisions.
- [x] 8.6 Re-run isolated validation, syntax checks, strict OpenSpec validation, diff hygiene, and focused secret scanning without applying to a real console.
