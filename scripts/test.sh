#!/bin/bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
node --test tests/*.test.cjs
python3 -m unittest discover -s tests -p '*_test.py'
