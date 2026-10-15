# Tasks

## 1. Acceptance and workflow readiness

- [ ] 1.1 Obtain explicit acceptance of this contract and record the accepted
  scope in acceptance.md; verify that no executable Beads task predates it.
- [ ] 1.2 Add the missing project workflow manifest/schema/templates without
  replacing existing OpenSpec configuration or AGENTS.md; resolve or record the
  OpenSpec doctor compatibility issue, then require workflow validation to pass.
- [ ] 1.3 Convert the accepted contract into a local Beads epic and dependency
  graph, record beads.md, and create the isolated implementation worktree; verify
  path ownership and preservation of all unrelated main-worktree edits.

## 2. Native desktop configuration

- [ ] 2.1 Translate the saved preferences into managed native TOML, archive the
  v4 JSON, and document GUI override precedence and visible v5 differences;
  verify warning-free native validation and every preference mapping.
- [ ] 2.2 Replace Noctalia startup and IPC command strings while preserving
  physical chords, modifiers, and existing OpenWhispr edits; verify complete Niri
  config validation and the keyboard portion of the capability test plan.
- [ ] 2.3 Reconcile the Arch manifest to the official native package after the
  required Bash/diff/package-name checks; verify the rendered package plan has
  one Noctalia owner and no legacy runtime declarations.
- [ ] 2.4 Update archive/workflow exclusions as needed and validate all five
  roles with isolated rendering, negative-boundary checks, and double-apply
  idempotence; verify the capability test plan without changing the live home.

## 3. Review and activation

- [ ] 3.1 Run strict OpenSpec and workflow validation, commit the implementation,
  and obtain independent post-commit review; verify all required checks and
  review findings are resolved before integration.
- [ ] 3.2 Integrate while retaining the pre-existing main-worktree changes;
  repeat the capability checks against the integrated source.
- [ ] 3.3 Back up the reviewed desktop targets and existing native overrides,
  apply only the authorized Noctalia/Niri targets, and restart native Noctalia;
  verify one bar/wallpaper per monitor and safe panel IPC, leaving reboot to the
  operator.
- [ ] 3.4 Record the preview review, activation results, remaining visual
  differences, rollback paths, and the pending normal-login persistence check.
