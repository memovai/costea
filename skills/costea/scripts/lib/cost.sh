#!/usr/bin/env bash
# Costea: shared price table and jq helper functions
# Source this file: source "$(dirname "$0")/lib/cost.sh"
#
# Provides:
#   COSTEA_PRICES   - JSON string: model → {input, output, cache_read, cache_write} (USD / M tokens)
#   COSTEA_JQ_FUNS  - jq function definitions to prepend to any jq program
#
# Source: claude-code-main/src/utils/modelCost.ts (COST_TIER_* constants)

# ── Price table ───────────────────────────────────────────────────────────────
# Each entry: USD per million tokens
# Models aliased to first-party canonical names (same as modelCost.ts logic)
COSTEA_PRICES='{
  "claude-opus-4-6":   {"input": 5,    "output": 25,   "cache_read": 0.50,  "cache_write": 6.25},
  "claude-opus-4-5":   {"input": 5,    "output": 25,   "cache_read": 0.50,  "cache_write": 6.25},
  "claude-opus-4-1":   {"input": 15,   "output": 75,   "cache_read": 1.50,  "cache_write": 18.75},
  "claude-opus-4":     {"input": 15,   "output": 75,   "cache_read": 1.50,  "cache_write": 18.75},
  "claude-sonnet-4-6": {"input": 3,    "output": 15,   "cache_read": 0.30,  "cache_write": 3.75},
  "claude-sonnet-4-5": {"input": 3,    "output": 15,   "cache_read": 0.30,  "cache_write": 3.75},
  "claude-sonnet-4":   {"input": 3,    "output": 15,   "cache_read": 0.30,  "cache_write": 3.75},
  "claude-haiku-4-5":  {"input": 1,    "output": 5,    "cache_read": 0.10,  "cache_write": 1.25},
  "claude-haiku-3-5":  {"input": 0.8,  "output": 4,    "cache_read": 0.08,  "cache_write": 1.00},
  "gpt-5.4":           {"input": 2.50, "output": 15,   "cache_read": 0,     "cache_write": 0},
  "gpt-5.2-codex":     {"input": 1.07, "output": 8.50, "cache_read": 0,     "cache_write": 0},
  "gpt-5.1-codex":     {"input": 1.07, "output": 8.50, "cache_read": 0,     "cache_write": 0}
}'

# ── jq function definitions ───────────────────────────────────────────────────
# Prepend $COSTEA_JQ_FUNS to any jq program that needs cost calculation.
# Requires --argjson prices "$COSTEA_PRICES" to be passed to jq.
#
# Functions:
#   normalize_model   - model full name → short canonical name
#   mcost(m;i;o;r;w)  - USD cost from model name + token counts
#   r6                - round to 6 decimal places (avoids floating-point noise)
read -r -d '' COSTEA_JQ_FUNS << 'JQEOF' || true
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

# mcost(model_name; input_tokens; output_tokens; cache_read_tokens; cache_write_tokens)
# Returns USD cost as a float.
# Requires $prices (argjson) to be in scope.
def mcost(m; i; o; r; w):
  (m | normalize_model) as $s |
  ($prices[$s] // $prices["claude-opus-4-6"]) as $p |
  (i * $p.input + o * $p.output + r * $p.cache_read + w * $p.cache_write) / 1000000;

# Round to 6 decimal places (avoids IEEE 754 noise in cost fields)
def r6: . * 1000000 | round / 1000000;
JQEOF

export COSTEA_PRICES COSTEA_JQ_FUNS
