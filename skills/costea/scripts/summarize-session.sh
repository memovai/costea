#!/usr/bin/env bash
set -euo pipefail

# Costea: Generate summary.json for one or all parsed sessions
#
# Usage:
#   summarize-session.sh <session_id>           # summarize one session
#   summarize-session.sh --all                  # summarize all sessions
#
# Reads:  ~/.costea/sessions/<id>/{session,llm-calls,tools,agents}.jsonl
# Writes: ~/.costea/sessions/<id>/summary.json
#
# summary.json is always re-generated from the raw JSONL; it is safe to
# delete and regenerate at any time.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
COSTEA_DIR="$HOME/.costea"
SESSIONS_DIR="$COSTEA_DIR/sessions"

source "$SCRIPT_DIR/lib/cost.sh"

if ! command -v jq &>/dev/null; then
  echo "jq is required. Install: brew install jq" >&2
  exit 1
fi

# ── Argument parsing ──────────────────────────────────────────────────────────
MODE="single"
SESSION_ID=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --all) MODE="all"; shift ;;
    -*)    echo "Unknown option: $1" >&2; exit 1 ;;
    *)     SESSION_ID="$1"; shift ;;
  esac
done

if [[ "$MODE" == "single" && -z "$SESSION_ID" ]]; then
  echo "Usage: $0 <session_id>  OR  $0 --all" >&2
  exit 1
fi

