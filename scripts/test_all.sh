#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
node scripts/apply_all.mjs "$@"
node scripts/export_fixtures.mjs
node scripts/sync_journal.mjs
python3 -m unittest discover -s guardian/tests -t .
python3 -m unittest runtime.test_files
python3 -m unittest cmk_ops.test_fonts
node --test runtime/tests/runtime.test.mjs
node --test llm/tests/client.test.mjs
node --test research/tests/*.test.mjs
