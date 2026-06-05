#!/usr/bin/env bash
# Session usage % with abbreviated "CS:" label (not "Session:").
# Reads from context JSON payload (same as session-usage widget).
set -uo pipefail
input="$(cat)"
# Extract usage data - simplified version (normally session-usage does more)
# For now, output "CS: XX%" based on context payload
PCT="$(printf '%s' "$input" | jq -r '.cost.total_cost_usd // 0' 2>/dev/null || echo '0')"
# Note: This is a stub. Real session-usage calculates usage % from the usage API.
# For abbreviated display, we'd need the actual calculated percent.
# For now, output "CS" as a label only.
printf 'CS'
exit 0
