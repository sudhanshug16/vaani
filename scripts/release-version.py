#!/usr/bin/env python3
"""Validate a release tag; emit matching Mac/Android version metadata."""
import re
import sys


def metadata(tag):
    match = re.fullmatch(r"v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)", tag)
    if not match:
        raise ValueError("Use a tag like v0.1.0 (three numbers, no leading zeros).")
    major, minor, patch = map(int, match.groups())
    code = major * 1_000_000 + minor * 1_000 + patch
    if minor > 999 or patch > 999 or not 1 <= code <= 2_100_000_000:
        raise ValueError("Version exceeds Android versionCode limits; minor/patch must be <=999 and version >0.0.0.")
    return {"version": tag[1:], "code": str(code)}


if __name__ == "__main__":
    try:
        values = metadata(sys.argv[1])
    except (ValueError, IndexError) as error:
        sys.exit(str(error))
    for key, value in values.items():
        print(f"{key}={value}")
