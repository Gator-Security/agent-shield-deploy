#!/usr/bin/env python3
"""Generate the argon2id password hash for the bootstrap console admin.

Identity REFUSES a plaintext-looking GF_BOOTSTRAP_ADMIN_PASSWORD_HASH — it must be a
real $argon2id$ hash. This helper prompts for a password (never echoed, never stored)
and prints the hash to paste into terraform.tfvars (bootstrap_admin_password_hash) or
your Secret. The password itself never touches Terraform state or the cluster.

Requires: pip install argon2-cffi
"""
import getpass
import sys


def main() -> None:
    try:
        from argon2 import PasswordHasher
    except ImportError:
        sys.stderr.write("make_admin_hash.py requires argon2-cffi: pip install argon2-cffi\n")
        sys.exit(1)

    pw = getpass.getpass("Console admin password (input hidden): ")
    if len(pw) < 12:
        sys.stderr.write("ERROR: use at least 12 characters.\n")
        sys.exit(1)
    if pw != getpass.getpass("Confirm password: "):
        sys.stderr.write("ERROR: passwords do not match.\n")
        sys.exit(1)

    print(PasswordHasher().hash(pw))


if __name__ == "__main__":
    main()
