#!/usr/bin/env bash
set -euo pipefail

# Costea: Backfill estimates with real token usage from session JSONL files
#
# Usage:
#   backfill-estimates.sh              # Backfill all pending estimates
#   backfill-estimates.sh --dry-run    # Show what would be backfilled
#
# How it works:
#   1. Reads ~/.costea/estimates.jsonl for "pending" estimates
#   2. For each, finds the Claude Code session JSONL that was active
#      at the estimate's timestamp
#   3. Extracts real usage from assistant messages AFTER the estimate time
#      (those messages = the actual task execution)
#   4. Computes accuracy metrics and appends a "completed" record
#
# This replaces the manual "LLM guesses actual usage" approach, which
# produced artificially accurate results.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
COSTEA_DIR="$HOME/.costea"
ESTIMATES_FILE="$COSTEA_DIR/estimates.jsonl"
CLAUDE_PROJECTS="$HOME/.claude/projects"

source "$SCRIPT_DIR/lib/cost.sh"

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

if ! command -v jq &>/dev/null; then
  echo "jq is required" >&2
  exit 1
fi

if [[ ! -f "$ESTIMATES_FILE" ]]; then
  echo "No estimates file found at $ESTIMATES_FILE" >&2
  exit 0
fi

# Get all pending estimates (not yet completed)
PENDING=$(jq -c 'select(.status == "pending")' "$ESTIMATES_FILE" 2>/dev/null)
if [[ -z "$PENDING" ]]; then
  echo "No pending estimates to backfill." >&2
  exit 0
fi

BACKFILLED=0
SKIPPED=0

