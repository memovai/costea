#!/usr/bin/env bash
set -euo pipefail

# Costea: Parse a single Claude Code session JSONL into structured records
#
# Usage:
#   parse-session.sh [--file] <session.jsonl> [--force]
#
# Output directory: ~/.costea/sessions/<session_id>/
#   session.jsonl   — one record per conversation turn (user message)
#   llm-calls.jsonl — one record per LLM API call (deduped by message.id)
#   tools.jsonl     — one record per tool invocation
#   agents.jsonl    — one record per subagent lifecycle event
#
# Key behaviours:
#   - Parallel tool calls share the same message.id; only the first occurrence
#     is counted for tokens (dedup). All tool_use blocks are still recorded.
#   - Subagents in <session>/subagents/agent-*.jsonl are scanned automatically;
#     their LLM calls are appended to the parent session's llm-calls.jsonl.
#   - Skips re-parsing if the source file is older than the output (use --force
#     to override).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
COSTEA_DIR="$HOME/.costea"
SESSIONS_DIR="$COSTEA_DIR/sessions"

# ── Load shared price table ───────────────────────────────────────────────────
# shellcheck source=lib/cost.sh
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

if [[ -z "$FILE" ]]; then
  echo "Usage: $0 [--file] <session.jsonl> [--force]" >&2
  exit 1
fi
if [[ ! -f "$FILE" ]]; then
  echo "File not found: $FILE" >&2
  exit 1
fi
if ! command -v jq &>/dev/null; then
  echo "jq is required. Install: brew install jq" >&2
  exit 1
fi

