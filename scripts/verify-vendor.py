#!/usr/bin/env python3
"""Verify the single vendored iodine engine; no third-party Python dependencies."""
import argparse
import hashlib
from pathlib import Path
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--update", action="store_true", help="regenerate checksums after a reviewed engine edit")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    engine = root / "vendor" / "iodine"
    for old in (root / "ios/vendor/iodine", root / "android/jni/iodine"):
        if old.exists() or old.is_symlink():
            sys.exit(f"Duplicate iodine tree: {old.relative_to(root)}; use vendor/iodine instead")
    sources = sorted(path for path in (engine / "src").iterdir() if path.is_file())
    if not sources or any(path.suffix not in {".c", ".h"} for path in sources):
        sys.exit("vendor/iodine/src must contain the canonical C and header files")
    paths = [engine / "LICENSE", *sources]
    expected = "".join(f"{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.relative_to(engine).as_posix()}\n" for path in paths)
    manifest = engine / "SHA256SUMS"
    if args.update:
        manifest.write_text(expected, encoding="ascii")
        print(f"Updated {len(paths)} shared iodine checksums")
    elif not manifest.exists() or manifest.read_text(encoding="ascii") != expected:
        sys.exit("Shared iodine manifest mismatch; review source changes before using --update")
    else:
        print(f"Verified {len(paths)} shared iodine files; no duplicated platform engines")


if __name__ == "__main__":
    main()
