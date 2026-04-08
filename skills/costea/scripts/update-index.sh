#!/usr/bin/env bash
set -euo pipefail

# Costea: Scan all Claude Code sessions, parse new/changed ones, rebuild index
#
# Usage:
#   update-index.sh [--force] [--source <platform>]
#
# Options:
#   --force           Re-parse every session even if already up to date
#   --source <name>   Limit to one platform: claude-code | codex | openclaw | all (default: all)
#
# What this script does (Phase 1: Claude Code):
#   1. Finds all session JSONL files under ~/.claude/projects/
#   2. For each new / modified session, calls parse-session.sh
#   3. Runs summarize-session.sh to generate summary.json
#   4. Rebuilds ~/.costea/index.json from all summary.json files
#
# After running, ~/.costea/index.json is a lightweight index of all tracked
# sessions suitable for quick reporting without loading individual JSONL files.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
COSTEA_DIR="$HOME/.costea"
SESSIONS_DIR="$COSTEA_DIR/sessions"
INDEX_FILE="$COSTEA_DIR/index.json"

# Platform session paths
CLAUDE_PROJECTS="$HOME/.claude/projects"
CODEX_SESSIONS="${CODEX_HOME:-$HOME/.codex}/sessions"
OPENCLAW_SESSIONS="${OPENCLAW_SESSIONS_DIR:-$HOME/.openclaw/agents/main/sessions}"

source "$SCRIPT_DIR/lib/cost.sh"

if ! command -v jq &>/dev/null; then
  echo "jq is required. Install: brew install jq" >&2
  exit 1
fi

# ── Arguments ────────────────────────────────────────────────────────────────
FORCE=false
SOURCE_FILTER="all"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --force)  FORCE=true; shift ;;
    --source) SOURCE_FILTER="$2"; shift 2 ;;
    -*)       echo "Unknown option: $1" >&2; exit 1 ;;
    *)        shift ;;
  esac
done

mkdir -p "$SESSIONS_DIR"
FORCE_FLAG=""
[[ "$FORCE" == true ]] && FORCE_FLAG="--force"

sessions_parsed=0
sessions_skipped=0

# ── Phase 1: Claude Code ──────────────────────────────────────────────────────
scan_claude_code() {
  [[ ! -d "$CLAUDE_PROJECTS" ]] && return
  [[ "$SOURCE_FILTER" != "all" && "$SOURCE_FILTER" != "claude-code" ]] && return

  echo "Scanning Claude Code sessions..." >&2

  while IFS= read -r jsonl_file; do
    [[ ! -f "$jsonl_file" ]] && continue

    local bn
    bn=$(basename "$jsonl_file" .jsonl)
    # Only UUID-named files are session roots (skip subagent files)
    [[ ! "$bn" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]] && continue

    local session_dir="$SESSIONS_DIR/$bn"

    # Check if already up to date (parse-session.sh also does this, but lets
    # us skip the subprocess invocation entirely for large repos)
    if [[ "$FORCE" == false && -f "$session_dir/llm-calls.jsonl" ]]; then
      if [[ "$jsonl_file" -ot "$session_dir/llm-calls.jsonl" ]]; then
        sessions_skipped=$((sessions_skipped + 1))
        continue
      fi
    fi

    echo "  Parsing: $bn" >&2
    bash "$SCRIPT_DIR/parse-session.sh" $FORCE_FLAG --file "$jsonl_file" || {
      echo "    Warning: failed to parse $jsonl_file" >&2
      continue
    }
    bash "$SCRIPT_DIR/summarize-session.sh" "$bn" || {
      echo "    Warning: failed to summarize $bn" >&2
      continue
    }
    sessions_parsed=$((sessions_parsed + 1))

  done < <(find "$CLAUDE_PROJECTS" -maxdepth 2 -name "*.jsonl" \
              -not -path "*/subagents/*" 2>/dev/null | sort)
}

