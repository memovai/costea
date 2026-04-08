#!/usr/bin/env bash
set -euo pipefail

# Costea: Parse a single OpenClaw session JSONL into structured records
#
# Usage:
#   parse-openclaw.sh [--file] <session.jsonl> --sid <session_id> [--force]
#
# OpenClaw JSONL format:
#   type=session       → session metadata
#   type=message       → message.role: user | assistant | toolResult
#     assistant msgs   → message.usage.{input, output, cacheRead, cacheWrite, totalTokens, cost}
#                      → message.content[].type: text | toolCall
#                      → message.model, message.provider, message.stopReason
#   type=model_change  → model switch mid-session
#
# Token accounting:
#   OpenClaw provides per-message usage with cost — no dedup or delta needed.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
COSTEA_DIR="$HOME/.costea"
SESSIONS_DIR="$COSTEA_DIR/sessions"

source "$SCRIPT_DIR/lib/cost.sh"

# ── Arguments ────────────────────────────────────────────────────────────────
FILE="" FORCE=false SESSION_ID=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --file|-f) FILE="$2"; shift 2 ;;
    --sid)     SESSION_ID="$2"; shift 2 ;;
    --force)   FORCE=true; shift ;;
    -*)        echo "Unknown option: $1" >&2; exit 1 ;;
    *)         [[ -z "$FILE" ]] && FILE="$1" || true; shift ;;
  esac
done

[[ -z "$FILE" ]] && { echo "Usage: $0 [--file] <session.jsonl> --sid <id> [--force]" >&2; exit 1; }
[[ ! -f "$FILE" ]] && { echo "File not found: $FILE" >&2; exit 1; }
command -v jq &>/dev/null || { echo "jq is required" >&2; exit 1; }

