#!/usr/bin/env python3
"""Generate MCP client configs for HexStrike AI with real absolute paths.

The templates in ../configs/ use a `/path/to/hexstrike-ai/` placeholder. This
script resolves the actual checkout and virtualenv on this machine and writes
ready-to-paste configs into ../configs/generated/.

  python3 generate-client-config.py --write
  python3 generate-client-config.py --print claude-desktop
  python3 generate-client-config.py --install claude-desktop   # merges into the
                                                               # real app config
                                                               # (makes a backup)
"""
from __future__ import annotations

import argparse
import json
import os
import platform
import shutil
import sys
from datetime import datetime
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent                      # <repo>/hexstrike
SRC = ROOT / "vendor" / "hexstrike-ai"
VENV_PY = ROOT / "hexstrike-env" / "bin" / "python3"
VENV_PY_WIN = ROOT / "hexstrike-env" / "Scripts" / "python.exe"
GENERATED = ROOT / "configs" / "generated"

DESCRIPTION = "HexStrike AI - MCP bridge to the local HexStrike security server"


def python_command() -> str:
    """Prefer the repo virtualenv interpreter; fall back to system python3."""
    for candidate in (VENV_PY, VENV_PY_WIN):
        if candidate.exists():
            return str(candidate)
    print(
        "[!] virtualenv not found - falling back to 'python3'. Run setup.sh to "
        "create it, then re-run this script.",
        file=sys.stderr,
    )
    return "python3"


def server_url() -> str:
    port = os.environ.get("HEXSTRIKE_PORT", "8888")
    env_file = ROOT / "hexstrike.env"
    if env_file.exists():
        for line in env_file.read_text().splitlines():
            line = line.strip()
            if line.startswith("HEXSTRIKE_PORT="):
                port = line.split("=", 1)[1].strip().strip("\"'")
    return f"http://localhost:{port}"


def mcp_entry() -> dict:
    return {
        "command": python_command(),
        "args": [str(SRC / "hexstrike_mcp.py"), "--server", server_url()],
        "description": DESCRIPTION,
        "timeout": 300,
        "disabled": False,
    }


def configs() -> dict[str, dict]:
    entry = mcp_entry()
    stdio_entry = {
        "type": "stdio",
        "command": entry["command"],
        "args": entry["args"],
    }
    return {
        # Claude Desktop, Cursor and 5ire all speak the mcpServers dialect.
        "claude-desktop": {"mcpServers": {"hexstrike-ai": entry}},
        "cursor": {"mcpServers": {"hexstrike-ai": entry}},
        "5ire": {"mcpServers": {"hexstrike-ai": dict(entry, alwaysAllow=[])}},
        # Claude Code reads .mcp.json from the project root.
        "claude-code": {"mcpServers": {"hexstrike-ai": stdio_entry}},
        # VS Code Copilot / Roo Code.
        "vscode": {"servers": {"hexstrike": stdio_entry}, "inputs": []},
    }


def install_target(client: str) -> Path:
    system = platform.system()
    home = Path.home()
    if client == "claude-desktop":
        if system == "Darwin":
            return home / "Library" / "Application Support" / "Claude" / "claude_desktop_config.json"
        if system == "Windows":
            return Path(os.environ.get("APPDATA", home)) / "Claude" / "claude_desktop_config.json"
        return home / ".config" / "Claude" / "claude_desktop_config.json"
    if client == "cursor":
        return home / ".cursor" / "mcp.json"
    raise SystemExit(
        f"--install does not support '{client}'. Supported: claude-desktop, cursor.\n"
        "For vscode / claude-code / 5ire, copy the generated file into your project."
    )


def merge_install(client: str) -> None:
    """Merge our server entry into an existing client config, preserving the rest."""
    target = install_target(client)
    new = configs()[client]
    target.parent.mkdir(parents=True, exist_ok=True)

    existing: dict = {}
    if target.exists():
        backup = target.with_suffix(
            target.suffix + f".bak-{datetime.now():%Y%m%d-%H%M%S}"
        )
        shutil.copy2(target, backup)
        print(f"[*] Backed up existing config to {backup}")
        try:
            existing = json.loads(target.read_text() or "{}")
        except json.JSONDecodeError as exc:
            raise SystemExit(
                f"[!] {target} is not valid JSON ({exc}); refusing to overwrite. "
                "Fix or move it, then re-run."
            )

    servers = existing.setdefault("mcpServers", {})
    servers["hexstrike-ai"] = new["mcpServers"]["hexstrike-ai"]
    target.write_text(json.dumps(existing, indent=2) + "\n")
    print(f"[+] Installed hexstrike-ai into {target}")
    print("    Restart the client for it to pick up the new server.")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--write", action="store_true", help="write all configs to configs/generated/")
    ap.add_argument("--print", dest="print_client", metavar="CLIENT", help="print one config to stdout")
    ap.add_argument("--install", metavar="CLIENT", help="merge into the real client config (claude-desktop|cursor)")
    args = ap.parse_args()

    if not (args.write or args.print_client or args.install):
        ap.print_help()
        return 2

    if not SRC.exists():
        print(f"[!] {SRC} not found - run setup.sh first.", file=sys.stderr)

    all_configs = configs()

    if args.print_client:
        if args.print_client not in all_configs:
            raise SystemExit(f"unknown client '{args.print_client}'; choose from {', '.join(all_configs)}")
        print(json.dumps(all_configs[args.print_client], indent=2))

    if args.write:
        GENERATED.mkdir(parents=True, exist_ok=True)
        names = {
            "claude-desktop": "claude_desktop_config.json",
            "cursor": "cursor-mcp.json",
            "5ire": "5ire-hexstrike.json",
            "claude-code": "claude-code.mcp.json",
            "vscode": "vscode-mcp.json",
        }
        for client, cfg in all_configs.items():
            out = GENERATED / names[client]
            out.write_text(json.dumps(cfg, indent=2) + "\n")
            print(f"[+] {out}")

    if args.install:
        merge_install(args.install)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