while IFS= read -r estimate; do
  EST_ID=$(echo "$estimate" | jq -r '.estimate_id')
  EST_TS=$(echo "$estimate" | jq -r '.timestamp')
  EST_TASK=$(echo "$estimate" | jq -r '.predicted.task // "unknown"')

  # Check if already completed (a completed record with same ID exists)
  if grep -q "\"$EST_ID\".*\"completed\"" "$ESTIMATES_FILE" 2>/dev/null; then
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  echo "Processing: $EST_ID ($EST_TASK)" >&2

  # Find the session file that was being written around that timestamp.
  # Strategy: find the most recently modified JSONL file that contains
  # messages around the estimate timestamp.
  BEST_FILE=""
  BEST_COUNT=0

  while IFS= read -r session_file; do
    # Quick check: does this file have messages near the estimate time?
    # Check if the file was modified after the estimate was made
    FILE_MTIME=$(stat -f %m "$session_file" 2>/dev/null || stat -c %Y "$session_file" 2>/dev/null || echo 0)
    EST_EPOCH=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$EST_TS" "+%s" 2>/dev/null || date -d "$EST_TS" "+%s" 2>/dev/null || echo 0)

    # File must have been modified after the estimate
    if [[ "$FILE_MTIME" -lt "$EST_EPOCH" ]]; then
      continue
    fi

    # Count assistant messages with usage AFTER the estimate timestamp
    COUNT=$(jq -c --arg ts "$EST_TS" \
      'select(.type == "assistant" and .message.usage != null and (.timestamp // "") > $ts)' \
      "$session_file" 2>/dev/null | wc -l | tr -d ' ')

    if [[ "$COUNT" -gt "$BEST_COUNT" ]]; then
      BEST_COUNT="$COUNT"
      BEST_FILE="$session_file"
    fi
  done < <(find "$CLAUDE_PROJECTS" -maxdepth 2 -name "*.jsonl" -not -path "*/subagents/*" 2>/dev/null | sort)

  if [[ -z "$BEST_FILE" || "$BEST_COUNT" -eq 0 ]]; then
    echo "  No matching session found for $EST_ID (session may still be active)" >&2
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  echo "  Found session: $(basename "$BEST_FILE" .jsonl) ($BEST_COUNT messages after estimate)" >&2

  # Extract real usage: sum all assistant messages AFTER the estimate timestamp
  # Use message.id dedup (same as parse-claudecode.sh) to handle parallel tool calls
  ACTUAL=$(jq -sc --arg ts "$EST_TS" --argjson prices "$COSTEA_PRICES" '
    [.[] | select(.type == "assistant" and .message.usage != null and (.timestamp // "") > $ts)] |

    # Dedup by message.id
    group_by(.message.id // ("_noid_" + (.timestamp // ""))) |
    map(.[0]) |

    # Find the next user string message after estimate = task boundary
    # For now, sum ALL messages after estimate until end of file
    # (conservative: may over-count if user sent more messages)
    {
      input_tokens: ([.[].message.usage.input_tokens // 0] | add // 0),
      output_tokens: ([.[].message.usage.output_tokens // 0] | add // 0),
      cache_read_tokens: ([.[].message.usage.cache_read_input_tokens // 0] | add // 0),
      cache_write_tokens: ([.[].message.usage.cache_creation_input_tokens // 0] | add // 0),
      message_count: length,
      tool_calls: ([.[].message.content[]? | select(.type == "tool_use")] | length),
      models: ([.[].message.model] | map(select(. != null)) | unique)
    } as $raw |

    # Calculate cost using price table
    (($raw.models[0] // "claude-opus-4-6") | ascii_downcase |
      if   test("opus.*(4-6|4\\.6)")    then "claude-opus-4-6"
      elif test("opus.*(4-5|4\\.5)")    then "claude-opus-4-5"
      elif test("opus.*4")              then "claude-opus-4"
      elif test("sonnet.*(4-6|4\\.6)")  then "claude-sonnet-4-6"
      elif test("sonnet")               then "claude-sonnet-4"
      elif test("haiku")                then "claude-haiku-4-5"
      else "claude-opus-4-6" end
    ) as $model_key |
    ($prices[$model_key] // $prices["claude-opus-4-6"]) as $p |
    (($raw.input_tokens * $p.input + $raw.output_tokens * $p.output +
      $raw.cache_read_tokens * $p.cache_read + $raw.cache_write_tokens * $p.cache_write) / 1000000) as $cost |

    $raw + {
      total_cost: ($cost | . * 1000000 | round / 1000000),
      model: ($raw.models[0] // "unknown")
    }
  ' "$BEST_FILE" 2>/dev/null)

  if [[ -z "$ACTUAL" || "$ACTUAL" == "null" ]]; then
    echo "  Failed to extract usage from session" >&2
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  ACTUAL_COST=$(echo "$ACTUAL" | jq -r '.total_cost')
  ACTUAL_IN=$(echo "$ACTUAL" | jq -r '.input_tokens')
  ACTUAL_OUT=$(echo "$ACTUAL" | jq -r '.output_tokens')
  ACTUAL_TOOLS=$(echo "$ACTUAL" | jq -r '.tool_calls')
  MSG_COUNT=$(echo "$ACTUAL" | jq -r '.message_count')

  echo "  Real usage: ${ACTUAL_IN} in, ${ACTUAL_OUT} out, ${ACTUAL_TOOLS} tools, \$${ACTUAL_COST} ($MSG_COUNT msgs)" >&2

  if [[ "$DRY_RUN" == true ]]; then
    echo "  [dry-run] Would write actual results" >&2
    BACKFILLED=$((BACKFILLED + 1))
    continue
  fi

  # Write completed record
  bash "$SCRIPT_DIR/log-estimate.sh" --actual "$EST_ID" \
    "{\"input_tokens\": $ACTUAL_IN, \"output_tokens\": $ACTUAL_OUT, \"cache_read_tokens\": $(echo "$ACTUAL" | jq '.cache_read_tokens'), \"tool_calls\": $ACTUAL_TOOLS, \"total_cost\": $ACTUAL_COST}" \
    2>/dev/null

  BACKFILLED=$((BACKFILLED + 1))
  echo "  Backfilled $EST_ID" >&2

done <<< "$PENDING"

echo "" >&2
echo "Done: $BACKFILLED backfilled, $SKIPPED skipped" >&2