# ── Session ID ────────────────────────────────────────────────────────────────
if [[ -z "$SESSION_ID" ]]; then
  # Try to extract from filename (UUID.jsonl)
  BASENAME=$(basename "$FILE" .jsonl)
  if [[ "$BASENAME" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
    SESSION_ID="$BASENAME"
  else
    SESSION_ID="openclaw-$(printf '%s' "$FILE" | md5 2>/dev/null | cut -c1-12 || printf '%s' "$FILE" | md5sum 2>/dev/null | cut -c1-12)"
  fi
fi

# ── Skip if up-to-date ────────────────────────────────────────────────────────
SESSION_DIR="$SESSIONS_DIR/$SESSION_ID"
if [[ "$FORCE" == false && -f "$SESSION_DIR/llm-calls.jsonl" ]]; then
  if [[ "$FILE" -ot "$SESSION_DIR/llm-calls.jsonl" ]]; then
    exit 0
  fi
fi

mkdir -p "$SESSION_DIR"
echo "  Parsing openclaw: $SESSION_ID" >&2

: > "$SESSION_DIR/session.jsonl"
: > "$SESSION_DIR/llm-calls.jsonl"
: > "$SESSION_DIR/tools.jsonl"
: > "$SESSION_DIR/agents.jsonl"

# ── Parse ─────────────────────────────────────────────────────────────────────
TMPFILE=$(mktemp /tmp/costea_oc.XXXXXX)
trap "rm -f '$TMPFILE'" EXIT

jq -sc \
  --arg sid "$SESSION_ID" \
'
def r6: . * 1000000 | round / 1000000;

# ── group into turns (each user message starts a new turn) ────────────────────
[.[] | select(.type == "message")] as $msgs |

(reduce $msgs[] as $m (
  {turns: [], cur: null, idx: 0};
  if ($m.message.role == "user") then
    (if .cur then .turns + [.cur] else .turns end) as $t |
    {turns: $t, idx: (.idx + 1),
     cur: {
       idx: .idx,
       ts: ($m.timestamp // ""),
       prompt: ([$m.message.content[]? | select(.type == "text") | .text] | join("\n")
         | gsub("Conversation info \\(untrusted metadata\\):\n```json\n[^`]*```\n\n"; "")
         | gsub("Sender \\(untrusted metadata\\):\n```json\n[^`]*```\n\n"; "")
         | gsub("^\\s+|\\s+$"; "")),
       assistants: []
     }}
  elif ($m.message.role == "assistant" and .cur != null) then
    .cur.assistants += [$m] | .
  else . end
) | (if .cur then .turns + [.cur] else .turns end)) as $turns |

# ── emit records ──────────────────────────────────────────────────────────────
[$turns[] |
  . as $t |
  ($t.assistants | map(select(.message.usage != null and (.message.usage.totalTokens // 0) > 0))) as $um |

  if ($um | length) == 0 then empty else

  ($t.ts | gsub("[^0-9T:-]"; "") | .[0:19]) as $tss |
  ($sid[:8] + "_" + $tss + "_" + ($t.idx | tostring)) as $tid |

  # Detect skill invocation
  ($t.prompt | test("^Use the \"[^\"]+\" skill for this request\\.")) as $isskill |
  (if $isskill then ($t.prompt | capture("^Use the \"(?<n>[^\"]+)\" skill") | .n) else null end) as $sname |
  (if $isskill then ($t.prompt | gsub("^Use the \"[^\"]+\" skill for this request\\.\\s*"; "") | gsub("^User input:\\s*"; "") | gsub("^\\s+|\\s+$"; ""))
   else $t.prompt end) as $prompt |

  # Token totals (OpenClaw gives per-message, just sum)
  {
    input:  ([$um[].message.usage.input  // 0] | add // 0),
    output: ([$um[].message.usage.output // 0] | add // 0),
    cr:     ([$um[].message.usage.cacheRead  // 0] | add // 0),
    cw:     ([$um[].message.usage.cacheWrite // 0] | add // 0),
    total:  ([$um[].message.usage.totalTokens // 0] | add // 0)
  } as $tok |

  # Cost (OpenClaw provides it directly)
  ([$um[].message.usage.cost.total // 0] | add // 0 | r6) as $cost |
  ($um[0].message.model // "unknown") as $model |
  ($um[0].message.provider // "unknown") as $provider |

  # Tools
  ([$um[].message.content[]? | select(.type == "toolCall") | .name] |
    group_by(.) | map({key: .[0], value: length}) | from_entries) as $toolmap |
  ([$um[].message.content[]? | select(.type == "toolCall")] | length) as $ntool |

  # Reasoning vs tool
  ($um | map(select(.message.stopReason == "stop")))    as $rm |
  ($um | map(select(.message.stopReason == "toolUse"))) as $tm |

  # session_turn
  {__type__: "session_turn",
   record_type: "session_turn",
   turn_id: $tid, session_id: $sid,
   parent_session_id: null, agent_id: null,
   source: "openclaw", timestamp: $t.ts,
   user_prompt: ($prompt[:500]),
   is_skill: $isskill, skill_name: $sname,
   token_usage: {input: $tok.input, output: $tok.output, cache_read: $tok.cr, cache_write: $tok.cw, total: $tok.total},
   cost: {total_usd: $cost, by_model: {($model): $cost}},
   tools_summary: {total_calls: $ntool, by_tool: $toolmap},
   reasoning: {message_count: ($rm | length), tokens: ([$rm[].message.usage.output // 0] | add // 0)},
   tool_invocation: {message_count: ($tm | length), tokens: ([$tm[].message.usage.output // 0] | add // 0)},
   llm_call_count: ($um | length), version: "1.0"},

  # llm_call records (one per assistant message with usage)
  ($um[] |
    .message as $msg |
    ($msg.usage.input // 0) as $i | ($msg.usage.output // 0) as $o |
    ($msg.usage.cacheRead // 0) as $cr | ($msg.usage.cacheWrite // 0) as $cw |
    {__type__: "llm_call",
     record_type: "llm_call",
     call_id: ("oc_" + $sid[:8] + "_" + .timestamp),
     session_id: $sid, parent_session_id: null, agent_id: null,
     turn_id: $tid, source: "openclaw", timestamp: .timestamp,
     model: ($msg.model // "unknown"),
     model_short: ($msg.model // "unknown"),
     usage: {input_tokens: $i, output_tokens: $o,
             cache_read_input_tokens: $cr, cache_creation_input_tokens: $cw,
             web_search_requests: 0},
     cost_usd: (($msg.usage.cost.total // 0) | r6),
     context_window: {used: ($i + $o + $cr + $cw), model_max: 200000},
     stop_reason: ($msg.stopReason // "unknown"),
     is_reasoning_turn: ($msg.stopReason == "stop"),
     has_thinking: false,
     tool_calls: [$msg.content[]? | select(.type == "toolCall") | {tool_name: .name, tool_use_id: (.toolCallId // "unknown")}],
     dedup_siblings: 0, version: "1.0"}),

  # tool_call records
  ($um[] | .message.content[]? | select(.type == "toolCall") |
    {__type__: "tool_call",
     record_type: "tool_call",
     tool_use_id: (.toolCallId // "unknown"),
     session_id: $sid, agent_id: null, turn_id: $tid,
     tool_name: .name,
     tool_category: ((.name // "") | ascii_downcase |
       if test("exec|shell|bash|command") then "shell"
       elif test("read|write|edit|patch") then "filesystem"
       elif test("grep|search|find") then "search"
       else "other" end),
     outcome: "success", version: "1.0"})

  end
] | .[]
' "$FILE" > "$TMPFILE" 2>/dev/null || true

# ── Route to output files ─────────────────────────────────────────────────────
jq -c 'select(.__type__ == "session_turn") | del(.__type__)' "$TMPFILE" > "$SESSION_DIR/session.jsonl" 2>/dev/null || true
jq -c 'select(.__type__ == "llm_call")    | del(.__type__)' "$TMPFILE" > "$SESSION_DIR/llm-calls.jsonl" 2>/dev/null || true
jq -c 'select(.__type__ == "tool_call")   | del(.__type__)' "$TMPFILE" > "$SESSION_DIR/tools.jsonl" 2>/dev/null || true

echo "  Done → $SESSION_DIR" >&2
