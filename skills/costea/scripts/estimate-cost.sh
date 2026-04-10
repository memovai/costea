#!/usr/bin/env bash
set -euo pipefail

# Costea: Estimate cost for a new task using historical task index
# Output: JSON with historical data, aggregate stats, provider prices, recent P90 fallback

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
COSTEA_DIR="$HOME/.costea"
INDEX_FILE="$COSTEA_DIR/task-index.json"
SESSION_INDEX="$COSTEA_DIR/index.json"

source "$SCRIPT_DIR/lib/cost.sh"

TASK_DESC="${1:-}"

[[ -z "$TASK_DESC" ]] && { echo '{"error": "No task description provided"}'; exit 1; }
command -v jq &>/dev/null || { echo '{"error": "jq is required"}'; exit 1; }

# Rebuild index if missing or stale (older than 1 hour)
if [[ ! -f "$INDEX_FILE" ]] || [[ $(find "$INDEX_FILE" -mmin +60 2>/dev/null) ]]; then
  bash "$SCRIPT_DIR/build-index.sh" >/dev/null 2>&1 || true
fi

if [[ ! -f "$INDEX_FILE" ]]; then
  jq -n --arg task "$TASK_DESC" --argjson providers "$COSTEA_PROVIDERS" \
    '{task:$task, has_history:false, task_count:0, provider_prices:$providers, session_stats:null}'
  exit 0
fi

task_count=$(jq '.task_count // 0' "$INDEX_FILE")
if [[ "$task_count" -eq 0 ]]; then
  jq -n --arg task "$TASK_DESC" --argjson providers "$COSTEA_PROVIDERS" \
    '{task:$task, has_history:false, task_count:0, provider_prices:$providers, session_stats:null}'
  exit 0
fi

# ── All intermediate results go to temp files to avoid ARG_MAX ────────────────
TMP=$(mktemp -d /tmp/costea_est.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

# Historical tasks (limit to 200 most recent)
jq '[.tasks[-200:][] | {
  id: (.session_id[:8] + "/" + (.timestamp | split("T")[1][:8])),
  source, prompt: (.user_prompt[:200]), is_skill, skill: .skill_name, model,
  tokens: .token_usage.total, input: .token_usage.input, output: .token_usage.output,
  cache_read: (.token_usage.cache_read // 0),
  cost_usd: (.cost.total | . * 10000 | round / 10000),
  tools: [(.tools // [])[] | "\(.name)x\(.count)"],
  tool_calls: .total_tool_calls, msgs: .assistant_message_count,
  reasoning_pct: (if .token_usage.total > 0 then (.reasoning.tokens / .token_usage.total * 100 | round) else 0 end)
}]' "$INDEX_FILE" > "$TMP/history.json"

# Aggregate stats (single-pass reduce)
jq '
  (.tasks | map(.token_usage.total) | sort) as $sorted |
  (.tasks | length) as $n |
  (reduce .tasks[] as $t (
    {st:0, sc:0, scr:0, sct:0, sr:0, srt:0, stl:0, nwt:0, nwc:0, models:{}, tools:{}};
    .st += $t.token_usage.total | .sc += ($t.cost.total // 0) | .stl += $t.total_tool_calls |
    (if $t.token_usage.total > 0 then .nwt += 1 | .scr += ($t.token_usage.cache_read // 0) |
      .sct += $t.token_usage.total | .sr += ($t.reasoning.tokens // 0) | .srt += $t.token_usage.total
    else . end) |
    (if ($t.token_usage.cache_read // 0) > 0 then .nwc += 1 else . end) |
    .models[($t.model // "unknown")] = true |
    (reduce (($t.tools // [])[] | .name) as $tn (.; .tools[$tn] = ((.tools[$tn] // 0) + 1)))
  )) as $a |
  {
    task_count: $n, total_tokens: $a.st,
    avg_tokens_per_task: (if $n>0 then ($a.st/$n|round) else 0 end),
    avg_cost_per_task: (if $n>0 then ($a.sc/$n|.*10000|round/10000) else 0 end),
    models_used: ($a.models|keys), sources: .sources,
    top_tools: ($a.tools|to_entries|sort_by(-.value)|.[:10]|map("\(.key) x\(.value)")),
    cache_stats: {tasks_with_cache: $a.nwc, avg_cache_read: (if $a.nwt>0 then ($a.scr/$a.sct*100|round) else 0 end)},
    token_distribution: {
      p25:($sorted[($n/4|floor)]//0), p50:($sorted[($n/2|floor)]//0),
      p75:($sorted[($n*3/4|floor)]//0), p90:($sorted[($n*9/10|floor)]//0),
      p95:($sorted[($n*95/100|floor)]//0), max:($sorted[-1]//0)
    },
    reasoning_stats: {
      avg_reasoning_pct: (if $a.srt>0 then ($a.sr/$a.srt*100|round) else 0 end),
      avg_tool_calls_per_task: (if $n>0 then ($a.stl/$n|round) else 0 end)
    }
  }
' "$INDEX_FILE" > "$TMP/agg.json"

# Session-level stats
if [[ -f "$SESSION_INDEX" ]]; then
  jq '{session_count, total_cost_usd,
    avg_cost_per_session: (if .session_count>0 then (.total_cost_usd/.session_count|.*100|round/100) else 0 end),
    platforms: [.sources[]|"\(.source): \(.count)"]}' "$SESSION_INDEX" > "$TMP/sess.json"
else
  echo 'null' > "$TMP/sess.json"
fi

# Recent P90 fallback (last 30 days)
CUTOFF=$(date -u -v-30d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '30 days ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo '2000-01-01')
jq --arg cutoff "$CUTOFF" '[.tasks[]|select(.token_usage.total>0 and (.timestamp//"")>=$cutoff)]' "$INDEX_FILE" > "$TMP/recent_tasks.json"
jq '
  length as $n |
  if $n >= 5 then
    def pct(arr;p): arr|sort|.[(length*p|floor)];
    {has_recent_data:true, recent_days:30, recent_task_count:$n,
     p50:{input:pct(map(.token_usage.input);0.5), output:pct(map(.token_usage.output);0.5), total:pct(map(.token_usage.total);0.5)},
     p90:{input:pct(map(.token_usage.input);0.9), output:pct(map(.token_usage.output);0.9),
          cache_read:pct(map(.token_usage.cache_read//0);0.9), tools:pct(map(.total_tool_calls);0.9), total:pct(map(.token_usage.total);0.9)}}
  else {has_recent_data:false, recent_days:30, recent_task_count:$n} end
' "$TMP/recent_tasks.json" > "$TMP/recent.json"

echo "$COSTEA_PROVIDERS" > "$TMP/providers.json"
built_at=$(jq -r '.built_at' "$INDEX_FILE")

# ── Final output via --slurpfile (no ARG_MAX risk) ────────────────────────────
jq -n \
  --arg task "$TASK_DESC" \
  --argjson task_count "$task_count" \
  --arg built_at "$built_at" \
  --slurpfile history  "$TMP/history.json" \
  --slurpfile providers "$TMP/providers.json" \
  --slurpfile agg      "$TMP/agg.json" \
  --slurpfile sess     "$TMP/sess.json" \
  --slurpfile recent   "$TMP/recent.json" \
  '{
    task: $task, has_history: true, task_count: $task_count, index_built_at: $built_at,
    historical_tasks: $history[0], provider_prices: $providers[0],
    aggregate_stats: $agg[0], session_stats: $sess[0], recent_fallback: $recent[0]
  }'
