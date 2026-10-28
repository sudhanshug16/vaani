#!/usr/bin/env python3
"""Restore the release identity into an isolated CI keychain, without root trust."""
import base64
import os
from pathlib import Path
import subprocess


def main():
    encoded = os.environ.get("MACOS_SIGNING_P12_BASE64")
    password = os.environ.get("MACOS_SIGNING_PASSWORD")
    if not encoded or not password:
        raise SystemExit("Missing permanent Mac signing secrets; refusing ad-hoc release")
    root = Path(os.environ["RUNNER_TEMP"])
    p12 = root / "vaani-macos-release.p12"
    keychain = root / "vaani-signing.keychain-db"

    def security(*args):
        # Never log the command, password, or imported private material.
        result = subprocess.run(["security", *args], capture_output=True)
        if result.returncode:
            raise RuntimeError("Mac signing keychain setup failed")

    try:
        p12.write_bytes(base64.b64decode(encoded, validate=True))
        p12.chmod(0o600)
        security("create-keychain", "-p", password, str(keychain))
        security("set-keychain-settings", "-lut", "21600", str(keychain))
        security("unlock-keychain", "-p", password, str(keychain))
        security("import", str(p12), "-k", str(keychain), "-P", password,
                 "-T", "/usr/bin/codesign")
        security("set-key-partition-list", "-S", "apple-tool:,apple:,codesign:",
                 "-s", "-k", password, str(keychain))
        with open(os.environ["GITHUB_ENV"], "a") as output:
            output.write("VAANI_SIGN_IDENTITY=Vaani Release Signing\n")
            output.write(f"VAANI_SIGN_KEYCHAIN={keychain}\n")
    except Exception:
        if keychain.exists():
            security("delete-keychain", str(keychain))
        raise
    finally:
        p12.unlink(missing_ok=True)


if __name__ == "__main__":
    main()
