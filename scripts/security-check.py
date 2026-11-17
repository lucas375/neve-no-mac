#!/usr/bin/env python3
"""Review exactly the Git index before publishing; print locations, never matching secret values."""
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
GIT = "/usr/bin/git"

RULES = {
    "private key": rb"-----BEGIN (?:[A-Z0-9 ]+ )?PRIVATE KEY-----",
    "GitHub token": rb"\b(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{50,})\b",
    "AWS access key": rb"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b",
    "API token": rb"\bsk-(?:proj-|svcacct-)?[A-Za-z0-9_-]{24,}\b",
    "credential in URL": rb"https?://[^\s/:]+:[^\s/@]+@",
    "hardcoded credential": rb"(?i)(?:password|api[_-]?key|access[_-]?token|client[_-]?secret)\s*[:=]\s*[\"'][A-Za-z0-9/+_=-]{16,}[\"']",
    "local home path": rb"/(?:Users|home)/[A-Za-z0-9_.-]+/",
}
ALLOWED_ROOTS = {"Sources", "Tests", "scripts", "docs", ".github", "windows"}
ALLOWED_FILES = {".gitignore", "Package.swift", "README.md", "SECURITY.md"}
FORBIDDEN_SUFFIXES = {".jpg", ".jpeg", ".png", ".image", ".pem", ".key", ".p12", ".pfx", ".mobileprovision", ".memgraph", ".log"}


def git(*args):
    return subprocess.check_output([GIT, *args], cwd=ROOT)


def main():
    entries = git("ls-files", "--stage", "-z").split(b"\0")
    failures = []
    checked = 0
    for entry in filter(None, entries):
        meta, raw_path = entry.split(b"\t", 1)
        mode, sha, stage = meta.split()
        path = raw_path.decode("utf-8")
        parts = PurePosixPath(path).parts
        if mode not in {b"100644", b"100755"} or stage != b"0":
            failures.append(f"{path}: unsupported index entry (symlink, submodule or conflict)")
            continue
        if (len(parts) == 1 and path not in ALLOWED_FILES) or (len(parts) > 1 and parts[0] not in ALLOWED_ROOTS):
            failures.append(f"{path}: outside the publication allowlist")
        if PurePosixPath(path).suffix.lower() in FORBIDDEN_SUFFIXES or any(p.startswith(".env") for p in parts):
            failures.append(f"{path}: private, binary or third-party resource")
        content = git("cat-file", "blob", sha.decode("ascii"))
        if len(content) > 512_000 or b"\0" in content:
            failures.append(f"{path}: unexpectedly large or binary file")
            continue
        for name, pattern in RULES.items():
            for match in re.finditer(pattern, content):
                line = content[:match.start()].count(b"\n") + 1
                failures.append(f"{path}:{line}: {name}")
        checked += 1
    if checked == 0:
        failures.append("No staged files to review")
    if failures:
        print("Security check FAILED:\n" + "\n".join(failures))
        return 1
    print(f"Security check passed: {checked} staged text files; no matching secrets or private resources.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
