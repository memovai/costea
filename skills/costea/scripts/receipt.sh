#!/usr/bin/env bash
set -euo pipefail

# Costea: Render a cost estimate receipt in the terminal
#
# Usage:
#   echo '<json>' | receipt.sh
#   receipt.sh --json '<json>'
#
# Input JSON schema:
#   {
#     "task":           "Refactor the auth module",
#     "input_tokens":   12400,
#     "output_tokens":  5800,
#     "tool_calls":     14,
#     "similar_tasks":  3,
#     "est_runtime":    "~2 min",
#     "providers": [
#       {"name": "Claude Sonnet 4", "cost": 0.38},
#       {"name": "GPT-5.4",         "cost": 0.54}
#     ],
#     "total_cost":     0.38,
#     "best_provider":  "Claude Sonnet 4",
#     "confidence":     96
#   }

if ! command -v jq &>/dev/null; then
  echo "Error: jq is required" >&2
  exit 1
fi

# ── Read JSON input ───────────────────────────────────────────────────────────
JSON=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --json|-j) JSON="$2"; shift 2 ;;
    *)         JSON="$1"; shift ;;
  esac
done
if [[ -z "$JSON" ]]; then
  JSON=$(cat)
fi
if [[ -z "$JSON" ]]; then
  echo "Error: no JSON input" >&2
  exit 1
fi

# ── Extract fields ────────────────────────────────────────────────────────────
task=$(echo "$JSON"           | jq -r '.task // "Unknown task"')
input_tokens=$(echo "$JSON"   | jq -r '.input_tokens // 0')
output_tokens=$(echo "$JSON"  | jq -r '.output_tokens // 0')
tool_calls=$(echo "$JSON"     | jq -r '.tool_calls // 0')
similar=$(echo "$JSON"        | jq -r '.similar_tasks // 0')
est_rt=$(echo "$JSON"         | jq -r '.est_runtime // "N/A"')
total_cost=$(echo "$JSON"     | jq -r '.total_cost // 0')
best=$(echo "$JSON"           | jq -r '.best_provider // ""')
confidence=$(echo "$JSON"     | jq -r '.confidence // 0')
timestamp=$(date '+%Y-%m-%d %H:%M:%S')

# Providers array → lines of "name|cost"
prov_lines=()
while IFS= read -r _line; do
  prov_lines+=("$_line")
done < <(echo "$JSON" | jq -r '.providers[]? | "\(.name)|\(.cost)"')

# ── Number formatting ─────────────────────────────────────────────────────────
fmt_num() {
  printf "%'d" "$1" 2>/dev/null || echo "$1"
}

fmt_cost() {
  printf '$%.2f' "$1"
}

# Truncate task to fit receipt width
MAX_TASK=44
if [[ ${#task} -gt $MAX_TASK ]]; then
  task="${task:0:$((MAX_TASK - 3))}..."
fi

# ── Receipt dimensions ────────────────────────────────────────────────────────
W=50  # inner content width (between │ borders)

# ── Drawing helpers ───────────────────────────────────────────────────────────
line_top()    { printf '┌'; printf '─%.0s' $(seq 1 $W); printf '┐\n'; }
line_bot()    { printf '└'; printf '─%.0s' $(seq 1 $W); printf '┘\n'; }
line_dash()   { printf '│'; printf -- '╌%.0s' $(seq 1 $W); printf '│\n'; }
line_double() { printf '│'; printf '═%.0s' $(seq 1 $W); printf '│\n'; }
blank()       { printf '│%-*s│\n' $W ""; }

center() {
  local text="$1"
  local len=${#text}
  local pad=$(( (W - len) / 2 ))
  local rpad=$(( W - len - pad ))
  printf '│%*s%s%*s│\n' "$pad" "" "$text" "$rpad" ""
}

# label (left-aligned, dim), value (right-aligned)
row() {
  local label="$1" value="$2"
  local gap=$(( W - 4 - ${#label} - ${#value} ))
  if [[ $gap -lt 1 ]]; then gap=1; fi
  printf '│  %s%*s%s  │\n' "$label" "$gap" "" "$value"
}

# section header (left-aligned, small caps style)
header() {
  printf '│  %-*s│\n' $((W - 2)) "$1"
}

# ── Render ────────────────────────────────────────────────────────────────────

line_top
blank
center "C O S T E A"
center "Agent Cost Receipt"
center "$timestamp"
blank
line_dash
blank
header "TASK"
printf '│  %-*s│\n' $((W - 2)) "$task"
blank
line_dash
blank
row "Input tokens"           "$(fmt_num "$input_tokens")"
row "Output tokens"          "$(fmt_num "$output_tokens")"
row "Tool calls"             "$tool_calls"
row "Similar tasks matched"  "$similar"
row "Est. runtime"           "$est_rt"
blank
line_dash
blank
header "PROVIDER ESTIMATES"

for pline in "${prov_lines[@]}"; do
  pname="${pline%%|*}"
  pcost="${pline##*|}"
  row "$pname" "$(fmt_cost "$pcost")"
done

blank
line_double
blank

# Total line — larger emphasis
total_label="ESTIMATED TOTAL"
total_val="$(fmt_cost "$total_cost")"
row "$total_label" "$total_val"

if [[ -n "$best" ]]; then
  best_text="best price: $best"
  local_pad=$(( W - 2 - ${#best_text} ))
  printf '│%*s%s  │\n' "$local_pad" "" "$best_text"
fi

blank
line_dash
blank
row "Confidence" "${confidence}%"
blank
line_dash
blank
center "Proceed? [Y/N]"
blank
line_dash
blank
center "POWERED BY /COSTEA SKILL"
center "THANK YOU FOR BEING COST-CONSCIOUS"
blank

# ── Barcode (decorative) ──────────────────────────────────────────────────────
bars="║│║║│║│ ║║│║│║│║ ║║│║║│║│║│"
center "$bars"

blank
line_bot
