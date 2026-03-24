#!/usr/bin/env bash
set -euo pipefail

# OpenClaw Token Analysis Script
# Analyzes session logs for token consumption with 3-level hierarchy

SESSIONS_DIR="${OPENCLAW_SESSIONS_DIR:-$HOME/.openclaw/agents/main/sessions}"
SESSIONS_JSON="$SESSIONS_DIR/sessions.json"

# Defaults
MODE="recent"       # recent | all | single
SESSION_ID=""
TOP_N=10
USE_COLOR=true

# Colors
setup_colors() {
  if $USE_COLOR && [[ -t 1 ]]; then
    BOLD='\033[1m'
    DIM='\033[2m'
    CYAN='\033[36m'
    GREEN='\033[32m'
    YELLOW='\033[33m'
    MAGENTA='\033[35m'
    RED='\033[31m'
    RESET='\033[0m'
  else
    BOLD='' DIM='' CYAN='' GREEN='' YELLOW='' MAGENTA='' RED='' RESET=''
  fi
}

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Analyze OpenClaw session logs for token consumption.

Options:
  --all              Analyze all sessions
  --session ID       Analyze specific session (prefix match)
  --top N            Top N sessions by cost (default: 10, with --all)
  --no-color         Disable color output
  -h, --help         Show this help

Output Hierarchy:
  Level 1: Session totals (tokens + cost)
  Level 2: Per-tool breakdown (tokens per tool, call counts)
  Level 3: Reasoning vs tool invocation split
EOF
  exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --all)       MODE="all"; shift ;;
    --session)   MODE="single"; SESSION_ID="$2"; shift 2 ;;
    --top)       TOP_N="$2"; shift 2 ;;
    --no-color)  USE_COLOR=false; shift ;;
    -h|--help)   usage ;;
    *)           echo "Unknown option: $1"; usage ;;
  esac
done

setup_colors

# Check dependencies
if ! command -v jq &>/dev/null; then
  echo "Error: jq is required. Install with: brew install jq" >&2
  exit 1
fi

if [[ ! -f "$SESSIONS_JSON" ]]; then
  echo "Error: sessions.json not found at $SESSIONS_JSON" >&2
  exit 1
fi

# Format number with commas
fmt_num() {
  printf "%'d" "$1" 2>/dev/null || printf "%d" "$1"
}

# Format cost
fmt_cost() {
  printf "$%.4f" "$1"
}

# Format duration from ms
fmt_duration() {
  local ms="$1"
  if [[ -z "$ms" || "$ms" == "null" ]]; then
    echo "N/A"
    return
  fi
  local secs=$((ms / 1000))
  if [[ $secs -lt 60 ]]; then
    echo "${secs}s"
  elif [[ $secs -lt 3600 ]]; then
    echo "$((secs / 60))m $((secs % 60))s"
  else
    echo "$((secs / 3600))h $((secs % 3600 / 60))m"
  fi
}

