# New Mac Setup — Quick Reference

## 0. Day zero — bare metal (before you have a real terminal)

Fresh admin account, nothing installed. Do this in Terminal.app:

1. **Firefox** — download from mozilla.org, drag to /Applications
2. **1Password** — sign in via Firefox, install the Firefox extension (so you can paste credentials into GitLab / Anthropic / etc. later)
3. **Ghostty** — download from ghostty.org (don't wait for the Brewfile to install it — you want a real terminal ASAP). First launch: Gatekeeper → System Settings → Privacy & Security → Open Anyway
4. **Claude Code** — `curl -fsSL claude.ai/install.sh | bash` (or via brew once installed). Run `claude` in Ghostty, log in with your Anthropic account
5. **Retrieve your age key from 1Password** — it's stored there as `chezmoi age key` (or wherever you filed it). Download to `~/Downloads/key.txt`, then proceed to section 1

### Potential brew ownership gotcha

If the Mac was pre-imaged by IT, `/opt/homebrew` may already exist but be owned by a different user. `brew install` will fail with a "not writable" error. Fix:
```bash
sudo chown -R $(whoami) /opt/homebrew
```
Type your macOS login password when prompted (it's invisible — that's normal). Then retry whatever brew command failed.

After this you're ready to bootstrap dotfiles — the rest of this doc.

## 1. Chezmoi dotfiles (zsh, ghostty, aerospace, nvim, etc.)

Place your age key first:
```bash
mkdir -p ~/.config/chezmoi && chmod 700 ~/.config/chezmoi
mv ~/Downloads/key.txt ~/.config/chezmoi/key.txt
chmod 600 ~/.config/chezmoi/key.txt
```

Run bootstrap:
```bash
curl -sSL https://raw.githubusercontent.com/lukethomas1/dotfiles/main/bootstrap.sh | bash
```

Expect 3 prompts:
1. Press enter for Homebrew install
2. Type sudo password (may ask twice)
3. Click Install on Xcode CLT popup if it appears

Then wait for `brew bundle` (longest phase — installs aerospace, ghostty, nvim, etc.)

## 2. Bootstrap will stop and ask for permissions

Three macOS permissions cannot be granted from a script, and the keybindings are
useless without them. So bootstrap installs the packages, raises the prompts, and
then **stops before applying your dotfiles**, listing exactly what to approve:

1. System Settings → General → **Login Items & Extensions** → Driver Extensions →
   enable `Karabiner-DriverKit-VirtualHIDDevice`
2. System Settings → General → **Login Items & Extensions** → allow background
   items for `Karabiner-Elements`
3. System Settings → Privacy & Security → **Accessibility** → enable
   `Karabiner-Elements` **and** `AeroSpace`

Restart if macOS asks. **Then re-run `bootstrap.sh`** — it is idempotent and will
pick up where it left off, applying the dotfiles once the permissions are in place.

> **Don't go hunting for Karabiner in Privacy & Security → Input Monitoring.** It
> is normally not listed there at all — granting Accessibility covers input
> monitoring for it. Chasing the missing entry is a dead end.

This stop is deliberate. Caps Lock is the window-manager modifier, and Karabiner
is what makes it emit Alt+Cmd. Applying the configs before Karabiner is running
would leave you with a window manager that responds to no key at all, with
nothing to point at the cause. See `KEYBINDINGS.md`.

Leave System Settings → Keyboard → Modifier Keys at its default (Caps Lock = Caps
Lock). A second remap there fights Karabiner and is the usual cause of "Karabiner
isn't working" — bootstrap warns if it finds one.

## 3. Other post-bootstrap manual steps

- **Ghostty Gatekeeper**: first launch → System Settings → Privacy & Security → Open Anyway
- **Restart Ghostty** so it picks up the freed Cmd keys.
- **Log out and back in** — the screenshot shortcuts (Ctrl+Shift+1/2/3, matching
  Niri) only take effect after a fresh login.
- **Default shell**: bootstrap runs `chsh -s /bin/zsh` automatically. To do it
  manually: `chsh -s /bin/zsh`

### Sanity-check the keyboard

```bash
# Caps Lock should now be the WM modifier:
#   Caps+Return -> new Ghostty window     Caps+1..9 -> workspaces
#   Caps+H/L    -> focus left/right       Caps+Q    -> close window
# Cmd belongs to herdr:
#   Cmd+T -> new herdr tab (NOT a Ghostty tab)   Cmd+N -> new herdr workspace
```

Cmd is inside the Caps chord, so verify these three by hand after any macOS
update: `Caps+Tab` (vs the Dock's app switcher), `Caps+Q`, and `Cmd+T`.

## 4. Clone the Nalej sandbox repo

Find your GitLab username: `https://gitlab-internal.nalej.io` → avatar → your @handle.

HTTPS + PAT (easiest):
1. `https://gitlab-internal.nalej.io` → avatar → Edit profile → Access Tokens
2. Scopes: `read_api` + `read_repository` (add `write_repository` if you'll push)
3. Create → copy token
4. Clone under `~/Gitlab/` so your work gitconfig applies:
   ```bash
   mkdir -p ~/Gitlab && cd ~/Gitlab
   git clone https://gitlab-internal.nalej.io/swat-devops-sdo/platform/sandbox.git
   # username = your gitlab @handle (without @)
   # password = the PAT
   ```

SSH alternative:
```bash
ssh-keygen -t ed25519 -C "your-work-email" -f ~/.ssh/id_ed25519
pbcopy < ~/.ssh/id_ed25519.pub
# paste in gitlab-internal.nalej.io → Edit profile → SSH Keys
git clone git@gitlab-internal.nalej.io:swat-devops-sdo/platform/sandbox.git
```

## 5. Run the sandbox devcontainer

Install tools (already in your Brewfile but listing in case):
```bash
brew install colima docker node
npm install -g @devcontainers/cli
```

Start Docker VM:
```bash
colima start --cpu 4 --memory 8 --disk 60
docker ps  # should return empty list, not an error
```

Create a GitLab PAT (separate from the clone one):
- `https://gitlab-internal.nalej.io` → Edit profile → Access Tokens
- Scopes: `read_api` + `read_repository`

Get Anthropic API key:
- `https://console.anthropic.com` → API Keys → Create Key

Export env vars (in the shell where you'll run devcontainer):
```bash
export GITLAB_TOKEN=glpat-...
export ANTHROPIC_API_KEY=sk-ant-...
```

Build & run:
```bash
cd ~/Gitlab/sandbox
devcontainer up --workspace-folder .
devcontainer exec --workspace-folder . bash
```

Inside the container, follow README steps 5–8:
```bash
aws configure  # or: aws sso login --profile <profile>
aws eks update-kubeconfig --name platform-operations-dev --alias platform-dev-operations
cd /home/dev/Gitlab/platform
claude
```

## Gotchas

- **Env vars must be set before `devcontainer up`** — they're passed at build time. Forget = container builds but bootstrap can't clone repos. Fix: re-export, re-run `devcontainer up` (idempotent).
- **First `colima start`** downloads a VM image — slow, no prompt, just wait.
- **First `devcontainer up`** builds the Dockerfile — slow, lots of apt output.
- **Bootstrap is idempotent** — safe to re-run if anything fails.

## Things NOT covered by your Brewfile

Install manually if needed: browser (Chrome/Arc/Firefox), Slack/Discord/Zoom, 1Password, Mac App Store apps, iCloud sign-in.

## Updating this doc on a future fresh Mac

To push edits back to the dotfiles repo without doing the full chezmoi bootstrap first:

```bash
brew install gh
gh auth login
# answers: GitHub.com → HTTPS → Y → Login with a web browser
# copy the one-time code, press enter, Firefox opens to github.com/login/device
# paste code → Authorize GitHub CLI → back to terminal

cd /tmp
git clone https://github.com/lukethomas1/dotfiles.git
cp ~/Documents/new-mac-setup.md dotfiles/NEW-MAC-SETUP.md
cd dotfiles
git add NEW-MAC-SETUP.md
git commit -m "docs: update new mac setup"
git push
cd ~ && rm -rf /tmp/dotfiles
```

`gh auth login` only needs to run once — after that, git's credential helper caches the token globally.

## Sanity checks
```bash
chezmoi status          # should be empty
brew bundle check --file="$(chezmoi source-path)/pkg/macos/Brewfile"
aerospace --version
docker ps
```