# ── Codex CLI ─────────────────────────────────────────────────────────────────
scan_codex() {
  [[ ! -d "$CODEX_SESSIONS" ]] && return
  [[ "$SOURCE_FILTER" != "all" && "$SOURCE_FILTER" != "codex" ]] && return

  echo "Scanning Codex CLI sessions..." >&2

  while IFS= read -r jsonl_file; do
    [[ ! -f "$jsonl_file" ]] && continue

    # Extract session ID from session_meta or filename
    local sid
    sid=$(jq -r 'select(.type == "session_meta") | .payload.id // empty' "$jsonl_file" 2>/dev/null | head -1)
    if [[ -z "$sid" ]]; then
      local bn
      bn=$(basename "$jsonl_file" .jsonl)
      sid="codex-${bn##*-}"
    fi

    local session_dir="$SESSIONS_DIR/$sid"
    if [[ "$FORCE" == false && -f "$session_dir/llm-calls.jsonl" ]]; then
      if [[ "$jsonl_file" -ot "$session_dir/llm-calls.jsonl" ]]; then
        sessions_skipped=$((sessions_skipped + 1))
        continue
      fi
    fi

    bash "$SCRIPT_DIR/parse-codex.sh" $FORCE_FLAG --file "$jsonl_file" || {
      echo "    Warning: failed to parse codex $jsonl_file" >&2
      continue
    }
    bash "$SCRIPT_DIR/summarize-session.sh" "$sid" || {
      echo "    Warning: failed to summarize codex $sid" >&2
      continue
    }
    sessions_parsed=$((sessions_parsed + 1))

  done < <(find "$CODEX_SESSIONS" -name "rollout-*.jsonl" 2>/dev/null | sort)
}

# ── Phase 2 stub: OpenClaw ────────────────────────────────────────────────────
scan_openclaw() {
  [[ ! -d "$OPENCLAW_SESSIONS" ]] && return
  [[ "$SOURCE_FILTER" != "all" && "$SOURCE_FILTER" != "openclaw" ]] && return
  echo "  OpenClaw: full parsing coming in Phase 2 (stats available via build-index.sh)" >&2
}

# ── Run scans ─────────────────────────────────────────────────────────────────
echo "Updating session index..." >&2
scan_claude_code
scan_codex
scan_openclaw

echo "Parsed: $sessions_parsed  Skipped (up-to-date): $sessions_skipped" >&2

# ── Rebuild index.json from all summary.json files ────────────────────────────
echo "Rebuilding ~/.costea/index.json..." >&2

# Collect all summaries into a single JSON array
summaries="[]"
while IFS= read -r summary_file; do
  [[ ! -f "$summary_file" ]] && continue
  entry=$(jq -c '{
    session_id:      .session_id,
    source:          .source,
    project_path:    .project_path,
    started_at:      .started_at,
    ended_at:        .ended_at,
    turn_count:      .turn_count,
    llm_call_count:  .llm_call_count,
    tool_call_count: .tool_call_count,
    total_tokens:    .token_usage.grand_total,
    total_cost_usd:  .cost.total_usd,
    subagent_count:  .subagents.count,
    summary_path:    ("sessions/" + .session_id + "/summary.json")
  }' "$summary_file" 2>/dev/null) || continue
  summaries=$(printf '%s\n%s' "$summaries" "$entry" | jq -sc '.[0] + [.[1:][]]')
done < <(find "$SESSIONS_DIR" -maxdepth 2 -name "summary.json" 2>/dev/null | sort)

jq -n \
  --argjson sessions "$summaries" \
  --arg updated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{
    updated_at:     $updated_at,
    session_count:  ($sessions | length),
    total_tokens:   ([$sessions[].total_tokens   // 0] | add // 0),
    total_cost_usd: ([$sessions[].total_cost_usd // 0] | add // 0 | . * 1000000 | round / 1000000),
    sources: (
      $sessions | group_by(.source) |
      map({ source: .[0].source, count: length }) | sort_by(-.count)
    ),
    sessions: ($sessions | sort_by(.started_at) | reverse)
  }' > "$INDEX_FILE"

echo "Index written → $INDEX_FILE" >&2
echo "  Sessions tracked: $(jq '.session_count' "$INDEX_FILE")" >&2
echo "  Total tokens:     $(jq '.total_tokens'   "$INDEX_FILE")" >&2
echo "  Total cost:      \$$(jq '.total_cost_usd' "$INDEX_FILE")" >&2
