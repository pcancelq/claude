#!/usr/bin/env python3
"""Launch the HexStrike API server bound to a host you actually choose.

Why this exists: upstream's `__main__` block prints "Server starting on
{API_HOST}:{API_PORT}" — where API_HOST defaults to 127.0.0.1 — but then calls
`app.run(host="0.0.0.0", ...)` with the host hardcoded. So HEXSTRIKE_HOST is
silently ignored and the server listens on every interface while telling you it
is on loopback. With no authentication in front of it, that is remote code
execution for anyone who can reach the port.

This launcher imports hexstrike_server as a module (its app.run is inside a
`if __name__ == "__main__"` guard, so nothing starts on import) and runs the
Flask app itself with the host we want. Upstream stays unpatched, so
`setup.sh` can keep fast-forwarding the vendored clone.

  python3 hexstrike_local.py                    # 127.0.0.1:8888
  python3 hexstrike_local.py --port 9999
  python3 hexstrike_local.py --host 0.0.0.0     # opt in explicitly, with a warning
  python3 hexstrike_local.py --debug
"""
from __future__ import annotations

import argparse
import importlib.util
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SERVER_PY = ROOT / "vendor" / "hexstrike-ai" / "hexstrike_server.py"


def load_server_module():
    if not SERVER_PY.exists():
        sys.exit(f"[!] {SERVER_PY} not found - run {ROOT}/setup.sh first.")
    # Upstream writes hexstrike.log relative to cwd; keep it beside the source.
    os.chdir(SERVER_PY.parent)
    spec = importlib.util.spec_from_file_location("hexstrike_server", SERVER_PY)
    module = importlib.util.module_from_spec(spec)
    sys.modules["hexstrike_server"] = module
    spec.loader.exec_module(module)
    return module


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--host", default=os.environ.get("HEXSTRIKE_HOST", "127.0.0.1"),
                    help="interface to bind (default: 127.0.0.1)")
    ap.add_argument("--port", type=int, default=int(os.environ.get("HEXSTRIKE_PORT", 8888)),
                    help="port to listen on (default: 8888)")
    ap.add_argument("--debug", action="store_true", help="enable Flask debug mode")
    args = ap.parse_args()

    if args.host not in ("127.0.0.1", "localhost", "::1"):
        print(
            f"\033[33m[!] Binding {args.host}:{args.port} - the API has NO authentication.\n"
            f"    Anyone who can reach this port can run security tools as "
            f"{os.environ.get('USER', 'this user')}.\033[0m",
            file=sys.stderr,
        )

    server = load_server_module()
    server.API_PORT = args.port
    if args.debug:
        server.DEBUG_MODE = True

    print(f"\033[36m[*] HexStrike API server on http://{args.host}:{args.port}\033[0m")
    server.app.run(host=args.host, port=args.port, debug=args.debug)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
