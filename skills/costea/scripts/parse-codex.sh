#!/usr/bin/env bash
set -euo pipefail

# Costea: Parse a single Codex CLI rollout JSONL into structured records
#
# Usage:
#   parse-codex.sh [--file] <rollout-*.jsonl> [--force]
#
# Output directory: ~/.costea/sessions/<session_id>/
#   session.jsonl   — one record per conversation turn (user message)
#   llm-calls.jsonl — one record per turn with cumulative-delta token usage
#   tools.jsonl     — one record per function_call invocation
#   agents.jsonl    — empty (Codex has no subagent concept)
#
# Token accounting:
#   Codex token_count events carry cumulative total_token_usage.
#   Per-turn delta = (this turn's last cumulative) − (prev turn's last cumulative).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
COSTEA_DIR="$HOME/.costea"
SESSIONS_DIR="$COSTEA_DIR/sessions"

source "$SCRIPT_DIR/lib/cost.sh"

# ── Arguments ────────────────────────────────────────────────────────────────
FILE="" FORCE=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --file|-f) FILE="$2"; shift 2 ;;
    --force)   FORCE=true; shift ;;
    -*)        echo "Unknown option: $1" >&2; exit 1 ;;
    *)         [[ -z "$FILE" ]] && FILE="$1" || true; shift ;;
  esac
done

[[ -z "$FILE" ]] && { echo "Usage: $0 [--file] <rollout.jsonl> [--force]" >&2; exit 1; }
[[ ! -f "$FILE" ]] && { echo "File not found: $FILE" >&2; exit 1; }
command -v jq &>/dev/null || { echo "jq is required" >&2; exit 1; }

# ── Session ID ────────────────────────────────────────────────────────────────
SESSION_ID=$(jq -r 'select(.type == "session_meta") | .payload.id // empty' "$FILE" 2>/dev/null | head -1)
if [[ -z "$SESSION_ID" ]]; then
  BASENAME=$(basename "$FILE" .jsonl)
  SESSION_ID="codex-${BASENAME##*-}"
fi

# ── Skip if up-to-date ────────────────────────────────────────────────────────
SESSION_DIR="$SESSIONS_DIR/$SESSION_ID"
if [[ "$FORCE" == false && -f "$SESSION_DIR/llm-calls.jsonl" ]]; then
  if [[ "$FILE" -ot "$SESSION_DIR/llm-calls.jsonl" ]]; then
    exit 0
  fi
fi

mkdir -p "$SESSION_DIR"
echo "  Parsing codex: $SESSION_ID" >&2

# ── Truncate output files ─────────────────────────────────────────────────────
: > "$SESSION_DIR/session.jsonl"
: > "$SESSION_DIR/llm-calls.jsonl"
: > "$SESSION_DIR/tools.jsonl"
: > "$SESSION_DIR/agents.jsonl"

# ── Parse ─────────────────────────────────────────────────────────────────────
TMPFILE=$(mktemp /tmp/costea_codex.XXXXXX)
trap "rm -f '$TMPFILE'" EXIT

jq -sc \
  --arg sid "$SESSION_ID" \
  --argjson prices "$COSTEA_PRICES" \
'
def normalize_model:
  if . == null then "unknown"
  else ascii_downcase |
    if   test("gpt-5\\.4")     then "gpt-5.4"
    elif test("5[-.]3|5[-.]2") then "gpt-5.2-codex"
    elif test("5[-.]1|codex")  then "gpt-5.2-codex"
    elif test("gpt")           then "gpt-5.4"
    else "gpt-5.2-codex" end
  end;

