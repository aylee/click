#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
LANE=${1:-all}
case "$LANE" in all|build|test|privacy) ;; *) echo "Usage: $0 [all|build|test|privacy]" >&2; exit 2 ;; esac
if [[ "$LANE" == all || "$LANE" == build ]]; then
    swift build --product Click
fi
if [[ "$LANE" == all || "$LANE" == test ]]; then
    swift run ClickTests
fi
if [[ "$LANE" == all || "$LANE" == privacy ]]; then
    python3 - <<'PYTHON'
from pathlib import Path
import re
import sys

# A source regression check, not a network sandbox or a complete security audit.
patterns = {
    "network framework": r"\bimport\s+(?:Network|CFNetwork|FoundationNetworking|WebKit)\b",
    "network client": r"\b(?:URLSession|URLRequest|NSURLConnection|NWConnection|NWListener|WKWebView|CFHTTPMessage|CFStreamCreatePairWithSocketToHost|getaddrinfo)\b|\bsocket\s*\(",
    "remote URL": r'"(?:https?|wss?|ftp)://',
    "service SDK": r"\b(?:Sparkle|SUUpdater|SPUStandardUpdaterController|Firebase|SentrySDK|TelemetryDeck|Mixpanel|Amplitude|Auth0|ASWebAuthenticationSession)\b",
}
problems = []
for path in sorted(Path("Sources").rglob("*")):
    if path.suffix not in {".swift", ".c", ".h"}:
        continue
    for number, line in enumerate(path.read_text().splitlines(), 1):
        if line.lstrip().startswith("//"):
            continue
        for label, pattern in patterns.items():
            if re.search(pattern, line):
                problems.append(f"{path}:{number}: {label}: {line.strip()}")
if re.search(r"\.package\s*\(", Path("Package.swift").read_text()):
    problems.append("Package.swift: package dependencies require a privacy review")
if problems:
    print("Privacy regression check failed:\n" + "\n".join(problems), file=sys.stderr)
    sys.exit(1)
print("Privacy source check passed: no matched network, service SDK, remote URL, or package dependency patterns.")
PYTHON
fi
