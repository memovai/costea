#!/usr/bin/env bash
set -euo pipefail

# Costea: Estimate cost for a new task using historical task index
# Uses the task index built by build-index.sh + session summaries
# Output: JSON with historical data, aggregated stats, and provider prices
#
# The output is consumed by the /costea skill (SKILL.md), which
# uses LLM reasoning to match similar tasks and build a receipt.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
COSTEA_DIR="$HOME/.costea"
INDEX_FILE="$COSTEA_DIR/task-index.json"
SESSION_INDEX="$COSTEA_DIR/index.json"

source "$SCRIPT_DIR/lib/cost.sh"

TASK_DESC="${1:-}"

if [[ -z "$TASK_DESC" ]]; then
  echo '{"error": "No task description provided"}'
  exit 1
fi

if ! command -v jq &>/dev/null; then
  echo '{"error": "jq is required"}'
  exit 1
fi

# Rebuild index if missing or stale (older than 1 hour)
if [[ ! -f "$INDEX_FILE" ]] || [[ $(find "$INDEX_FILE" -mmin +60 2>/dev/null) ]]; then
  bash "$SCRIPT_DIR/build-index.sh" >/dev/null 2>&1 || true
fi

# If still no index, return empty
if [[ ! -f "$INDEX_FILE" ]]; then
  jq -n --arg task "$TASK_DESC" \
    --argjson providers "$COSTEA_PROVIDERS" \
    '{task: $task, has_history: false, task_count: 0,
     history_summary: "No historical task data available.",
     provider_prices: $providers, session_stats: null}'
  exit 0
fi

task_count=$(jq '.task_count // 0' "$INDEX_FILE")

if [[ "$task_count" -eq 0 ]]; then
  jq -n --arg task "$TASK_DESC" \
    --argjson providers "$COSTEA_PROVIDERS" \
    '{task: $task, has_history: false, task_count: 0,
     history_summary: "No historical task data available.",
     provider_prices: $providers, session_stats: null}'
  exit 0
fi

TMPDIR_COSTEA=$(mktemp -d)
trap 'rm -rf "$TMPDIR_COSTEA"' EXIT

# ── Historical tasks (compact for LLM, limit to 200 most recent) ──────────────
jq '[.tasks[-200:] [] | {
  id: (.session_id[:8] + "/" + (.timestamp | split("T")[1][:8])),
  source: .source,
  prompt: (.user_prompt[:200]),
  is_skill: .is_skill,
  skill: .skill_name,
  model: .model,
  tokens: .token_usage.total,
  input: .token_usage.input,
  output: .token_usage.output,
  cache_read: (.token_usage.cache_read // 0),
  cost_usd: (.cost.total | . * 10000 | round / 10000),
  tools: [(.tools // [])[] | "\(.name)x\(.count)"],
  tool_calls: .total_tool_calls,
  msgs: .assistant_message_count,
  reasoning_pct: (if .token_usage.total > 0 then (.reasoning.tokens / .token_usage.total * 100 | round) else 0 end)
}]' "$INDEX_FILE" > "$TMPDIR_COSTEA/history.json"

# ── Aggregate stats from task index (for LLM context) ─────────────────────────
jq '{
  task_count: .task_count,
  total_tokens: .total_tokens,
  avg_tokens_per_task: (if .task_count > 0 then (.total_tokens / .task_count | round) else 0 end),
  avg_cost_per_task: (if .task_count > 0 then ((.total_cost // 0) / .task_count | . * 10000 | round / 10000) else 0 end),
  models_used: ([.tasks[].model] | map(select(. != null)) | unique),
  top_tools: ([.tasks[] | (.tools // [])[] | .name] | group_by(.) | map({name: .[0], count: length}) | sort_by(-.count) | .[:10] | map("\(.name) x\(.count)")),
  sources: .sources,
  cache_stats: {
    tasks_with_cache: ([.tasks[] | select((.token_usage.cache_read // 0) > 0)] | length),
    avg_cache_read: (
      [.tasks[] | select(.token_usage.total > 0) | ((.token_usage.cache_read // 0) / .token_usage.total * 100)] |
      if length > 0 then (add / length | round) else 0 end
    )
  },
  token_distribution: {
    p25: ([.tasks[].token_usage.total] | sort | .[length / 4 | floor] // 0),
    p50: ([.tasks[].token_usage.total] | sort | .[length / 2 | floor] // 0),
    p75: ([.tasks[].token_usage.total] | sort | .[length * 3 / 4 | floor] // 0),
    p95: ([.tasks[].token_usage.total] | sort | .[length * 95 / 100 | floor] // 0),
    max: ([.tasks[].token_usage.total] | max // 0)
  },
  reasoning_stats: {
    avg_reasoning_pct: (
      [.tasks[] | select(.token_usage.total > 0) | (.reasoning.tokens / .token_usage.total * 100)] |
      if length > 0 then (add / length | round) else 0 end
    ),
    avg_tool_calls_per_task: (
      [.tasks[].total_tool_calls] |
      if length > 0 then (add / length | round) else 0 end
    )
  }
}' "$INDEX_FILE" > "$TMPDIR_COSTEA/agg.json"

# ── Session-level stats (if available) ────────────────────────────────────────
if [[ -f "$SESSION_INDEX" ]]; then
  jq '{
    session_count: .session_count,
    total_cost_usd: .total_cost_usd,
    avg_cost_per_session: (if .session_count > 0 then (.total_cost_usd / .session_count | . * 100 | round / 100) else 0 end),
    platforms: [.sources[] | "\(.source): \(.count)"]
  }' "$SESSION_INDEX" > "$TMPDIR_COSTEA/sess.json"
else
  echo 'null' > "$TMPDIR_COSTEA/sess.json"
fi

echo "$COSTEA_PROVIDERS" > "$TMPDIR_COSTEA/providers.json"

built_at=$(jq -r '.built_at' "$INDEX_FILE")

# ── Output ────────────────────────────────────────────────────────────────────
jq -n \
  --arg task "$TASK_DESC" \
  --argjson task_count "$task_count" \
  --slurpfile history "$TMPDIR_COSTEA/history.json" \
  --slurpfile providers "$TMPDIR_COSTEA/providers.json" \
  --slurpfile agg "$TMPDIR_COSTEA/agg.json" \
  --slurpfile sess "$TMPDIR_COSTEA/sess.json" \
  --arg built_at "$built_at" \
  '{
    task: $task,
    has_history: true,
    task_count: $task_count,
    index_built_at: $built_at,
    historical_tasks: $history[0],
    provider_prices: $providers[0],
    aggregate_stats: $agg[0],
    session_stats: $sess[0]
  }'
