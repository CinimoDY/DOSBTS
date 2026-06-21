#!/usr/bin/env python3
"""Mint a short-lived ES256 JWT for the App Store Connect API (DMNC-1147, KTD9).

Pure-bash ES256 is a footgun (the DER ASN.1 signature must be converted to raw
R‖S), so signing goes through openssl and this shim handles the encoding. The
private key (.p8) path, key id, and issuer id come from the caller — no
credentials are embedded here. The token is printed to stdout and never logged.

Usage: asc-jwt.py <key_path> <key_id> <issuer_id> [exp_seconds]
"""

import base64
import json
import os
import subprocess
import sys
import time


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def der_to_raw(der: bytes) -> bytes:
    """ECDSA DER `SEQUENCE { INTEGER r, INTEGER s }` → raw 64-byte R‖S."""
    if not der or der[0] != 0x30:
        raise ValueError("malformed DER signature")
    i = 1
    # Skip the SEQUENCE length (short or long form).
    i += 1 + (der[i] & 0x7F) if der[i] & 0x80 else 1
    if der[i] != 0x02:
        raise ValueError("expected INTEGER r")
    r_len = der[i + 1]
    r = der[i + 2 : i + 2 + r_len]
    i = i + 2 + r_len
    if der[i] != 0x02:
        raise ValueError("expected INTEGER s")
    s_len = der[i + 1]
    s = der[i + 2 : i + 2 + s_len]
    # Drop sign-padding, then left-pad each coordinate to 32 bytes.
    r = r.lstrip(b"\x00").rjust(32, b"\x00")
    s = s.lstrip(b"\x00").rjust(32, b"\x00")
    if len(r) != 32 or len(s) != 32:
        raise ValueError("r/s out of range for P-256")
    return r + s


def main() -> None:
    if len(sys.argv) < 4:
        sys.stderr.write("usage: asc-jwt.py <key_path> <key_id> <issuer_id> [exp_seconds]\n")
        sys.exit(2)

    key_path, key_id, issuer_id = sys.argv[1], sys.argv[2], sys.argv[3]
    exp_seconds = int(sys.argv[4]) if len(sys.argv) > 4 else 300
    exp_seconds = min(exp_seconds, 1200)  # ASC rejects tokens with >20 min lifetime

    if not os.path.isfile(key_path):
        sys.stderr.write(f"asc-jwt: private key not found: {key_path}\n")
        sys.exit(1)

    now = int(time.time())
    header = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
    payload = {"iss": issuer_id, "iat": now, "exp": now + exp_seconds, "aud": "appstoreconnect-v1"}
    signing_input = (
        b64url(json.dumps(header, separators=(",", ":")).encode())
        + "."
        + b64url(json.dumps(payload, separators=(",", ":")).encode())
    )

    try:
        der = subprocess.run(
            ["openssl", "dgst", "-sha256", "-sign", key_path],
            input=signing_input.encode(),
            capture_output=True,
            check=True,
        ).stdout
    except FileNotFoundError:
        sys.stderr.write("asc-jwt: openssl not found on PATH\n")
        sys.exit(1)
    except subprocess.CalledProcessError as exc:
        sys.stderr.write("asc-jwt: openssl signing failed: " + exc.stderr.decode(errors="replace") + "\n")
        sys.exit(1)

    try:
        raw = der_to_raw(der)
    except (ValueError, IndexError) as exc:
        sys.stderr.write(f"asc-jwt: malformed ECDSA signature from openssl: {exc}\n")
        sys.exit(1)

    sys.stdout.write(signing_input + "." + b64url(raw) + "\n")


if __name__ == "__main__":
    main()
