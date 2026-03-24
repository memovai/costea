#!/usr/bin/env bash
set -euo pipefail

# Costeamigo: Generate multi-dimensional summary from task index
# Reads ~/.costea/task-index.json (built by build-index.sh)
# Supports: OpenClaw, Claude Code, Codex CLI
# Outputs structured JSON for LLM to format into a human-readable report

COSTEA_DIR="$HOME/.costea"
INDEX_FILE="$COSTEA_DIR/task-index.json"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_INDEX="$SCRIPT_DIR/../../costea/scripts/build-index.sh"

# Parse arguments
SOURCE_FILTER="all"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --source) SOURCE_FILTER="$2"; shift 2 ;;
    *) shift ;;
  esac
done

if ! command -v jq &>/dev/null; then
  echo '{"error": "jq is required. Install with: brew install jq"}' >&2
  exit 1
fi

# Rebuild index first (scans all three sources)
if [[ -f "$BUILD_INDEX" ]]; then
  bash "$BUILD_INDEX" 2>/dev/null || true
fi

if [[ ! -f "$INDEX_FILE" ]]; then
  echo '{"error": "No task index found. No session data available from any source."}'
  exit 0
fi

task_count=$(jq '.task_count // 0' "$INDEX_FILE")
if [[ "$task_count" -eq 0 ]]; then
  echo '{"overview": {"total_tasks": 0, "total_tokens": 0, "total_cost": 0}, "empty": true}'
  exit 0
fi

# Apply source filter: pre-filter tasks before aggregation
FILTER_EXPR="."
if [[ "$SOURCE_FILTER" != "all" ]]; then
  FILTER_EXPR='.tasks |= [.[] | select(.source == "'"$SOURCE_FILTER"'")] | .task_count = (.tasks | length) | .total_tokens = ([.tasks[].token_usage.total] | add // 0) | .total_cost = ([.tasks[].cost.total] | add // 0)'
fi

# Generate the full multi-dimensional report in one jq pass
jq "$FILTER_EXPR" "$INDEX_FILE" | jq --arg source_filter "$SOURCE_FILTER" '{
  filter: $source_filter,
  overview: {
    total_tasks: .task_count,
    total_tokens: .total_tokens,
    total_cost: (.total_cost | . * 10000 | round / 10000),
    sessions_scanned: .sessions_scanned,
    index_built_at: .built_at,
    sources: .sources,
    time_range: {
      earliest: (.tasks | map(.timestamp // "") | map(select(. != "")) | sort | first // "N/A"),
      latest: (.tasks | map(.timestamp // "") | map(select(. != "")) | sort | last // "N/A")
    }
  },

  by_source: (
    [.tasks[] | {source, t: .}] |
    group_by(.source) |
    map({
      source: .[0].source,
      tasks: length,
      tokens: (map(.t.token_usage.total) | add),
      input: (map(.t.token_usage.input) | add),
      output: (map(.t.token_usage.output) | add),
      cache_read: (map(.t.token_usage.cache_read) | add),
      cost: (map(.t.cost.total) | add | . * 10000 | round / 10000),
      models: ([map(.t.model) | .[] | select(. != null)] | unique),
      tool_calls: (map(.t.total_tool_calls) | add)
    }) | sort_by(-.tokens)
  ),

  by_skill: (
    [.tasks[] | { cat: (if .is_skill then (.skill_name // "unknown-skill") else "(conversation)" end), t: . }] |
    group_by(.cat) |
    map({
      skill: .[0].cat,
      tasks: length,
      tokens: (map(.t.token_usage.total) | add),
      cost: (map(.t.cost.total) | add | . * 10000 | round / 10000),
      avg_tokens: (map(.t.token_usage.total) | add / length | round),
      tool_calls: (map(.t.total_tool_calls) | add)
    }) | sort_by(-.tokens)
  ),

  by_model: (
    [.tasks[] | {model: (.model // "unknown"), t: .}] |
    group_by(.model) |
    map({
      model: .[0].model,
      tasks: length,
      tokens: (map(.t.token_usage.total) | add),
      input: (map(.t.token_usage.input) | add),
      output: (map(.t.token_usage.output) | add),
      cache_read: (map(.t.token_usage.cache_read) | add),
      cost: (map(.t.cost.total) | add | . * 10000 | round / 10000),
      avg_tokens_per_task: (map(.t.token_usage.total) | add / length | round)
    }) | sort_by(-.tokens)
  ),

  by_tool: (
    [.tasks[] | .tools[]? | {name, count}] |
    group_by(.name) |
    map({
      tool: .[0].name,
      total_calls: (map(.count) | add),
      used_in_tasks: length
    }) | sort_by(-.total_calls)
  ),

  reasoning_vs_tools: {
    reasoning_tokens: ([.tasks[].reasoning.tokens] | add // 0),
    reasoning_msgs: ([.tasks[].reasoning.count] | add // 0),
    tool_inv_tokens: ([.tasks[].tool_invocation.tokens] | add // 0),
    tool_inv_msgs: ([.tasks[].tool_invocation.count] | add // 0),
    reasoning_pct: (
      ([.tasks[].reasoning.tokens] | add // 0) as $r |
      ([.tasks[].tool_invocation.tokens] | add // 0) as $t |
      if ($r + $t) > 0 then ($r / ($r + $t) * 100 | round) else 0 end
    )
  },

  top_tasks_by_tokens: (
    [.tasks | sort_by(-.token_usage.total) | .[:10][] | {
      prompt: (.user_prompt[:120]),
      source: .source,
      is_skill: .is_skill,
      skill: .skill_name,
      model: .model,
      tokens: .token_usage.total,
      cost: (.cost.total | . * 10000 | round / 10000),
      tools: [.tools[]? | "\(.name)x\(.count)"],
      tool_calls: .total_tool_calls,
      reasoning_pct: (if .token_usage.total > 0 then (.reasoning.tokens / .token_usage.total * 100 | round) else 0 end),
      timestamp: .timestamp
    }]
  ),

  all_tasks: (
    [.tasks[] | {
      prompt: (.user_prompt[:200]),
      source: .source,
      is_skill: .is_skill,
      skill: .skill_name,
      model: .model,
      tokens: .token_usage.total,
      input: .token_usage.input,
      output: .token_usage.output,
      cache_read: .token_usage.cache_read,
      cost: (.cost.total | . * 10000 | round / 10000),
      tools: [.tools[]? | "\(.name)x\(.count)"],
      tool_calls: .total_tool_calls,
      reasoning_pct: (if .token_usage.total > 0 then (.reasoning.tokens / .token_usage.total * 100 | round) else 0 end),
      timestamp: .timestamp,
      session_id: .session_id
    }]
  )
}'
