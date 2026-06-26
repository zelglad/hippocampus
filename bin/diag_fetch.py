#!/usr/bin/env python3
# isolated diagnostic: hits /api/organizations exactly like fetch, but sends the
# FULL decrypted cookie jar (incl. cf_clearance/__cf_bm) with the Claude app's
# real Electron user-agent, to get past the cloudflare managed challenge.
import os
import sys
import gzip
import shutil
import sqlite3
import tempfile
import urllib.request
import urllib.error

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from refresh_session_key import _get_keychain_password, _derive_key, _decrypt_cookie

COOKIE_DB = os.path.expanduser("~/Library/Application Support/Claude/Cookies")
# the claude desktop app's actual electron user-agent - cf_clearance is bound to it
UA = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Claude/1.15962.0 Chrome/148.0.7778.254 "
      "Electron/42.4.0 Safari/537.36")


def all_cookies():
    # decrypt every claude.ai cookie into a name=value jar
    aes = _derive_key(_get_keychain_password())
    with tempfile.NamedTemporaryFile(suffix=".db", delete=False) as t:
        shutil.copy2(COOKIE_DB, t.name)
        tmp = t.name
    try:
        conn = sqlite3.connect(tmp)
        rows = conn.execute(
            "SELECT name, encrypted_value FROM cookies WHERE host_key LIKE '%claude.ai'"
        ).fetchall()
        conn.close()
    finally:
        os.unlink(tmp)
    jar = {}
    for name, enc in rows:
        val = _decrypt_cookie(enc, aes)
        if val is not None:
            jar[name] = val.decode("utf-8", "replace")
    return jar


jar = all_cookies()
print(f"=== {len(jar)} cookies: {sorted(jar)} ===", file=sys.stderr)
cookie_hdr = "; ".join(f"{k}={v}" for k, v in jar.items())

req = urllib.request.Request("https://claude.ai/api/organizations")
req.add_header("Cookie", cookie_hdr)
req.add_header("User-Agent", UA)
req.add_header("Accept", "application/json")
req.add_header("Accept-Encoding", "gzip, identity")

try:
    resp = urllib.request.urlopen(req, timeout=60)
    body = resp.read()
    if resp.headers.get("Content-Encoding") == "gzip":
        body = gzip.decompress(body)
    print(f"  STATUS {resp.status} - SUCCESS", file=sys.stderr)
    print(f"  body[:200]={body[:200]!r}", file=sys.stderr)
except urllib.error.HTTPError as e:
    print(f"  HTTPError {e.code}  cf-mitigated={e.headers.get('cf-mitigated')}", file=sys.stderr)
    print(f"  cf-ray={e.headers.get('cf-ray')}", file=sys.stderr)
except Exception as e:
    print(f"  ERROR {type(e).__name__}: {e}", file=sys.stderr)
