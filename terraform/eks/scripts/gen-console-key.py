#!/usr/bin/env python3
"""Terraform `external` data source: derive the C04 console-identity PUBLIC key from a seed.

This is a PURE FUNCTION: it reads a base64 32-byte Ed25519 seed on stdin and returns only the
matching public key. It never emits the private seed, so nothing secret ends up in the (non-
sensitive) data-source result, plan output, or CI logs. The seed itself is generated and held
by a persisted `random_id` resource in Terraform state — so the keypair is STABLE across
applies (no console-key rotation / pod restarts on every `terraform apply`).

Input  (stdin JSON, per the Terraform external protocol): {"seed_b64": "<base64 of 32 bytes>"}
Output (stdout JSON):                                      {"public_pem": "<SPKI PEM>"}

The raw seed is what identity's load_or_create() adopts (mounted as a 32-byte file), and the
public PEM is what management-api pins as GF_IDENTITY_CONSOLE_PUBKEY — both derive from the one
seed, so C04-signed console tokens validate. Depends only on stdlib + `cryptography`.
"""
import base64
import json
import sys


def main() -> None:
    try:
        query = json.load(sys.stdin)
    except Exception:
        query = {}

    seed_b64 = query.get("seed_b64", "")
    try:
        seed = base64.b64decode(seed_b64)
    except Exception:
        sys.stderr.write("gen-console-key.py: seed_b64 is not valid base64\n")
        sys.exit(1)

    if len(seed) != 32:
        sys.stderr.write(f"gen-console-key.py: seed must decode to 32 bytes, got {len(seed)}\n")
        sys.exit(1)

    try:
        from cryptography.hazmat.primitives import serialization
        from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
    except ImportError:
        sys.stderr.write(
            "gen-console-key.py requires the 'cryptography' package: pip install cryptography\n"
        )
        sys.exit(1)

    public_pem = (
        Ed25519PrivateKey.from_private_bytes(seed)
        .public_key()
        .public_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PublicFormat.SubjectPublicKeyInfo,
        )
        .decode("ascii")
    )

    # Terraform's external provider requires all result values to be strings.
    json.dump({"public_pem": public_pem}, sys.stdout)


if __name__ == "__main__":
    main()
