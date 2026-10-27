"""Check the explicit public-file set before a commit or distribution."""
from pathlib import Path
import re
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
manifest = root / "public-files.txt"
allowed = [s.strip() for s in manifest.read_text(encoding="utf-8").splitlines() if s.strip()]
errors = []
if len(allowed) != len(set(allowed)):
    errors.append("Duplicate public manifest entry")
for name in allowed:
    path = root / name
    if not path.is_file() or not path.resolve().is_relative_to(root):
        errors.append(f"Missing or invalid public file: {name}")
        continue
    contents = path.read_text(encoding="utf-8-sig")
    checks = {
        "credential": r"(?:gh[pousr]_[A-Za-z0-9]{25,}|github_pat_[A-Za-z0-9_]{30,}|-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----)",
        "personal path": r"[A-Za-z]:[\\/]Users[\\/][^\\/\s]+",
        "email": r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b",
        "commit attribution": r"(?im)^\s*(?:co-authored-by|generated-by|assisted-by)\s*:",
    }
    for label, pattern in checks.items():
        if re.search(pattern, contents):
            errors.append(f"Review {label} in {name}")
    if path.suffix == ".md":
        for target in re.findall(r"\]\(([^)]+)\)", contents):
            if "://" not in target and not target.startswith("#") and not (path.parent / target.split("#")[0]).is_file():
                errors.append(f"Broken documentation link: {name} -> {target}")
    if name.startswith("docs/") and ".ko." in name:
        if name.replace(".ko.", ".en.") not in allowed:
            errors.append(f"Missing English guide for {name}")

result = subprocess.run(["git", "ls-files", "--cached", "--others", "--exclude-standard"], cwd=root, text=True, capture_output=True)
if result.returncode:
    errors.append("Unable to inspect Git file selection")
else:
    for name in result.stdout.splitlines():
        if name not in allowed:
            errors.append(f"Unexpected public file: {name}")
for name in [".mesh/STATE.md", "AGENTS.md", "GEMINI.md", "build/private.db", ".local/history.db"]:
    ignored = subprocess.run(["git", "check-ignore", "-q", name], cwd=root)
    if ignored.returncode != 0:
        errors.append(f"Private path is not ignored: {name}")
if errors:
    print("\n".join(errors))
    sys.exit(1)
print(f"PASS: {len(allowed)} public files; private paths excluded; documentation links checked")
