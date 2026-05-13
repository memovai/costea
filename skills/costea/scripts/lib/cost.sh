#!/usr/bin/env bash
# Costea: shared price table and jq helper functions
# Source this file: source "$(dirname "$0")/lib/cost.sh"
#
# Provides:
#   COSTEA_PRICES   - JSON: model → {provider, input, output, cache_read, cache_write}
#                     in USD per million tokens.
#   COSTEA_JQ_FUNS  - jq function definitions (normalize_model, mcost, r6) to
#                     prepend to any jq program that needs cost calculation.
#   COSTEA_PROVIDERS - flat list of named providers for "what if I used X" tables.
#
# Source of truth: vendored snapshot from LiteLLM
#   ./litellm-prices.json
# Refresh with: bash lib/refresh-prices.sh

# ── Price table (loaded from vendored LiteLLM snapshot) ───────────────────────
# Use BASH_SOURCE when available; fall back to $0 (works under zsh `source` too).
_costea_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd 2>/dev/null)"
_costea_prices_file="${_costea_lib_dir:-.}/litellm-prices.json"

if [[ -f "$_costea_prices_file" ]]; then
  COSTEA_PRICES=$(cat "$_costea_prices_file")
else
  # Fallback if vendored file is missing — minimal table so callers don't crash.
  COSTEA_PRICES='{"claude-opus-4-6":{"provider":"anthropic","input":5,"output":25,"cache_read":0.5,"cache_write":6.25}}'
fi

# ── jq function definitions ───────────────────────────────────────────────────
# Prepend $COSTEA_JQ_FUNS to any jq program that needs cost calculation.
# Requires --argjson prices "$COSTEA_PRICES" to be passed to jq.
#
# Functions:
#   normalize_model   - model full name → key that exists in $prices
#   mcost(m;i;o;r;w)  - USD cost from model name + token counts (per million)
#   r6                - round to 6 decimal places
read -r -d '' COSTEA_JQ_FUNS << 'JQEOF' || true
# normalize_model: best-effort lookup against LiteLLM key set.
#   1. exact match on the raw model string
#   2. strip date / snapshot suffix (-YYYYMMDD or -vN)
#   3. fall back to a Claude Opus 4-class default so cost is never undefined
def normalize_model:
  if . == null then "claude-opus-4-6"
  else
    . as $raw |
    if   $prices[$raw] then $raw
    else
      ($raw | sub("-(20\\d{6}|\\d{8})(-v\\d+:\\d+)?$"; ""))      as $stripped |
      ($raw | sub("(-20\\d{6}|-\\d{8})(-v\\d+:\\d+)?$"; ""))     as $stripped2 |
      if   $prices[$stripped]  then $stripped
      elif $prices[$stripped2] then $stripped2
      else "claude-opus-4-6"
      end
    end
  end;

# mcost(model_name; input_tokens; output_tokens; cache_read_tokens; cache_write_tokens)
# Returns USD cost as a float. Prices in $prices are USD per million tokens.
# Requires $prices (argjson) to be in scope.
def mcost(m; i; o; r; w):
  (m | normalize_model) as $s |
  ($prices[$s] // $prices["claude-opus-4-6"]) as $p |
  (i * $p.input + o * $p.output + r * $p.cache_read + w * $p.cache_write) / 1000000;

# Round to 6 decimal places (avoids IEEE 754 noise in cost fields)
def r6: . * 1000000 | round / 1000000;
JQEOF

# ── Multi-provider comparison prices ──────────────────────────────────────────
# Used by receipt.sh and estimate-cost.sh to show cost across providers.
# Only input + output (no cache) — for "what if I used a different model" estimates.
# Sourced from the same vendored LiteLLM snapshot at script-load time.
COSTEA_PROVIDERS=$(
  jq -c '
    def pick($k; $name):
      .[$k] // null | if . then {name: $name, input, output} else empty end;
    [
      pick("claude-opus-4-6";   "Claude Opus 4.6"),
      pick("claude-sonnet-4-6"; "Claude Sonnet 4.6"),
      pick("claude-haiku-4-5";  "Claude Haiku 4.5"),
      pick("gpt-5.4";           "GPT-5.4"),
      pick("gpt-5.2-codex";     "GPT-5.2 Codex"),
      pick("gemini-2.5-pro";    "Gemini 2.5 Pro"),
      pick("gemini-2.5-flash";  "Gemini 2.5 Flash")
    ]
  ' <<< "$COSTEA_PRICES" 2>/dev/null || echo '[]'
)

export COSTEA_PRICES COSTEA_JQ_FUNS COSTEA_PROVIDERS