# ── Core summary logic ────────────────────────────────────────────────────────
_summarize_one() {
  local sid="$1"
  local dir="$SESSIONS_DIR/$sid"

  if [[ ! -d "$dir" ]]; then
    echo "  Session not found: $sid" >&2
    return 1
  fi

  echo "  Summarizing: $sid" >&2

  # ── Collect timestamps from session.jsonl ────────────────────────────────
  local started_at ended_at project_path source_platform
  # NDJSON: each line is a separate JSON object; use head/tail + jq on single lines
  started_at=$(head -1 "$dir/session.jsonl" 2>/dev/null | jq -r '.timestamp // "N/A"' 2>/dev/null || echo "N/A")
  ended_at=$(tail -1 "$dir/session.jsonl" 2>/dev/null | jq -r '.timestamp // "N/A"' 2>/dev/null || echo "N/A")
  project_path=$(head -1 "$dir/session.jsonl" 2>/dev/null | jq -r '.cwd // ""' 2>/dev/null || echo "")
  source_platform=$(head -1 "$dir/session.jsonl" 2>/dev/null | jq -r '.source // "claude-code"' 2>/dev/null || echo "claude-code")

  # Fallback to llm-calls.jsonl if session.jsonl is empty
  if [[ "$started_at" == "N/A" || -z "$started_at" ]]; then
    started_at=$(head -1 "$dir/llm-calls.jsonl" 2>/dev/null | jq -r '.timestamp // "N/A"' 2>/dev/null || echo "N/A")
    ended_at=$(tail -1 "$dir/llm-calls.jsonl" 2>/dev/null | jq -r '.timestamp // "N/A"' 2>/dev/null || echo "N/A")
  fi
  if [[ -z "$source_platform" || "$source_platform" == "claude-code" ]]; then
    # Double-check from llm-calls if session.jsonl was empty (0 lines)
    local _llm_source
    _llm_source=$(head -1 "$dir/llm-calls.jsonl" 2>/dev/null | jq -r '.source // ""' 2>/dev/null || echo "")
    if [[ -n "$_llm_source" ]]; then
      source_platform="$_llm_source"
    fi
  fi

  # ── Pre-slurp JSONL files into temp JSON arrays ──────────────────────────
  # Use temp files + --slurpfile instead of --argjson to avoid ARG_MAX
  # overflow on large sessions (macOS default ~262144 bytes).
  local _tmp_sessions _tmp_calls _tmp_tools _tmp_agents
  _tmp_sessions=$(mktemp) _tmp_calls=$(mktemp) _tmp_tools=$(mktemp) _tmp_agents=$(mktemp)
  # shellcheck disable=SC2064
  trap "rm -f '$_tmp_sessions' '$_tmp_calls' '$_tmp_tools' '$_tmp_agents'" RETURN

  jq -sc '.' "$dir/session.jsonl"   2>/dev/null > "$_tmp_sessions" || echo '[]' > "$_tmp_sessions"
  jq -sc '.' "$dir/llm-calls.jsonl" 2>/dev/null > "$_tmp_calls"    || echo '[]' > "$_tmp_calls"
  jq -sc '.' "$dir/tools.jsonl"     2>/dev/null > "$_tmp_tools"    || echo '[]' > "$_tmp_tools"
  jq -sc '.' "$dir/agents.jsonl"    2>/dev/null > "$_tmp_agents"   || echo '[]' > "$_tmp_agents"

  # ── Build summary in one jq pass ───────────────────────────────────────
  jq -n \
    --arg sid          "$sid"             \
    --arg source       "$source_platform" \
    --arg project_path "$project_path"    \
    --arg started_at   "$started_at"      \
    --arg ended_at     "$ended_at"        \
    --arg now          "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --slurpfile sessions_f "$_tmp_sessions" \
    --slurpfile calls_f    "$_tmp_calls"    \
    --slurpfile tools_f    "$_tmp_tools"    \
    --slurpfile agents_f   "$_tmp_agents"   \
    '
    # ── helpers ────────────────────────────────────────────────────────────
    def r6: . * 1000000 | round / 1000000;
    def safeadd: if length == 0 then 0 else add // 0 end;

    # --slurpfile wraps in an outer array; unwrap to get the actual arrays
    ($sessions_f | first // []) as $sessions |
    ($calls_f    | first // []) as $calls |
    ($tools_f    | first // []) as $tools |
    ($agents_f   | first // []) as $agents |

    # ── turn stats ─────────────────────────────────────────────────────────
    ($sessions | length) as $n_turns |

    # ── LLM call stats ────────────────────────────────────────────────────
    # Separate parent calls (agent_id == null) from subagent calls
    ($calls | map(select(.agent_id == null)))        as $parent_calls |
    ($calls | map(select(.agent_id != null)))        as $agent_calls |

    # Per-model aggregation (parent calls only for model breakdown)
    ($parent_calls
      | group_by(.model_short // "unknown")
      | map(
          (.[0].model_short // "unknown") as $m |
          {
            model:       $m,
            call_count:  length,
            input:       ([.[].usage.input_tokens               // 0] | safeadd),
            output:      ([.[].usage.output_tokens              // 0] | safeadd),
            cache_read:  ([.[].usage.cache_read_input_tokens    // 0] | safeadd),
            cache_write: ([.[].usage.cache_creation_input_tokens // 0] | safeadd),
            cost_usd:    ([.[].cost_usd // 0] | safeadd | r6)
          }
        )
    ) as $by_model |

    # Total tokens (parent only)
    ([$by_model[] | .input + .output + .cache_read + .cache_write] | safeadd) as $parent_tokens |
    ([$by_model[].cost_usd] | safeadd | r6) as $parent_cost |

    # Subagent totals
    ($agents | map(select(.event_type == "stop"))) as $agent_stops |
    ([$agent_stops[].final_token_usage.total // 0] | safeadd) as $agent_tokens |
    ([$agent_stops[].final_cost_usd // 0] | safeadd | r6) as $agent_cost |

    # ── skill stats ────────────────────────────────────────────────────────
    ($sessions
      | group_by(if .is_skill then (.skill_name // "unknown") else "(conversation)" end)
      | map(
          (.[0] | if .is_skill then (.skill_name // "unknown") else "(conversation)" end) as $cat |
          {
            skill:      $cat,
            turns:      length,
            tokens:     ([.[].token_usage.total // 0] | safeadd),
            cost_usd:   ([.[].cost.total_usd    // 0] | safeadd | r6),
            avg_tokens: ([.[].token_usage.total // 0] | safeadd / (length | if . == 0 then 1 else . end) | round)
          }
        )
      | sort_by(-.tokens)
    ) as $by_skill |

    # ── tool stats ─────────────────────────────────────────────────────────
    ($tools
      | group_by(.tool_name)
      | map({ tool: .[0].tool_name, calls: length, category: .[0].tool_category })
      | sort_by(-.calls)
      | .[:20]
    ) as $top_tools |

    # ── reasoning vs tool-invocation ──────────────────────────────────────
    ([$sessions[].reasoning.message_count        // 0] | safeadd) as $r_msgs |
    ([$sessions[].reasoning.tokens               // 0] | safeadd) as $r_tok  |
    ([$sessions[].tool_invocation.message_count  // 0] | safeadd) as $ti_msgs |
    ([$sessions[].tool_invocation.tokens         // 0] | safeadd) as $ti_tok  |

    # ── top expensive turns ────────────────────────────────────────────────
    ($sessions
      | sort_by(-(.token_usage.total // 0))
      | .[:10]
      | map({
          turn_id:   .turn_id,
          prompt:    (.user_prompt[:120]),
          is_skill:  .is_skill,
          skill:     .skill_name,
          tokens:    (.token_usage.total // 0),
          cost_usd:  (.cost.total_usd   // 0 | r6),
          tool_calls: .tools_summary.total_calls,
          timestamp: .timestamp
        })
    ) as $top_turns |

    # ── final summary ──────────────────────────────────────────────────────
    {
      session_id:   $sid,
      source:       $source,
      project_path: $project_path,
      started_at:   $started_at,
      ended_at:     $ended_at,

      turn_count:      $n_turns,
      llm_call_count:  ($calls | length),
      tool_call_count: ($tools | length),

      token_usage: {
        input:          ([$by_model[].input]       | safeadd),
        output:         ([$by_model[].output]      | safeadd),
        cache_read:     ([$by_model[].cache_read]  | safeadd),
        cache_write:    ([$by_model[].cache_write] | safeadd),
        total:          $parent_tokens,
        subagent_total: $agent_tokens,
        grand_total:    ($parent_tokens + $agent_tokens)
      },

      cost: {
        total_usd:          ($parent_cost + $agent_cost | r6),
        parent_usd:         ($parent_cost | r6),
        subagent_usd:       ($agent_cost  | r6),
        by_model: ($by_model | map({key: .model, value: .cost_usd}) | from_entries)
      },

      by_model: $by_model,
      by_skill:  $by_skill,
      top_tools: $top_tools,

      reasoning_vs_tools: {
        reasoning_turns:      $r_msgs,
        reasoning_tokens:     $r_tok,
        tool_inv_turns:       $ti_msgs,
        tool_inv_tokens:      $ti_tok,
        reasoning_pct: (
          if ($r_tok + $ti_tok) > 0
          then ($r_tok / ($r_tok + $ti_tok) * 100 | round)
          else 0 end
        )
      },

      subagents: {
        count:         ($agent_stops | length),
        total_tokens:  $agent_tokens,
        total_cost_usd: ($agent_cost | r6),
        agents: [
          $agent_stops[] | {
            agent_id:       .agent_id,
            tokens:         (.final_token_usage.total  // 0),
            cost_usd:       (.final_cost_usd           // 0),
            llm_call_count: (.llm_call_count           // 0)
          }
        ]
      },

      top_turns_by_cost: $top_turns,
      generated_at: $now,
      version: "1.0"
    }
    ' > "$dir/summary.json"

  echo "  Written → $dir/summary.json" >&2
}

# ── Dispatch ──────────────────────────────────────────────────────────────────
if [[ "$MODE" == "all" ]]; then
  if [[ ! -d "$SESSIONS_DIR" ]]; then
    echo "No sessions directory found at $SESSIONS_DIR" >&2
    exit 0
  fi
  while IFS= read -r dir; do
    sid=$(basename "$dir")
    _summarize_one "$sid" || true
  done < <(find "$SESSIONS_DIR" -maxdepth 1 -mindepth 1 -type d | sort)
else
  _summarize_one "$SESSION_ID"
fi
