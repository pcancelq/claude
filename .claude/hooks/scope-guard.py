#!/usr/bin/env python3
"""PreToolUse hook: block network traffic to hosts outside the engagement scope.

An instruction in a prompt is a suggestion. This is a gate. It sits in front of
every Bash/WebFetch call Claude makes and denies anything aimed at a host that
is not in the scope file.

Scope file lookup order:  $HUNT_SCOPE, ./scope.json, .claude/scope.json
No scope file  ->  no decision (you are not on an engagement; normal rules apply).

IMPORTANT: this guards Claude's own tool calls only. Work delegated to Codex
runs in Codex's process, outside this hook, which is why delegation prompts are
scanned too - see check_delegation().
"""

import ipaddress
import json
import os
import re
import sys

# Commands that put packets on the wire. Anything else is unguarded.
NETWORK_TOOLS = {
    "curl", "wget", "httpx", "httpie", "http", "nuclei", "ffuf", "gobuster",
    "feroxbuster", "dirb", "dirsearch", "nmap", "masscan", "rustscan",
    "sqlmap", "nikto", "wpscan", "subfinder", "amass", "assetfinder",
    "dnsx", "massdns", "dig", "host", "nslookup", "whatweb", "wafw00f",
    "nc", "ncat", "netcat", "socat", "openssl", "hydra", "medusa",
    "testssl.sh", "sslscan", "katana", "hakrawler", "waybackurls", "gau",
}

# Tokens that look like hostnames but are filenames.
NOT_TLDS = {
    "py", "sh", "js", "ts", "jsx", "tsx", "go", "rs", "rb", "php", "c", "h",
    "cpp", "java", "json", "txt", "md", "log", "xml", "yaml", "yml", "toml",
    "ini", "conf", "cfg", "csv", "tsv", "html", "htm", "css", "png", "jpg",
    "jpeg", "gif", "svg", "pdf", "zip", "gz", "tar", "bz2", "xz", "bak",
    "out", "err", "tmp", "lock", "pem", "key", "crt", "cer", "db", "sqlite",
    "sql", "env", "example", "sample", "old", "orig", "swp", "so", "dll",
}

URL_RE = re.compile(r"\b[a-zA-Z][a-zA-Z0-9+.-]*://([^/\s'\"|;)>]+)")
HOST_RE = re.compile(r"\b((?:[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?\.)+[a-zA-Z]{2,})\b")
IPV4_RE = re.compile(r"\b(\d{1,3}(?:\.\d{1,3}){3})\b")


def emit(decision, reason):
    """Emit a PreToolUse decision and exit."""
    if decision != "defer":
        json.dump({
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": decision,
                "permissionDecisionReason": reason,
            }
        }, sys.stdout)
    sys.exit(0)


def load_scope(cwd):
    for path in (os.environ.get("HUNT_SCOPE"),
                 os.path.join(cwd, "scope.json"),
                 os.path.join(cwd, ".claude", "scope.json")):
        if path and os.path.isfile(path):
            try:
                with open(path) as fh:
                    return json.load(fh), path
            except (json.JSONDecodeError, OSError) as exc:
                emit("deny", f"Scope file {path} is unreadable ({exc}). "
                             "Fix it before sending any traffic.")
    return None, None


def normalize(host):
    host = host.strip().lower().rstrip(".")
    if "@" in host:                       # strip userinfo
        host = host.rsplit("@", 1)[1]
    if host.startswith("["):              # bracketed IPv6
        host = host.split("]")[0].lstrip("[")
    elif host.count(":") == 1:            # host:port
        host = host.split(":")[0]
    return host


def extract_hosts(text):
    found = set()
    for match in URL_RE.findall(text):
        found.add(normalize(match))
    for match in IPV4_RE.findall(text):
        try:
            ipaddress.ip_address(match)
            found.add(match)
        except ValueError:
            pass
    for match in HOST_RE.findall(text):
        host = normalize(match)
        if host.rsplit(".", 1)[-1] not in NOT_TLDS:
            found.add(host)
    return {h for h in found if h and h not in ("localhost", "127.0.0.1")}


def matches(host, patterns):
    for pattern in patterns:
        pattern = pattern.strip().lower()
        if not pattern:
            continue
        if pattern.startswith("*."):
            base = pattern[2:]
            if host == base or host.endswith("." + base):
                return True
        elif host == pattern:
            return True
    return False


def matches_ip(host, cidrs):
    try:
        addr = ipaddress.ip_address(host)
    except ValueError:
        return False
    for cidr in cidrs:
        try:
            if addr in ipaddress.ip_network(cidr.strip(), strict=False):
                return True
        except ValueError:
            continue
    return False


def classify(host, scope):
    """Return 'out' if explicitly excluded, 'in' if allowed, else 'unknown'."""
    out = scope.get("out_of_scope", {})
    if matches(host, out.get("domains", [])) or matches_ip(host, out.get("ips", [])):
        return "out"
    inn = scope.get("in_scope", {})
    if matches(host, inn.get("domains", [])) or matches_ip(host, inn.get("ips", [])):
        return "in"
    return "unknown"


def uses_network(command):
    # Check each token so pipelines and `sudo nmap ...` are caught too.
    tokens = re.split(r"[\s;|&()<>]+", command)
    return any(os.path.basename(t) in NETWORK_TOOLS for t in tokens if t)


def check(text, scope, scope_path, label):
    hosts = extract_hosts(text)
    if not hosts:
        emit("deny", f"scope-guard: {label} appears to send traffic but no target "
                     "host could be identified. Write the target literally "
                     "(no shell variables) so it can be checked against "
                     f"{scope_path}.")
    bad = {h: classify(h, scope) for h in sorted(hosts)}
    rejected = {h: v for h, v in bad.items() if v != "in"}
    if rejected:
        detail = ", ".join(
            f"{h} ({'explicitly out of scope' if v == 'out' else 'not listed in scope'})"
            for h, v in rejected.items()
        )
        emit("deny", f"scope-guard: BLOCKED. {detail}. Authorized scope is "
                     f"defined in {scope_path}. Do not retry against these hosts; "
                     "either pick an in-scope target or ask the operator to "
                     "amend the scope file.")
    # In scope: defer rather than allow. This hook only ever subtracts
    # permission - granting it here would silently bypass the allow/deny rules
    # in settings.json for any command that happens to name an in-scope host.
    emit("defer", "")


def main():
    try:
        event = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        sys.exit(0)

    scope, scope_path = load_scope(event.get("cwd") or os.getcwd())
    if scope is None:
        sys.exit(0)   # not on an engagement

    tool = event.get("tool_name", "")
    inp = event.get("tool_input") or {}

    if tool == "Bash":
        command = inp.get("command", "")
        if not uses_network(command):
            sys.exit(0)
        check(command, scope, scope_path, "this command")

    elif tool in ("WebFetch", "WebSearch"):
        check(inp.get("url", "") or inp.get("query", ""), scope, scope_path, "this fetch")

    elif tool.startswith("mcp__codex__"):
        # Codex executes outside this hook, so the handoff is the last
        # checkpoint. Only block on hosts that are affirmatively out of scope -
        # delegation prompts are prose and mention hosts incidentally.
        hosts = extract_hosts(json.dumps(inp))
        out = [h for h in sorted(hosts) if classify(h, scope) == "out"]
        if out:
            emit("deny", f"scope-guard: refusing to delegate to Codex - the prompt "
                         f"references out-of-scope host(s): {', '.join(out)}. "
                         "Codex runs outside this hook, so it cannot be re-checked "
                         "downstream.")
        sys.exit(0)

    sys.exit(0)


if __name__ == "__main__":
    main()
