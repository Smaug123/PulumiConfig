"""
Decrypt age-encrypted JSON secrets and deploy to /run/secrets/.

Each secret in {"service": {"key": "value"}} becomes /run/secrets/service_key
owned by service:service (with overrides for special cases).
"""

import argparse
import grp
import json
import os
import pwd
import subprocess
import sys
from pathlib import Path

try:
    import bcrypt
except ImportError:
    bcrypt = None


DEFAULT_SERVICE_OWNERSHIP: dict[str, tuple[str, str]] = {
    "woodpecker": ("gitea", "gitea"),
}


def hash_password(password: str) -> str:
    """Hash a password using bcrypt for htpasswd."""
    if bcrypt is None:
        raise RuntimeError("bcrypt not available, cannot hash password")
    password_bytes = password.encode('utf-8')
    salt = bcrypt.gensalt()
    hashed = bcrypt.hashpw(password_bytes, salt)
    return hashed.decode('utf-8')


def get_uid(name: str) -> int:
    try:
        return pwd.getpwnam(name).pw_uid
    except KeyError:
        print(f"Warning: user {name} not found, using root", file=sys.stderr)
        return 0


def get_gid(name: str) -> int:
    try:
        return grp.getgrnam(name).gr_gid
    except KeyError:
        print(f"Warning: group {name} not found, using root", file=sys.stderr)
        return 0


def decrypt_secrets(
    encrypted_path: Path, age_binary: Path, key_path: Path
) -> dict:
    result = subprocess.run(
        [str(age_binary), "-d", "-i", str(key_path), str(encrypted_path)],
        capture_output=True,
    )
    if result.returncode != 0:
        raise RuntimeError(f"Decryption failed: {result.stderr.decode()}")
    return json.loads(result.stdout)


def deploy_secret(
    filepath: Path, value: str, uid: int, gid: int, mode: int = 0o440
) -> None:
    # Create file with restrictive permissions first
    fd = os.open(filepath, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o400)
    try:
        os.write(fd, value.encode())
    finally:
        os.close(fd)
    # Set ownership and permissions explicitly (not affected by umask)
    os.chown(filepath, uid, gid)
    os.chmod(filepath, mode)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Deploy secrets from encrypted JSON"
    )
    parser.add_argument(
        "encrypted_file",
        type=Path,
        help="Path to age-encrypted secrets JSON",
    )
    parser.add_argument(
        "--age-binary",
        type=Path,
        default=Path("/usr/bin/age"),
        help="Path to age binary",
    )
    parser.add_argument(
        "--key-file",
        type=Path,
        default=Path("/etc/age-key.txt"),
        help="Path to age private key",
    )
    parser.add_argument(
        "--secrets-dir",
        type=Path,
        default=Path("/run/secrets"),
        help="Directory to write decrypted secrets",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print what would be done without writing",
    )
    args = parser.parse_args()

    if not args.encrypted_file.exists():
        print(f"Error: {args.encrypted_file} not found", file=sys.stderr)
        return 1

    if not args.key_file.exists():
        print(f"Error: {args.key_file} not found", file=sys.stderr)
        return 1

    try:
        secrets = decrypt_secrets(
            args.encrypted_file, args.age_binary, args.key_file
        )
    except RuntimeError as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1

    if not args.dry_run:
        args.secrets_dir.mkdir(mode=0o755, exist_ok=True)

    # Extract ownership overrides from _ownership key if present
    ownership_config = secrets.pop("_ownership", {})

    for service, service_secrets in secrets.items():
        # Default ownership: service user/group
        default_owner, default_group = DEFAULT_SERVICE_OWNERSHIP.get(
            service, (service, service)
        )

        for key, value in service_secrets.items():
            filepath = args.secrets_dir / f"{service}_{key}"
            secret_name = f"{service}_{key}"

            # Check for custom ownership in _ownership config
            if secret_name in ownership_config:
                owner, group = ownership_config[secret_name]
            else:
                owner, group = default_owner, default_group

            uid = get_uid(owner)
            gid = get_gid(group)

            # Special case: htcrypt_password needs to be combined with user
            # into htpasswd format: "username:bcrypt_hash"
            if key == "htcrypt_password" and "user" in service_secrets:
                password_hash = hash_password(value)
                value = f"{service_secrets['user']}:{password_hash}"

            # Database passwords owned by root need to be world-readable
            # so postgres (via sudo) can read them
            mode = 0o444 if uid == 0 else 0o440

            if args.dry_run:
                preview = value[:20] + "..." if len(value) > 20 else value
                mode_str = "0444" if mode == 0o444 else "0440"
                msg = f"Would create {filepath} ({owner}:{group}, {mode_str})"
                msg += f": {preview}"
                print(msg)
            else:
                deploy_secret(filepath, value, uid, gid, mode)
                mode_str = "0444" if mode == 0o444 else "0440"
                print(f"Created {filepath} ({owner}:{group}, {mode_str})")

    return 0


if __name__ == "__main__":
    sys.exit(main())
