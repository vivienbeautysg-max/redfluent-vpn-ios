#!/usr/bin/env bash
# Compiles the pure-Foundation logic (regions, usage, runtime-config rules, API decoding) together
# with Tests/SelfTest/main.swift and runs it. No simulator or signing needed.
#
# Usage: scripts/selftest.sh

set -euo pipefail

cd "$(dirname "$0")/.."

OUT="$(mktemp -d)/rfv-selftest"

swiftc -o "$OUT" \
  App/Regions.swift \
  App/StartAttempt.swift \
  App/UsageMetrics.swift \
  App/APIClient.swift \
  Tunnel/RuntimeConfigRequest.swift \
  Tunnel/SharedContainer.swift \
  Tunnel/StatsSnapshot.swift \
  Tests/SelfTest/main.swift

"$OUT"
