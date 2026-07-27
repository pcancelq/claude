# HexStrike AI — setup and MCP client configuration

Repo-side setup for [0x4m4/hexstrike-ai](https://github.com/0x4m4/hexstrike-ai) (MIT):
an MCP server that exposes ~150 CLI security tools to MCP-compatible AI agents.

Upstream source is **not vendored here** — `setup.sh` clones it into
`hexstrike/vendor/` (gitignored) so you track upstream instead of a stale copy.
What lives in git is the setup scripts and the client configuration.

## How it works

1. **`hexstrike_server.py`** — a Flask API on `:8888` that shells out to the
   installed tools (nmap, ffuf, sqlmap, …) and returns structured results.
2. **`hexstrike_mcp.py`** — a stdio MCP client your AI agent launches. It
   translates MCP tool calls into HTTP calls against that server.
3. Your agent (Claude Desktop, Claude Code, Cursor, VS Code Copilot, Roo, 5ire)
   connects to #2, which talks to #1, which runs the actual tools.

Both processes must be running for anything to work: the server as a long-lived
process you start yourself, the MCP client spawned on demand by the AI client.

## Setup

```bash
./hexstrike/setup.sh              # clone upstream + venv + deps + generate configs
./hexstrike/setup.sh --skip-heavy # skip angr + pwntools (the slow ones)
```

`--skip-heavy` is safe: `angr` and `pwntools` never get imported by the server —
they only appear inside generated exploit-template strings. Everything else,
**including mitmproxy**, is a module-level import in `hexstrike_server.py`, so
the server won't boot without it.

Then install the CLI tools it wraps (optional — missing tools degrade gracefully):

```bash
./hexstrike/scripts/install-security-tools.sh          # core set
./hexstrike/scripts/install-security-tools.sh --all    # + cloud tools + Chromium
./hexstrike/scripts/install-security-tools.sh --check   # what's already present
```

Run the server, then verify:

```bash
./hexstrike/scripts/start-server.sh          # binds 127.0.0.1:8888
./hexstrike/scripts/verify.sh
```

`verify.sh` hits `/health` and `POST /api/intelligence/analyze-target`. A healthy
server reports `"status": "healthy"` plus a per-tool availability map — most
entries read `false` until you install the CLI tools, which is expected.

`start-server.sh` takes `--debug`, `--port 9999`, `--host 0.0.0.0`, and
`--upstream` (run upstream's entrypoint unmodified — see the binding note below).

### Already cloned it manually?

If you ran the upstream quick-start yourself, point this at your checkout
instead of re-cloning:

```bash
mkdir -p hexstrike/vendor && ln -s /abs/path/to/your/hexstrike-ai hexstrike/vendor/hexstrike-ai
ln -s /abs/path/to/your/hexstrike-env hexstrike/hexstrike-env
python3 hexstrike/scripts/generate-client-config.py --write
```

## AI client configuration

`setup.sh` writes configs with your real absolute paths into
`hexstrike/configs/generated/`. The files in `hexstrike/configs/` are the
reference templates with `/path/to/…` placeholders.

Regenerate or inspect them any time:

```bash
python3 hexstrike/scripts/generate-client-config.py --write
python3 hexstrike/scripts/generate-client-config.py --print claude-desktop
```

Merge directly into a client's real config (takes a timestamped backup first,
and preserves any other MCP servers already configured):

```bash
python3 hexstrike/scripts/generate-client-config.py --install claude-desktop
python3 hexstrike/scripts/generate-client-config.py --install cursor
```

Where each client expects its config:

| Client | Location |
| --- | --- |
| Claude Desktop (Linux) | `~/.config/Claude/claude_desktop_config.json` |
| Claude Desktop (macOS) | `~/Library/Application Support/Claude/claude_desktop_config.json` |
| Claude Desktop (Windows) | `%APPDATA%\Claude\claude_desktop_config.json` |
| Cursor | `~/.cursor/mcp.json` |
| Claude Code | `.mcp.json` in the project root |
| VS Code Copilot / Roo Code | `.vscode/mcp.json` |
| 5ire | in-app MCP settings (v0.14.0 is not supported upstream) |

Restart the client after editing. The generated config points the MCP client at
the virtualenv interpreter, so you don't need the venv activated for the client
to work.

### Environment

```bash
cp hexstrike/hexstrike.env.example hexstrike/hexstrike.env
```

`hexstrike.env` is gitignored — put the port and any API keys there.
`start-server.sh` and the config generator both read it.

## Security notes

Read these before exposing this to an agent.

- **The API has no authentication of any kind.** Anyone who can reach port 8888
  gets arbitrary tool execution as your user. Treat reachability as full shell
  access.
- **Upstream binds every interface while telling you it doesn't.**
  `hexstrike_server.py` reads `API_HOST` from `HEXSTRIKE_HOST` (default
  `127.0.0.1`) and prints `Server starting on {API_HOST}:{API_PORT}` — but its
  `__main__` block then calls `app.run(host="0.0.0.0", ...)` with the host
  hardcoded. `HEXSTRIKE_HOST` is silently ignored, so the banner says loopback
  while the socket is open to the network.

  `scripts/hexstrike_local.py` fixes this without patching the vendored clone: it
  imports the module (whose `app.run` sits behind a `__main__` guard, so nothing
  auto-starts) and runs the Flask app on the host you asked for.
  `start-server.sh` uses it by default and verifiably binds `127.0.0.1` only.
  Pass `--host 0.0.0.0` to expose it deliberately; you'll get a warning.
- **`alwaysAllow` means autonomous execution.** The 5ire template ships with an
  empty `alwaysAllow` list on purpose — leave it empty unless you want the agent
  running scans without confirmation.
- **Only test systems you're authorized to test.** These are real offensive
  tools; an AI agent will happily point them at whatever hostname appears in its
  context. Scope every engagement explicitly, and be aware that prompt content
  reaching the agent from an untrusted source can influence what gets scanned.
- **API keys** for Shodan/Censys/VirusTotal go in `hexstrike.env`, never in a
  committed config.

## Layout

```
hexstrike/
├── setup.sh                        # clone + venv + deps + configs
├── hexstrike.env.example           # port and API keys (copy to hexstrike.env)
├── configs/                        # reference templates (placeholder paths)
│   └── generated/                  # real paths, written by setup.sh (gitignored)
├── scripts/
│   ├── start-server.sh             # launcher wrapper (loopback by default)
│   ├── hexstrike_local.py          # runs the app bound to a host you choose
│   ├── verify.sh
│   ├── install-security-tools.sh
│   └── generate-client-config.py
├── vendor/hexstrike-ai/            # upstream clone (gitignored)
└── hexstrike-env/                  # virtualenv (gitignored)
```

Upstream install/demo walkthrough: <https://www.youtube.com/watch?v=pSoftCagCm8>
