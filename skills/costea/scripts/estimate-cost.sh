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

# ── Aggregate stats (single-pass reduce to limit memory) ─────────────────────
# Instead of expanding .tasks[] multiple times (O(N) per metric), we do a
# single reduce pass collecting all counters, then compute percentiles from
# a pre-sorted total-tokens array.
jq '
  # Pre-sort token totals once for percentile lookups
  (.tasks | map(.token_usage.total) | sort) as $sorted_totals |
  (.tasks | length) as $n |

  # Single reduce pass for sums and counters
  (reduce .tasks[] as $t (
    {sum_tokens:0, sum_cost:0, sum_cache:0, sum_cache_total:0,
     sum_reasoning:0, sum_reasoning_total:0, sum_tools:0,
     n_with_cache:0, n_with_total:0,
     models:{}, tools:{}};

    .sum_tokens += $t.token_usage.total |
    .sum_cost   += ($t.cost.total // 0) |
    .sum_tools  += $t.total_tool_calls |

    (if $t.token_usage.total > 0 then
      .n_with_total += 1 |
      .sum_cache       += ($t.token_usage.cache_read // 0) |
      .sum_cache_total += $t.token_usage.total |
      .sum_reasoning   += ($t.reasoning.tokens // 0) |
      .sum_reasoning_total += $t.token_usage.total
    else . end) |

    (if ($t.token_usage.cache_read // 0) > 0 then .n_with_cache += 1 else . end) |
    .models[($t.model // "unknown")] = true |
    (reduce (($t.tools // [])[] | .name) as $tn (.; .tools[$tn] = ((.tools[$tn] // 0) + 1)))
  )) as $agg |

  {
    task_count: $n,
    total_tokens: $agg.sum_tokens,
    avg_tokens_per_task: (if $n > 0 then ($agg.sum_tokens / $n | round) else 0 end),
    avg_cost_per_task: (if $n > 0 then ($agg.sum_cost / $n | . * 10000 | round / 10000) else 0 end),
    models_used: ($agg.models | keys),
    top_tools: ($agg.tools | to_entries | sort_by(-.value) | .[:10] | map("\(.key) x\(.value)")),
    sources: .sources,
    cache_stats: {
      tasks_with_cache: $agg.n_with_cache,
      avg_cache_read: (if $agg.n_with_total > 0 then ($agg.sum_cache / $agg.sum_cache_total * 100 | round) else 0 end)
    },
    token_distribution: {
      p25: ($sorted_totals[($n / 4 | floor)] // 0),
      p50: ($sorted_totals[($n / 2 | floor)] // 0),
      p75: ($sorted_totals[($n * 3 / 4 | floor)] // 0),
      p90: ($sorted_totals[($n * 9 / 10 | floor)] // 0),
      p95: ($sorted_totals[($n * 95 / 100 | floor)] // 0),
      max: ($sorted_totals[-1] // 0)
    },
    reasoning_stats: {
      avg_reasoning_pct: (if $agg.sum_reasoning_total > 0 then ($agg.sum_reasoning / $agg.sum_reasoning_total * 100 | round) else 0 end),
      avg_tool_calls_per_task: (if $n > 0 then ($agg.sum_tools / $n | round) else 0 end)
    }
  }
' "$INDEX_FILE" > "$TMPDIR_COSTEA/agg.json"

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

# ── Recent P90 fallback (last 30 days) ───────────────────────────────────────
# Pre-filter recent tasks into a temp file, then compute percentiles on
# the smaller set to avoid loading the full index twice.
CUTOFF=$(date -u -v-30d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '30 days ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo '2000-01-01')
jq --arg cutoff "$CUTOFF" '
  [.tasks[] | select(.token_usage.total > 0 and (.timestamp // "") >= $cutoff)]
' "$INDEX_FILE" > "$TMPDIR_COSTEA/recent_tasks.json"

jq '
  length as $n |
  if $n >= 5 then
    def pct(arr; p): arr | sort | .[(length * p | floor)];
    {
      has_recent_data: true, recent_days: 30, recent_task_count: $n,
      p50: {
        input:  pct(map(.token_usage.input); 0.5),
        output: pct(map(.token_usage.output); 0.5),
        total:  pct(map(.token_usage.total); 0.5)
      },
      p90: {
        input:      pct(map(.token_usage.input); 0.9),
        output:     pct(map(.token_usage.output); 0.9),
        cache_read: pct(map(.token_usage.cache_read // 0); 0.9),
        tools:      pct(map(.total_tool_calls); 0.9),
        total:      pct(map(.token_usage.total); 0.9)
      }
    }
  else
    {has_recent_data: false, recent_days: 30, recent_task_count: $n}
  end
' "$TMPDIR_COSTEA/recent_tasks.json" > "$TMPDIR_COSTEA/recent.json"

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
  --slurpfile recent "$TMPDIR_COSTEA/recent.json" \
  --arg built_at "$built_at" \
  '{
    task: $task,
    has_history: true,
    task_count: $task_count,
    index_built_at: $built_at,
    historical_tasks: $history[0],
    provider_prices: $providers[0],
    aggregate_stats: $agg[0],
    session_stats: $sess[0],
    recent_fallback: $recent[0]
  }'
