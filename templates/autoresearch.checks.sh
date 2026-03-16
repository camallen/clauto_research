#!/bin/bash
# Autoresearch backpressure checks (optional)
# Copy this to your project root as autoresearch.checks.sh
# If this script fails, the experiment is reverted regardless of metric improvement.
#
# Examples:
#   npm test
#   npx tsc --noEmit
#   npm run lint

set -euo pipefail

# Add your validation commands here:
# npm test
# npx tsc --noEmit

echo "CHECKS_PASSED"
