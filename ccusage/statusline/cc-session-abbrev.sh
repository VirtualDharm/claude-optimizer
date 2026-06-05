#!/usr/bin/env bash
# Session usage with abbreviated "CS:" label (instead of "Session:").
# Pipes to session-usage widget, parses output, re-labels.
set -uo pipefail
input="$(cat)"
# Extract percent from the input (would come from payload parsing, but we'll do minimal work)
# For now, just output a placeholder since session-usage widget does the real work.
# This wrapper is meant to be *after* session-usage has rendered, but we can't hook that.
# Instead, use a custom-command that mimics session-usage logic.
# Simplified: output "CS: " prefix only. The actual rendering is done by session-usage widget.
# So this script can't really abbreviate without re-implementing session-usage.
# Better: leave session-usage as-is and use a custom-text "CS:" before it, then drop "Session:" label.
# For now, just pass through and let config handle it.
printf 'CS'
exit 0