# ── Derive session ID ─────────────────────────────────────────────────────────
# Claude Code names session files as UUID.jsonl
BASENAME=$(basename "$FILE" .jsonl)
SESSION_ID=""
if [[ "$BASENAME" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
  SESSION_ID="$BASENAME"
fi
if [[ -z "$SESSION_ID" ]]; then
  # Fallback for non-UUID filenames (Codex / OpenClaw)
  _hash=$(printf '%s' "$FILE" | md5 2>/dev/null || printf '%s' "$FILE" | md5sum 2>/dev/null | cut -c1-32)
  SESSION_ID="session-${_hash:0:12}"
fi

# ── Skip if already up-to-date ────────────────────────────────────────────────
SESSION_DIR="$SESSIONS_DIR/$SESSION_ID"
if [[ "$FORCE" == false && -f "$SESSION_DIR/llm-calls.jsonl" ]]; then
  if [[ "$FILE" -ot "$SESSION_DIR/llm-calls.jsonl" ]]; then
    exit 0
  fi
fi

mkdir -p "$SESSION_DIR"
echo "  Parsing session: $SESSION_ID" >&2

# ── Core jq program ───────────────────────────────────────────────────────────
# Emits NDJSON lines, each tagged with __type__:
#   "session_turn"  → session.jsonl
#   "llm_call"      → llm-calls.jsonl
#   "tool_call"     → tools.jsonl
#
# Design notes:
# 1. Messages are grouped into "turns" where each user string message starts
#    a new turn. If no user string messages exist (e.g. subagent files), all
#    assistant messages are collected into one virtual turn.
# 2. Dedup: assistant messages sharing the same message.id (parallel tool calls)
#    are grouped; only the first occurrence contributes to token counts.
# 3. All tool_use blocks across siblings are collected and emitted as tool_call
#    records with unique tool_use_id values.
read -r -d '' _JQ_PARSE << 'JQEOF' || true

# ── Utility functions (requires $prices argjson) ─────────────────────────────

def normalize_model:
  if . == null then "unknown"
  else ascii_downcase |
    if   test("opus.*(4-6|4\\.6)")    then "claude-opus-4-6"
    elif test("opus.*(4-5|4\\.5)")    then "claude-opus-4-5"
    elif test("opus.*(4-1|4\\.1)")    then "claude-opus-4-1"
    elif test("opus.*4")              then "claude-opus-4"
    elif test("sonnet.*(4-6|4\\.6)")  then "claude-sonnet-4-6"
    elif test("sonnet.*(4-5|4\\.5)")  then "claude-sonnet-4-5"
    elif test("sonnet.*4")            then "claude-sonnet-4"
    elif test("haiku.*(4-5|4\\.5)")   then "claude-haiku-4-5"
    elif test("haiku")                then "claude-haiku-3-5"
    elif test("gpt-5\\.4")            then "gpt-5.4"
    elif test("codex|5[-.]2")         then "gpt-5.2-codex"
    else "claude-opus-4-6" end
  end;

def mcost(m; i; o; r; w):
  (m | normalize_model) as $s |
  ($prices[$s] // $prices["claude-opus-4-6"]) as $p |
  (i * $p.input + o * $p.output + r * $p.cache_read + w * $p.cache_write) / 1000000;

def r6: . * 1000000 | round / 1000000;

def tool_category:
  ascii_downcase |
  if   test("read|write|edit|glob|notebook") then "filesystem"
  elif test("bash|execute")                  then "shell"
  elif test("grep|search|web")               then "search"
  elif test("agent|task")                    then "agent"
  else "other" end;

# ── Group messages into turns ─────────────────────────────────────────────────
# A "turn" starts with a user string message. If there are none, fall back to
# a single virtual turn containing all assistant messages.

[.[] | select(.type == "user" or .type == "assistant")] as $all |

# First pass: check if there are any user string messages
([$all[] | select(.type == "user" and (.message.content | type) == "string")] | length) as $n_user |

(if $n_user > 0 then
  # Normal grouping: each user string message starts a new turn
  reduce $all[] as $m (
    {turns: [], cur: null, idx: 0};
    if ($m.type == "user" and ($m.message.content | type) == "string") then
      (if .cur then .turns + [.cur] else .turns end) as $t |
      { turns: $t, idx: (.idx + 1),
        cur: { idx: .idx, ts: ($m.timestamp // ""),
               prompt: ($m.message.content // ""), msgs: [] } }
    elif ($m.type == "assistant" and .cur != null) then
      .cur.msgs += [$m] | .
    else . end
  ) | (if .cur then .turns + [.cur] else .turns end)
else
  # Subagent / no user messages: single virtual turn
  [{ idx: 0,
     ts: ($all | map(select(.type == "assistant")) | first // {} | .timestamp // ""),
     prompt: "",
     msgs: [$all[] | select(.type == "assistant")] }]
end) as $turns |

# ── Emit records for each turn ────────────────────────────────────────────────
$turns[] |
  .idx    as $tidx  |
  .ts     as $ts    |
  .prompt as $raw   |
  .msgs   as $msgs  |

  # Dedup assistant messages with usage by message.id.
  # Group by id; first in group = authoritative for token counts.
  # Collect all tool_use blocks across all siblings in the group.
  ($msgs
    | map(select(.message.usage != null))
    | group_by(
        .message.id //
        ("_noid_" + (.timestamp // "") + (. | tojson | length | tostring))
      )
    | map({
        f:     .[0],
        tools: [.[].message.content[]? | select(.type == "tool_use")],
        n:     length
      })
  ) as $calls |

  # Skip turns with no LLM activity
  if ($calls | length) == 0 then empty
  else

  # Turn ID: short-sid + timestamp digits + sequential index
  ($ts | gsub("[^0-9T:-]"; "") | .[0:19]) as $tss |
  ($sid[:8] + "_" + $tss + "_" + ($tidx | tostring)) as $tid |

  # Skill detection (Claude Code: /command at start of user prompt)
  ($raw | test("^/[a-zA-Z]")) as $isskill |
  (if $isskill then ($raw | capture("^/(?<n>[a-zA-Z0-9_-]+)") | .n)
               else null end) as $sname |
  (if $isskill then ($raw | gsub("^/[a-zA-Z0-9_-]+\\s*"; ""))
               else $raw end) as $prompt |

  # Per-model token aggregation (for cost breakdown by model)
  ($calls
    | group_by(.f.message.model // "unknown")
    | map(
        (.[0].f.message.model // "unknown") as $m |
        { model: $m,
          ms:  ($m | normalize_model),
          i:   ([.[].f.message.usage.input_tokens  // 0] | add // 0),
          o:   ([.[].f.message.usage.output_tokens // 0] | add // 0),
          r:   ([.[].f.message.usage.cache_read_input_tokens  // 0] | add // 0),
          w:   ([.[].f.message.usage.cache_creation_input_tokens // 0] | add // 0) }
        | . + { c: (mcost(.model; .i; .o; .r; .w) | r6) }
      )
  ) as $bym |

  { i: ([$bym[].i] | add // 0), o: ([$bym[].o] | add // 0),
    r: ([$bym[].r] | add // 0), w: ([$bym[].w] | add // 0) } as $tok |
  ($tok.i + $tok.o + $tok.r + $tok.w) as $total |
  ([$bym[].c] | add // 0) as $tcost |

  # Tool aggregates across all (non-deduped) messages in this turn
  ([$msgs[].message.content[]? | select(.type == "tool_use") | .name]
    | group_by(.) | map({key: .[0], value: length}) | from_entries) as $toolmap |
  ([$msgs[].message.content[]? | select(.type == "tool_use")] | length) as $ntool |

  # Reasoning vs tool-invocation split (by stop_reason)
  ($calls | map(select(.f.message.stop_reason == "end_turn")))  as $rm |
  ($calls | map(select(.f.message.stop_reason == "tool_use")))  as $tm |

  # ── EMIT: session_turn record ─────────────────────────
  { __type__: "session_turn",
    record_type: "session_turn",
    turn_id:           $tid,
    session_id:        $sid,
    parent_session_id: (if $parent_sid != "" then $parent_sid else null end),
    agent_id:          (if $agent_id   != "" then $agent_id   else null end),
    source:            "claude-code",
    timestamp:         $ts,
    user_prompt:       ($prompt[:500]),
    is_skill:          $isskill,
    skill_name:        $sname,
    token_usage: {
      input:       $tok.i, output:      $tok.o,
      cache_read:  $tok.r, cache_write: $tok.w, total: $total },
    cost: {
      total_usd: ($tcost | r6),
      by_model:  ($bym | map({key: .model, value: (.c | r6)}) | from_entries) },
    tools_summary: { total_calls: $ntool, by_tool: $toolmap },
    reasoning:        { message_count: ($rm | length),
                        tokens: ([$rm[].f.message.usage.output_tokens // 0] | add // 0) },
    tool_invocation:  { message_count: ($tm | length),
                        tokens: ([$tm[].f.message.usage.output_tokens // 0] | add // 0) },
    llm_call_count: ($calls | length),
    version: "1.0" },

  # ── EMIT: llm_call record (one per deduped message) ───
  ($calls[] |
    .f.message.usage as $u |
    (.f.message.model // "unknown") as $m |
    ($u.input_tokens  // 0) as $i |
    ($u.output_tokens // 0) as $o |
    ($u.cache_read_input_tokens   // 0) as $r |
    ($u.cache_creation_input_tokens // 0) as $w |
    { __type__: "llm_call",
      record_type:       "llm_call",
      call_id:           (.f.message.id // null),
      session_id:        $sid,
      parent_session_id: (if $parent_sid != "" then $parent_sid else null end),
      agent_id:          (if $agent_id   != "" then $agent_id   else .f.agentId // null end),
      turn_id:           $tid,
      source:            "claude-code",
      timestamp:         .f.timestamp,
      model:             $m,
      model_short:       ($m | normalize_model),
      usage: {
        input_tokens:               $i,
        output_tokens:              $o,
        cache_read_input_tokens:    $r,
        cache_creation_input_tokens: $w,
        web_search_requests: (.f.message.usage.server_tool_use?.web_search_requests // 0) },
      cost_usd:         (mcost($m; $i; $o; $r; $w) | r6),
      context_window:   { used: ($i + $o + $r + $w), model_max: 200000 },
      stop_reason:      (.f.message.stop_reason // "unknown"),
      is_reasoning_turn: (.f.message.stop_reason == "end_turn"),
      has_thinking:     ([.f.message.content[]? | select(.type == "thinking")] | length > 0),
      tool_calls:       [.tools[] | {tool_name: .name, tool_use_id: .id}],
      dedup_siblings:   (.n - 1),
      version: "1.0" }),

  # ── EMIT: tool_call record (one per unique tool_use block) ──
  ($calls[] | .tools[] |
    { __type__: "tool_call",
      record_type:  "tool_call",
      tool_use_id:  .id,
      session_id:   $sid,
      agent_id:     (if $agent_id != "" then $agent_id else null end),
      turn_id:      $tid,
      tool_name:    .name,
      tool_category: (.name | tool_category),
      outcome:      "success",
      version:      "1.0" })

  end
JQEOF

# ── Helper: parse one JSONL file → temp tagged records ───────────────────────
# Args: <file> <session_id> <parent_session_id> <agent_id> <out_dir>
# Appends (not overwrites) llm-calls.jsonl and tools.jsonl so subagent calls
# accumulate in the parent session directory.
_parse_file() {
  local file="$1" sid="$2" parent_sid="$3" agent_id="$4" out_dir="$5"

  local tmpfile
  tmpfile=$(mktemp /tmp/costea_parse.XXXXXX)
  # shellcheck disable=SC2064
  trap "rm -f '$tmpfile'" RETURN

  jq -sc \
    --arg sid        "$sid"        \
    --arg parent_sid "$parent_sid" \
    --arg agent_id   "$agent_id"   \
    --argjson prices "$COSTEA_PRICES" \
    "$_JQ_PARSE" \
    "$file" > "$tmpfile" 2>/dev/null || true

  # Route tagged records to the appropriate JSONL files
  # session_turn  → overwrite (only parent session generates these)
  # llm_call      → append   (subagent calls append to parent's file)
  # tool_call     → append
  if [[ "$agent_id" == "" ]]; then
    jq -c 'select(.__type__ == "session_turn") | del(.__type__)' "$tmpfile" \
      > "$out_dir/session.jsonl"
  fi
  jq -c 'select(.__type__ == "llm_call")    | del(.__type__)' "$tmpfile" \
    >> "$out_dir/llm-calls.jsonl"
  jq -c 'select(.__type__ == "tool_call")   | del(.__type__)' "$tmpfile" \
    >> "$out_dir/tools.jsonl"
}

# ── Parse main session ────────────────────────────────────────────────────────
# Truncate output files for the main session (fresh parse)
: > "$SESSION_DIR/session.jsonl"
: > "$SESSION_DIR/llm-calls.jsonl"
: > "$SESSION_DIR/tools.jsonl"
: > "$SESSION_DIR/agents.jsonl"

_parse_file "$FILE" "$SESSION_ID" "" "" "$SESSION_DIR"

# ── Scan and process subagents ────────────────────────────────────────────────
# Subagent files live at: <project>/<sessionId>/subagents/agent-<agentId>.jsonl
# Parallel to the main session file's location.
SUBAGENT_DIR="$(dirname "$FILE")/${SESSION_ID}/subagents"

if [[ -d "$SUBAGENT_DIR" ]]; then
  while IFS= read -r agent_file; do
    AGENT_ID=$(basename "$agent_file" .jsonl | sed 's/^agent-//')
    echo "    → subagent: $AGENT_ID" >&2

    # Append subagent LLM calls + tools to parent session files
    _parse_file "$agent_file" "$SESSION_ID" "$SESSION_ID" "$AGENT_ID" "$SESSION_DIR"

    # Build agent event record (token totals for this subagent)
    AGENT_STATS=$(jq -sc \
      --arg aid "$AGENT_ID" \
      --arg sid "$SESSION_ID" \
      --argjson prices "$COSTEA_PRICES" \
      "$COSTEA_JQ_FUNS"'
      [.[] | select(.type == "assistant" and .message.usage != null)] |
      group_by(.message.id // "_noid") | map(.[0]) as $dd |
      ($dd[0].message.model // "unknown") as $m0 |
      {
        llm_call_count: ($dd | length),
        model:          $m0,
        input:  ([$dd[].message.usage.input_tokens  // 0] | add // 0),
        output: ([$dd[].message.usage.output_tokens // 0] | add // 0),
        cr:     ([$dd[].message.usage.cache_read_input_tokens  // 0] | add // 0),
        cw:     ([$dd[].message.usage.cache_creation_input_tokens // 0] | add // 0)
      } | . + {
        total:    (.input + .output + .cr + .cw),
        cost_usd: (mcost(.model; .input; .output; .cr; .cw) | r6)
      }
      ' "$agent_file" 2>/dev/null) || AGENT_STATS='{"llm_call_count":0,"input":0,"output":0,"cr":0,"cw":0,"total":0,"cost_usd":0}'

    jq -cn \
      --arg    aid    "$AGENT_ID"                          \
      --arg    sid    "$SESSION_ID"                        \
      --arg    afile  "subagents/agent-${AGENT_ID}.jsonl"  \
      --argjson stats "$AGENT_STATS"                       \
      '{ record_type:  "agent_event",
         event_type:   "stop",
         agent_id:     $aid,
         session_id:   $sid,
         agent_file:   $afile,
         final_token_usage: {
           input:       ($stats.input  // 0),
           output:      ($stats.output // 0),
           cache_read:  ($stats.cr     // 0),
           cache_write: ($stats.cw     // 0),
           total:       ($stats.total  // 0) },
         final_cost_usd:  ($stats.cost_usd      // 0),
         llm_call_count:  ($stats.llm_call_count // 0),
         version: "1.0" }' \
      >> "$SESSION_DIR/agents.jsonl"

  done < <(find "$SUBAGENT_DIR" -name "agent-*.jsonl" 2>/dev/null | sort)
fi

echo "  Done → $SESSION_DIR" >&2