# Get list of sessions with token data
get_sessions() {
  jq -r '
    to_entries[]
    | select(.value.totalTokens != null and .value.totalTokens > 0)
    | .value
    | [.sessionId, (.startedAt // 0 | tostring), (.totalTokens // 0 | tostring),
       (.estimatedCostUsd // 0 | tostring), (.model // "unknown"), (.status // "unknown"),
       (.runtimeMs // 0 | tostring), (.origin.label // .origin.surface // "unknown")]
    | @tsv
  ' "$SESSIONS_JSON" | sort -t$'\t' -k2 -rn
}

# Analyze a single session JSONL file
analyze_session() {
  local session_id="$1"
  local jsonl_file="$SESSIONS_DIR/${session_id}.jsonl"

  if [[ ! -f "$jsonl_file" ]]; then
    echo -e "${RED}  JSONL file not found: $jsonl_file${RESET}" >&2
    return 1
  fi

  # Get session metadata from sessions.json
  local meta
  meta=$(jq -r --arg sid "$session_id" '
    to_entries[] | select(.value.sessionId == $sid) | .value |
    [(.startedAt // 0 | . / 1000 | strftime("%Y-%m-%d %H:%M:%S")),
     (.model // "unknown"), (.status // "unknown"),
     (.runtimeMs // 0 | tostring), (.origin.label // .origin.surface // "unknown"),
     (.inputTokens // 0 | tostring), (.outputTokens // 0 | tostring),
     (.cacheRead // 0 | tostring), (.cacheWrite // 0 | tostring),
     (.totalTokens // 0 | tostring), (.estimatedCostUsd // 0 | tostring)]
    | @tsv
  ' "$SESSIONS_JSON")

  IFS=$'\t' read -r started model sess_status runtime_ms origin \
    meta_input meta_output meta_cache_read meta_cache_write meta_total meta_cost <<< "$meta"

  local runtime_fmt
  runtime_fmt=$(fmt_duration "$runtime_ms")

  # Session header
  echo ""
  echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo -e "${BOLD} SESSION: ${session_id}${RESET}"
  echo -e "${DIM} Model: ${model} | Status: ${sess_status} | Duration: ${runtime_fmt}${RESET}"
  echo -e "${DIM} Started: ${started} | Origin: ${origin}${RESET}"
  echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"

  # Run the main jq analysis on the JSONL
  local analysis
  analysis=$(jq -s '
    # Filter to assistant messages only
    [.[] | select(.type == "message" and .message.role == "assistant" and .message.usage != null)] |

    if length == 0 then
      { empty: true }
    else
      {
        empty: false,
        message_count: length,

        # Level 1: Session totals
        total_input: (map(.message.usage.input // 0) | add),
        total_output: (map(.message.usage.output // 0) | add),
        total_cache_read: (map(.message.usage.cacheRead // 0) | add),
        total_cache_write: (map(.message.usage.cacheWrite // 0) | add),
        total_tokens: (map(.message.usage.totalTokens // 0) | add),
        total_cost: (map(.message.usage.cost.total // 0) | add),

        # Level 3: Reasoning vs tool invocation
        reasoning_tokens: ([.[] | select(.message.stopReason == "stop") | .message.usage.totalTokens // 0] | add // 0),
        reasoning_cost: ([.[] | select(.message.stopReason == "stop") | .message.usage.cost.total // 0] | add // 0),
        reasoning_count: ([.[] | select(.message.stopReason == "stop")] | length),
        reasoning_input: ([.[] | select(.message.stopReason == "stop") | .message.usage.input // 0] | add // 0),
        reasoning_output: ([.[] | select(.message.stopReason == "stop") | .message.usage.output // 0] | add // 0),

        tool_inv_tokens: ([.[] | select(.message.stopReason == "toolUse") | .message.usage.totalTokens // 0] | add // 0),
        tool_inv_cost: ([.[] | select(.message.stopReason == "toolUse") | .message.usage.cost.total // 0] | add // 0),
        tool_inv_count: ([.[] | select(.message.stopReason == "toolUse")] | length),
        tool_inv_input: ([.[] | select(.message.stopReason == "toolUse") | .message.usage.input // 0] | add // 0),
        tool_inv_output: ([.[] | select(.message.stopReason == "toolUse") | .message.usage.output // 0] | add // 0),

        # Level 2: Per-tool breakdown (proportional attribution)
        tools: (
          [.[] | select(.message.stopReason == "toolUse") |
            .message.usage as $u |
            ([.message.content[] | select(.type == "toolCall")] | length) as $tc |
            if $tc > 0 then
              .message.content[] | select(.type == "toolCall") |
              {
                name: .name,
                tokens: (($u.totalTokens // 0) / $tc | floor),
                input: (($u.input // 0) / $tc | floor),
                output: (($u.output // 0) / $tc | floor),
                cost: (($u.cost.total // 0) / $tc)
              }
            else empty end
          ] | group_by(.name) | map({
            name: .[0].name,
            tokens: (map(.tokens) | add),
            input: (map(.input) | add),
            output: (map(.output) | add),
            cost: (map(.cost) | add),
            calls: length
          }) | sort_by(-.tokens)
        )
      }
    end
  ' "$jsonl_file")

  # Check if session had any assistant messages
  local is_empty
  is_empty=$(echo "$analysis" | jq -r '.empty')
  if [[ "$is_empty" == "true" ]]; then
    echo -e "\n${DIM}  No assistant messages found in this session.${RESET}\n"
    return 0
  fi

  # Level 1: Session Totals
  echo ""
  echo -e "${BOLD}${GREEN}  LEVEL 1: Session Totals${RESET}"
  echo -e "${GREEN}  ───────────────────────${RESET}"

  local t_input t_output t_cread t_cwrite t_total t_cost msg_count
  t_input=$(echo "$analysis" | jq -r '.total_input')
  t_output=$(echo "$analysis" | jq -r '.total_output')
  t_cread=$(echo "$analysis" | jq -r '.total_cache_read')
  t_cwrite=$(echo "$analysis" | jq -r '.total_cache_write')
  t_total=$(echo "$analysis" | jq -r '.total_tokens')
  t_cost=$(echo "$analysis" | jq -r '.total_cost')
  msg_count=$(echo "$analysis" | jq -r '.message_count')

  printf "  ${BOLD}  Total tokens:  %s${RESET}     ${DIM}Cost: \$%.4f${RESET}     ${DIM}(%s messages)${RESET}\n" \
    "$(fmt_num "$t_total")" "$t_cost" "$msg_count"
  printf "    Input:         %s\n" "$(fmt_num "$t_input")"
  printf "    Output:        %s\n" "$(fmt_num "$t_output")"
  printf "    Cache read:    %s\n" "$(fmt_num "$t_cread")"
  printf "    Cache write:   %s\n" "$(fmt_num "$t_cwrite")"

  # Level 2: Per-Tool Breakdown
  echo ""
  echo -e "${BOLD}${YELLOW}  LEVEL 2: Token Breakdown by Tool${RESET}"
  echo -e "${YELLOW}  ────────────────────────────────${RESET}"

  local tool_count
  tool_count=$(echo "$analysis" | jq '.tools | length')

  if [[ "$tool_count" -eq 0 ]]; then
    echo -e "${DIM}    No tool calls in this session.${RESET}"
  else
    # Header
    printf "    ${DIM}%-16s %10s %10s %10s %10s  %s${RESET}\n" \
      "Tool" "Tokens" "Input" "Output" "Cost" "Calls"
    printf "    ${DIM}%-16s %10s %10s %10s %10s  %s${RESET}\n" \
      "────────────────" "──────────" "──────────" "──────────" "──────────" "─────"

    echo "$analysis" | jq -r '.tools[] | [.name, (.tokens|tostring), (.input|tostring), (.output|tostring), (.cost|tostring), (.calls|tostring)] | @tsv' | \
    while IFS=$'\t' read -r name tokens input output cost calls; do
      printf "    %-16s %10s %10s %10s %10s  %s\n" \
        "$name" "$(fmt_num "$tokens")" "$(fmt_num "$input")" "$(fmt_num "$output")" "$(fmt_cost "$cost")" "${calls} call$([ "$calls" != "1" ] && echo "s")"
    done
  fi

  # Level 3: Reasoning vs Tool Invocation
  echo ""
  echo -e "${BOLD}${MAGENTA}  LEVEL 3: Reasoning vs Tool Invocation${RESET}"
  echo -e "${MAGENTA}  ──────────────────────────────────────${RESET}"

  local r_tokens r_cost r_count r_input r_output
  local ti_tokens ti_cost ti_count ti_input ti_output
  r_tokens=$(echo "$analysis" | jq -r '.reasoning_tokens')
  r_cost=$(echo "$analysis" | jq -r '.reasoning_cost')
  r_count=$(echo "$analysis" | jq -r '.reasoning_count')
  r_input=$(echo "$analysis" | jq -r '.reasoning_input')
  r_output=$(echo "$analysis" | jq -r '.reasoning_output')
  ti_tokens=$(echo "$analysis" | jq -r '.tool_inv_tokens')
  ti_cost=$(echo "$analysis" | jq -r '.tool_inv_cost')
  ti_count=$(echo "$analysis" | jq -r '.tool_inv_count')
  ti_input=$(echo "$analysis" | jq -r '.tool_inv_input')
  ti_output=$(echo "$analysis" | jq -r '.tool_inv_output')

  # Calculate percentages
  local r_pct ti_pct
  if [[ "$t_total" -gt 0 ]]; then
    r_pct=$(awk "BEGIN { printf \"%.1f\", ($r_tokens / $t_total) * 100 }")
    ti_pct=$(awk "BEGIN { printf \"%.1f\", ($ti_tokens / $t_total) * 100 }")
  else
    r_pct="0.0"
    ti_pct="0.0"
  fi

  printf "    ${BOLD}Reasoning${RESET}        %10s tokens  ${DIM}(\$%.4f)${RESET}  %s msgs  ${DIM}[%s%%]${RESET}\n" \
    "$(fmt_num "$r_tokens")" "$r_cost" "$r_count" "$r_pct"
  printf "      ${DIM}└─ Input: %s  Output: %s${RESET}\n" \
    "$(fmt_num "$r_input")" "$(fmt_num "$r_output")"

  printf "    ${BOLD}Tool Invocation${RESET}  %10s tokens  ${DIM}(\$%.4f)${RESET}  %s msgs  ${DIM}[%s%%]${RESET}\n" \
    "$(fmt_num "$ti_tokens")" "$ti_cost" "$ti_count" "$ti_pct"
  printf "      ${DIM}└─ Input: %s  Output: %s${RESET}\n" \
    "$(fmt_num "$ti_input")" "$(fmt_num "$ti_output")"

  echo ""
}

# Print summary table for --all mode
print_summary_table() {
  echo ""
  echo -e "${BOLD}${CYAN}━━━ OpenClaw Session Summary ━━━${RESET}"
  echo ""
  printf "  ${DIM}%-8s  %-19s  %-12s  %10s  %10s  %s${RESET}\n" \
    "ID" "Started" "Model" "Tokens" "Cost" "Status"
  printf "  ${DIM}%-8s  %-19s  %-12s  %10s  %10s  %s${RESET}\n" \
    "────────" "───────────────────" "────────────" "──────────" "──────────" "──────"

  local count=0
  get_sessions | while IFS=$'\t' read -r sid started_ms total_tokens cost model sess_status runtime_ms origin; do
    [[ $count -ge $TOP_N ]] && break

    local started
    started=$(date -r "$((started_ms / 1000))" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "unknown")
    local short_id="${sid:0:8}"

    printf "  %-8s  %-19s  %-12s  %10s  %10s  %s\n" \
      "$short_id" "$started" "$model" "$(fmt_num "$total_tokens")" "$(fmt_cost "$cost")" "$sess_status"

    count=$((count + 1))
  done
  echo ""
}

# Main
main() {
  case "$MODE" in
    recent)
      # Get most recent session
      local latest
      latest=$(get_sessions | head -1 | cut -f1)
      if [[ -z "$latest" ]]; then
        echo "No sessions with token data found." >&2
        exit 1
      fi
      analyze_session "$latest"
      ;;

    single)
      # Prefix match on session ID
      local matched
      matched=$(get_sessions | awk -F'\t' -v prefix="$SESSION_ID" '$1 ~ "^"prefix { print $1; exit }')
      if [[ -z "$matched" ]]; then
        echo "No session found matching: $SESSION_ID" >&2
        exit 1
      fi
      analyze_session "$matched"
      ;;

    all)
      print_summary_table
      local count=0
      get_sessions | while IFS=$'\t' read -r sid rest; do
        [[ $count -ge $TOP_N ]] && break
        analyze_session "$sid"
        count=$((count + 1))
      done
      ;;
  esac
}

main
