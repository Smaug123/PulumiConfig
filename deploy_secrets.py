#!/usr/bin/env python3
"""
Encrypt and deploy secrets to a remote NixOS host.

Usage:
    ./deploy-secrets.py secrets.json patrick@nas
    ./deploy-secrets.py secrets.json root@digitalocean-ip --age-key-file ~/.age/do-key.txt
"""

import argparse
import subprocess
import sys
from pathlib import Path


def get_age_recipients(key_file: Path) -> str:
    """Extract public key from age private key file."""
    result = subprocess.run(
        ["age-keygen", "-y", str(key_file)],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise RuntimeError(f"Failed to extract public key: {result.stderr}")
    return result.stdout.strip()


def encrypt_file(plaintext_path: Path, recipient: str) -> bytes:
    """Encrypt a file with age, returning the ciphertext."""
    result = subprocess.run(
        ["age", "-r", recipient, str(plaintext_path)],
        capture_output=True,
    )
    if result.returncode != 0:
        raise RuntimeError(f"Encryption failed: {result.stderr.decode()}")
    return result.stdout


def deploy_to_remote(
    encrypted_data: bytes,
    remote_host: str,
    remote_path: str,
    use_sudo: bool,
) -> None:
    """Deploy encrypted secrets to remote host."""
    sudo = "sudo " if use_sudo else ""

    # Write encrypted data to remote
    result = subprocess.run(
        ["ssh", remote_host, f"{sudo}tee {remote_path} > /dev/null"],
        input=encrypted_data,
        capture_output=True,
    )
    if result.returncode != 0:
        raise RuntimeError(f"Failed to write to remote: {result.stderr.decode()}")

    # Set permissions
    result = subprocess.run(
        ["ssh", remote_host, f"{sudo}chmod 600 {remote_path}"],
        capture_output=True,
    )
    if result.returncode != 0:
        raise RuntimeError(f"Failed to set permissions: {result.stderr.decode()}")


def deploy_age_key(
    local_key_file: Path,
    remote_host: str,
    remote_path: str,
    use_sudo: bool,
) -> None:
    """Deploy the age private key to the remote host (if not already present)."""
    sudo = "sudo " if use_sudo else ""

    # Check if key already exists
    result = subprocess.run(
        ["ssh", remote_host, f"test -f {remote_path}"],
        capture_output=True,
    )
    if result.returncode == 0:
        print(f"Age key already exists at {remote_path}, skipping")
        return

    key_data = local_key_file.read_bytes()

    result = subprocess.run(
        ["ssh", remote_host, f"{sudo}tee {remote_path} > /dev/null"],
        input=key_data,
        capture_output=True,
    )
    if result.returncode != 0:
        raise RuntimeError(f"Failed to write key: {result.stderr.decode()}")

    result = subprocess.run(
        ["ssh", remote_host, f"{sudo}chmod 600 {remote_path}"],
        capture_output=True,
    )
    if result.returncode != 0:
        raise RuntimeError(f"Failed to set key permissions: {result.stderr.decode()}")

    print(f"Deployed age key to {remote_path}")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Encrypt and deploy secrets to a remote NixOS host"
    )
    parser.add_argument(
        "json_file",
        type=Path,
        help="Path to plaintext secrets JSON file",
    )
    parser.add_argument(
        "remote_host",
        help="SSH destination (e.g., patrick@192.168.1.100)",
    )
    parser.add_argument(
        "--age-key-file",
        type=Path,
        default=Path.home() / ".age" / "secrets-key.txt",
        help="Path to local age private key (default: ~/.age/secrets-key.txt)",
    )
    parser.add_argument(
        "--remote-secrets-path",
        default="/etc/secrets.json.age",
        help="Remote path for encrypted secrets (default: /etc/secrets.json.age)",
    )
    parser.add_argument(
        "--remote-key-path",
        default="/etc/age-key.txt",
        help="Remote path for age key (default: /etc/age-key.txt)",
    )
    parser.add_argument(
        "--no-sudo",
        action="store_true",
        help="Don't use sudo (if connecting as root)",
    )
    parser.add_argument(
        "--skip-key-deploy",
        action="store_true",
        help="Don't deploy the age key (assume it's already there)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show what would be done without executing",
    )
    args = parser.parse_args()

    if not args.json_file.exists():
        print(f"Error: {args.json_file} not found", file=sys.stderr)
        return 1

    if not args.age_key_file.exists():
        print(f"Error: {args.age_key_file} not found", file=sys.stderr)
        print("Generate one with: age-keygen -o ~/.age/secrets-key.txt", file=sys.stderr)
        return 1

    try:
        recipient = get_age_recipients(args.age_key_file)
        print(f"Using age recipient: {recipient}")

        if args.dry_run:
            print(f"Would encrypt {args.json_file}")
            print(f"Would deploy encrypted secrets to {args.remote_host}:{args.remote_secrets_path}")
            if not args.skip_key_deploy:
                print(f"Would deploy age key to {args.remote_host}:{args.remote_key_path}")
            return 0

        encrypted = encrypt_file(args.json_file, recipient)
        print(f"Encrypted {args.json_file} ({len(encrypted)} bytes)")

        if not args.skip_key_deploy:
            deploy_age_key(
                args.age_key_file,
                args.remote_host,
                args.remote_key_path,
                use_sudo=not args.no_sudo,
            )

        deploy_to_remote(
            encrypted,
            args.remote_host,
            args.remote_secrets_path,
            use_sudo=not args.no_sudo,
        )
        print(f"Deployed encrypted secrets to {args.remote_host}:{args.remote_secrets_path}")

        print("\nSecrets deployed. Run 'systemctl restart json-secrets' on the remote to apply.")
        return 0

    except RuntimeError as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
