#!/usr/bin/env python3
"""Validate desktop profile output in temporary homes; never activate a session."""

import hashlib
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import tempfile
import tomllib


ROOT = Path(__file__).resolve().parents[1]


def run(command, env):
    result = subprocess.run(command, env=env, text=True, capture_output=True)
    if result.returncode:
        raise RuntimeError(f"{command!r}\n{result.stdout}{result.stderr}")
    return result.stdout + result.stderr


def snapshot(home):
    entries = []
    for path in sorted(home.rglob("*")):
        info = path.lstat()
        content = (
            os.readlink(path) if path.is_symlink()
            else hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file()
            else "directory"
        )
        entries.append((str(path.relative_to(home)), stat.S_IMODE(info.st_mode), content))
    return entries


def main():
    for tool in ["chezmoi", "noctalia", "niri"]:
        run([tool, "--version"], os.environ.copy())
    with tempfile.TemporaryDirectory(prefix="chezmoi-desktop-") as temporary:
        temporary = Path(temporary)
        arch_home = None
        for role in ["arch", "macos", "fedora", "container", "debian-dev-headless"]:
            base = temporary / role
            home = base / "home"
            home.mkdir(parents=True)
            runtime = base / "runtime"
            runtime.mkdir(mode=0o700)
            env = dict(os.environ, HOME=str(home), XDG_CONFIG_HOME=str(home / ".config"),
                       XDG_CACHE_HOME=str(base / "cache"), XDG_STATE_HOME=str(base / "state"),
                       XDG_RUNTIME_DIR=str(runtime), CHEZMOI_ROLE=role, CHEZMOI_WORK="0")
            command = ["chezmoi", "--source", str(ROOT), "--destination", str(home),
                       "--config", str(base / "chezmoi.toml"), "--cache", str(base / "cache"),
                       "--persistent-state", str(base / "chezmoi-state"), "--no-tty",
                       "--refresh-externals=never", "--exclude", "encrypted,scripts"]
            run(command + ["init"], env)
            managed = set(run(command + ["managed", "--path-style=relative"], env).splitlines())
            assert (".config/noctalia/config.toml" in managed) == (role == "arch"), role
            for path in managed:
                assert not any(path == prefix or path.startswith(prefix + "/") for prefix in
                               ["archive", "openspec", ".agentic-workflow", ".beads", ".worktrees"]), path
                assert path != "NOCTALIA-MIGRATION.md", path
                assert path != ".config/noctalia/settings.json", path
            run(command + ["apply", "--force"], env)
            first = snapshot(home)
            run(command + ["apply", "--force"], env)
            assert first == snapshot(home), f"{role}: second apply changed the destination"
            if role == "arch":
                arch_home = home
                native_env = dict(env, NOCTALIA_CONFIG_HOME=str(home / ".config"),
                                  NOCTALIA_STATE_HOME=str(base / "native-state"))
                output = run(["noctalia", "config", "validate", str(home / ".config/noctalia/config.toml")], native_env)
                assert not re.search(r"\bWARN(?:ING)?\b", output), output
                effective = tomllib.loads(run(["noctalia", "config", "export", "full"], native_env))
                verify_preferences(effective)
                run(["niri", "validate", "--config", str(home / ".config/niri/config.kdl")], env)
            print(f"OK: {role} targets, archive boundaries, and apply-twice state")
        assert arch_home is not None
        verify_commands(arch_home)


def verify_preferences(config):
    widget = config["widget"]
    workspace = widget["workspaces"]
    assert config["theme"]["source"] == "builtin"
    assert config["theme"]["builtin"] == "Catppuccin" and config["theme"]["mode"] == "dark"
    assert workspace["label_source"] == "name" and workspace["show_labels"]
    assert not workspace["labels_only_when_occupied"] and not workspace["hide_when_empty"]
    assert workspace["pill_scale"] == 1 and workspace["active_pill_size"] == 1
    assert all(workspace["actions"][key] == "none" for key in
               ["scroll_up", "scroll_down", "scroll_left", "scroll_right"])
    assert not widget["tray"]["drawer"] and not widget["tray"]["hide_passive"]
    assert config["audio"]["enable_sounds"] and not config["audio"]["enable_overdrive"]
    assert widget["ram"]["stat"] == "ram_pct" and widget["disk"]["stat"] == "disk_used_pct"
    assert all(name in config["bar"]["default"]["start"] for name in
               ["cpu", "temp", "ram", "disk", "network_rx", "network_tx", "media", "audio-vis"])
    assert widget["audio-vis"]["type"] == "audio_visualizer"
    assert all(widget[name]["font_family"] == "monospace" for name in
               ["cpu", "temp", "ram", "disk", "network_rx", "network_tx"])
    assert not config["shell"]["telemetry_enabled"] and not config["shell"]["clipboard_enabled"]
    assert not config["shell"]["setup_wizard_enabled"] and config["shell"]["polkit_agent"]
    print("OK: native configuration validates and saved preferences survive effective-config loading")


def verify_commands(home):
    niri = home / ".config/niri"
    startup = (niri / "cfg/autostart.kdl").read_text()
    assert startup.count('spawn-at-startup "noctalia"') == 1
    active = "\n".join(path.read_text() for path in niri.rglob("*.kdl"))
    assert "qs -c noctalia-shell" not in active
    help_text = run(["noctalia", "msg", "--help"], os.environ.copy())
    vocabulary = set(re.findall(r"^  ([a-z-]+)\s", help_text, re.MULTILINE))
    commands = re.findall(r'"noctalia msg ([^"]+)"', active)
    assert len(commands) == 13, commands
    for command in commands:
        assert command.split()[0] in vocabulary, command
    assert "volume-up 5" in commands and "volume-down 5" in commands
    packages = (ROOT / "pkg/arch/pacman-desktop.txt").read_text().splitlines()
    assert packages.count("noctalia") == 1
    assert "noctalia-shell" not in packages and "noctalia-qs" not in packages
    archived = ROOT / "archive/noctalia-v4/settings.json"
    original = json.loads(archived.read_text())
    assert original["bar"]["widgets"]["center"][0]["labelMode"] == "name"
    print("OK: native startup, IPC vocabulary, package ownership, and archived preferences")


if __name__ == "__main__":
    main()
