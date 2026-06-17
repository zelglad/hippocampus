#!/usr/bin/env python3
# extracts the claude.ai sessionKey cookie from the Claude desktop app's local SQLite
# cookie store, decrypting with the macOS Keychain key. stdlib only, no pip deps.
# exit codes: 0 ok, 1 failed.
# run with --diag to inspect key material without writing anything.

import ctypes
import hashlib
import os
import re
import shutil
import sqlite3
import subprocess
import sys
import tempfile

CONFIG_DIR = os.path.expanduser("~/.config/brain-kit")
KEY_FILE = os.path.join(CONFIG_DIR, "session.key")
COOKIE_DB = os.path.expanduser("~/Library/Application Support/Claude/Cookies")
DIAG = "--diag" in sys.argv

# electron prepends a 32-byte fixed header to all AES-encrypted cookie values
_ELECTRON_COOKIE_HEADER = 32


def _get_keychain_password():
    r = subprocess.run(
        ["security", "find-generic-password",
         "-s", "Claude Safe Storage", "-a", "Claude Key", "-g"],
        capture_output=True, text=True,
    )
    if r.returncode != 0:
        return None
    for line in r.stderr.splitlines():
        line = line.strip()
        if not line.startswith("password:"):
            continue
        m = re.search(r'0x([0-9a-fA-F]+)', line)
        if m:
            return bytes.fromhex(m.group(1))
        m = re.search(r'"(.*)"', line)
        if m:
            return m.group(1).encode("utf-8")
    return None


def _derive_key(pw_bytes):
    # chromium macOS key derivation: PBKDF2-SHA1, salt="saltysalt", 1003 iters, 16-byte key
    return hashlib.pbkdf2_hmac("sha1", pw_bytes, b"saltysalt", 1003, dklen=16)


def _aes128_cbc_decrypt(ciphertext, key, iv=b" " * 16):
    lib = ctypes.CDLL("/usr/lib/libSystem.B.dylib")
    cc = lib.CCCrypt
    cc.restype = ctypes.c_int32
    cc.argtypes = [
        ctypes.c_uint32, ctypes.c_uint32, ctypes.c_uint32,
        ctypes.c_char_p, ctypes.c_size_t, ctypes.c_char_p,
        ctypes.c_char_p, ctypes.c_size_t,
        ctypes.c_char_p, ctypes.c_size_t,
        ctypes.POINTER(ctypes.c_size_t),
    ]
    out = ctypes.create_string_buffer(len(ciphertext) + 16)
    moved = ctypes.c_size_t(0)
    status = cc(1, 0, 0, key, len(key), iv,
                ciphertext, len(ciphertext), out, len(out), ctypes.byref(moved))
    if status != 0:
        return None
    raw = bytes(out.raw[:moved.value])
    if raw and 1 <= raw[-1] <= 16:
        raw = raw[:-raw[-1]]
    return raw


def _decrypt_cookie(blob, aes_key):
    if not isinstance(blob, (bytes, bytearray)):
        blob = blob.encode()
    if not blob[:3] == b"v10":
        return None
    pt = _aes128_cbc_decrypt(blob[3:], aes_key)
    if pt is None or len(pt) <= _ELECTRON_COOKIE_HEADER:
        return None
    return pt[_ELECTRON_COOKIE_HEADER:]


def extract_session_key():
    pw = _get_keychain_password()
    if not pw:
        return None, "Claude Safe Storage keychain entry not found"

    aes_key = _derive_key(pw)
    if DIAG:
        print(f"  keychain pw: {len(pw)}B prefix={pw[:4].hex()}", file=sys.stderr)
        print(f"  aes key: {aes_key.hex()}", file=sys.stderr)

    if not os.path.exists(COOKIE_DB):
        return None, f"cookie db not found: {COOKIE_DB}"

    with tempfile.NamedTemporaryFile(suffix=".db", delete=False) as t:
        shutil.copy2(COOKIE_DB, t.name)
        tmp = t.name
    try:
        conn = sqlite3.connect(tmp)
        row = conn.execute(
            "SELECT encrypted_value FROM cookies "
            "WHERE host_key LIKE '%claude.ai' AND name='sessionKey'"
        ).fetchone()
        conn.close()
    finally:
        os.unlink(tmp)

    if not row:
        return None, "sessionKey cookie not found in Claude cookie db"

    val = _decrypt_cookie(row[0], aes_key)
    if val and val.startswith(b"sk-ant-"):
        return val.decode("ascii").strip(), None
    return None, f"decryption produced unexpected result: {val[:20] if val else b'<none>'!r}"


def main():
    if DIAG:
        print("=== diagnostic mode ===", file=sys.stderr)

    session_key, err = extract_session_key()

    if not session_key:
        print(f"refresh failed: {err}", file=sys.stderr)
        return 1

    if DIAG:
        print(f"  sessionKey: {session_key[:20]}... ({len(session_key)} chars)", file=sys.stderr)
        print("  --diag: not writing to disk", file=sys.stderr)
        return 0

    os.makedirs(CONFIG_DIR, exist_ok=True)
    with open(KEY_FILE, "w") as f:
        f.write(session_key)
    os.chmod(KEY_FILE, 0o600)
    print(f"session key refreshed from Claude app ({len(session_key)} chars)", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
