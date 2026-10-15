#!/usr/bin/env python3
"""Validate active OpenSpec contracts without treating archive/ as a change."""

from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="chezmoi-workflow-") as temporary:
    staging = Path(temporary)
    shutil.copytree(root / ".agentic-workflow", staging / ".agentic-workflow")
    changes = staging / "openspec/changes"
    changes.mkdir(parents=True)
    for change in sorted((root / "openspec/changes").iterdir()):
        if change.is_dir() and change.name != "archive":
            shutil.copytree(change, changes / change.name)
    subprocess.run(
        ["agentic-workflow", "validate", str(staging / ".agentic-workflow/config.yaml")],
        check=True,
    )