def mcost(m; i; o):
  (m | normalize_model) as $s |
  ($prices[$s] // $prices["gpt-5.2-codex"]) as $p |
  (i * $p.input + o * $p.output) / 1000000;

def r6: . * 1000000 | round / 1000000;

# ── metadata ──────────────────────────────────────────────────────────────────
([.[] | select(.type == "turn_context") | .payload.model] | .[0] // "gpt-5.2-codex") as $model_raw |
($model_raw | normalize_model) as $model_short |

# ── group into turns ──────────────────────────────────────────────────────────
(reduce .[] as $rec (
  {turns: [], cur: null, idx: 0};
  if ($rec.type == "event_msg" and $rec.payload.type == "user_message") then
    (if .cur then .turns + [.cur] else .turns end) as $t |
    {turns: $t, idx: (.idx + 1),
     cur: {idx: .idx, ts: ($rec.timestamp // ""),
           prompt: ($rec.payload.message // ""),
           tcs: [], fcs: []}}
  elif .cur != null then
    if ($rec.type == "event_msg" and $rec.payload.type == "token_count" and $rec.payload.info != null) then
      .cur.tcs += [$rec.payload.info] | .
    elif ($rec.type == "response_item" and $rec.payload.type == "function_call") then
      .cur.fcs += [$rec.payload] | .
    else . end
  else . end
) | (if .cur then .turns + [.cur] else .turns end)) as $turns |

# ── emit records with running cumulative state ────────────────────────────────
# Use foreach to track previous cumulative and emit per turn
[foreach $turns[] as $t (
  # state: previous cumulative totals
  {pi: 0, po: 0, pc: 0, pr: 0, pt: 0};

  # last token_count in this turn
  ($t.tcs | if length > 0 then .[-1].total_token_usage else null end) as $cum |
  ($cum // {input_tokens: .pi, output_tokens: .po, cached_input_tokens: .pc,
            reasoning_output_tokens: .pr, total_tokens: .pt}) as $c |

  # delta
  {
    di: (($c.input_tokens // 0) - .pi),
    do: (($c.output_tokens // 0) - .po),
    dc: (($c.cached_input_tokens // 0) - .pc),
    dr: (($c.reasoning_output_tokens // 0) - .pr),
    dt: (($c.total_tokens // 0) - .pt),
    # update state for next iteration
    pi: ($c.input_tokens // 0),
    po: ($c.output_tokens // 0),
    pc: ($c.cached_input_tokens // 0),
    pr: ($c.reasoning_output_tokens // 0),
    pt: ($c.total_tokens // 0),
    ctx: ($t.tcs | if length > 0 then .[-1].model_context_window else 258400 end),
    turn: $t
  };

  # emit: build records from current state
  . as $s | $s.turn as $t |

  ($t.ts | gsub("[^0-9T:-]"; "") | .[0:19]) as $tss |
  ($sid[:8] + "_" + $tss + "_" + ($t.idx | tostring)) as $tid |

  ($t.fcs | map(.name // "unknown") |
    group_by(.) | map({key: .[0], value: length}) | from_entries) as $toolmap |
  ($t.fcs | length) as $ntool |

  (mcost($model_raw; $s.di; $s.do) | r6) as $cost |

  [
    # session_turn
    { __type__: "session_turn",
      record_type: "session_turn",
      turn_id: $tid, session_id: $sid,
      parent_session_id: null, agent_id: null,
      source: "codex", timestamp: $t.ts,
      user_prompt: ($t.prompt[:500]),
      is_skill: false, skill_name: null,
      token_usage: {input: $s.di, output: $s.do, cache_read: $s.dc, cache_write: 0, total: $s.dt},
      cost: {total_usd: $cost, by_model: {($model_short): $cost}},
      tools_summary: {total_calls: $ntool, by_tool: $toolmap},
      reasoning: {message_count: (if $s.dr > 0 then 1 else 0 end), tokens: $s.dr},
      tool_invocation: {message_count: $ntool, tokens: 0},
      llm_call_count: 1, version: "1.0" },

    # llm_call
    { __type__: "llm_call",
      record_type: "llm_call",
      call_id: ("codex_" + $sid[:8] + "_" + ($t.idx | tostring)),
      session_id: $sid, parent_session_id: null, agent_id: null,
      turn_id: $tid, source: "codex", timestamp: $t.ts,
      model: $model_raw, model_short: $model_short,
      usage: {input_tokens: $s.di, output_tokens: $s.do,
              cache_read_input_tokens: $s.dc, cache_creation_input_tokens: 0,
              web_search_requests: 0},
      cost_usd: $cost,
      context_window: {used: $s.dt, model_max: ($s.ctx // 258400)},
      stop_reason: "end_turn",
      is_reasoning_turn: ($s.dr > 0),
      has_thinking: ($s.dr > 0),
      tool_calls: [$t.fcs[] | {tool_name: (.name // "unknown"), tool_use_id: (.call_id // "unknown")}],
      dedup_siblings: 0, version: "1.0" }
  ]
  + [$t.fcs[] | {
      __type__: "tool_call",
      record_type: "tool_call",
      tool_use_id: (.call_id // "unknown"),
      session_id: $sid, agent_id: null, turn_id: $tid,
      tool_name: (.name // "unknown"),
      tool_category: ((.name // "") | ascii_downcase |
        if test("exec_command|shell|bash") then "shell"
        elif test("read|write|edit|patch|apply") then "filesystem"
        elif test("grep|search|find|rg") then "search"
        else "other" end),
      outcome: "success", version: "1.0" }]

)] | flatten | .[]
' "$FILE" > "$TMPFILE" 2>/dev/null || true

# ── Route to output files ─────────────────────────────────────────────────────
jq -c 'select(.__type__ == "session_turn") | del(.__type__)' "$TMPFILE" > "$SESSION_DIR/session.jsonl" 2>/dev/null || true
jq -c 'select(.__type__ == "llm_call")    | del(.__type__)' "$TMPFILE" > "$SESSION_DIR/llm-calls.jsonl" 2>/dev/null || true
jq -c 'select(.__type__ == "tool_call")   | del(.__type__)' "$TMPFILE" > "$SESSION_DIR/tools.jsonl" 2>/dev/null || true

echo "  Done → $SESSION_DIR" >&2
