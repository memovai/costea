#!/usr/bin/env bash
set -euo pipefail

# Costea: Estimate cost for a new task using historical task index
# Uses the task index built by build-index.sh
# Output: JSON with estimate data for the SKILL.md to present

COSTEA_DIR="$HOME/.costea"
INDEX_FILE="$COSTEA_DIR/task-index.json"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

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
  jq -n --arg task "$TASK_DESC" '{
    task: $task,
    has_history: false,
    task_count: 0,
    history_summary: "No historical task data available."
  }'
  exit 0
fi

task_count=$(jq '.task_count // 0' "$INDEX_FILE")

if [[ "$task_count" -eq 0 ]]; then
  jq -n --arg task "$TASK_DESC" '{
    task: $task,
    has_history: false,
    task_count: 0,
    history_summary: "No historical task data available."
  }'
  exit 0
fi

# Build a compact summary of historical tasks for LLM consumption
# Include: prompt, skill info, token usage, cost, tools used
history_summary=$(jq '[.tasks[] | {
  id: (.session_id[:8] + "/" + (.timestamp | split("T")[1][:8])),
  source: .source,
  prompt: (.user_prompt[:200]),
  is_skill: .is_skill,
  skill: .skill_name,
  model: .model,
  tokens: .token_usage.total,
  input: .token_usage.input,
  output: .token_usage.output,
  cache_read: .token_usage.cache_read,
  cost_usd: (.cost.total | . * 10000 | round / 10000),
  tools: [.tools[] | "\(.name)x\(.count)"],
  tool_calls: .total_tool_calls,
  msgs: .assistant_message_count,
  reasoning_pct: (if .token_usage.total > 0 then (.reasoning.tokens / .token_usage.total * 100 | round) else 0 end)
}]' "$INDEX_FILE")

# Output everything the LLM needs to make its estimate
jq -n \
  --arg task "$TASK_DESC" \
  --argjson task_count "$task_count" \
  --argjson history "$history_summary" \
  --arg built_at "$(jq -r '.built_at' "$INDEX_FILE")" \
  '{
    task: $task,
    has_history: true,
    task_count: $task_count,
    index_built_at: $built_at,
    historical_tasks: $history
  }'
