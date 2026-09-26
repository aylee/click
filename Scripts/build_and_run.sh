#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
"$ROOT/Scripts/package_app.sh" debug
open "$ROOT/build/Click.app" --args "$@"
