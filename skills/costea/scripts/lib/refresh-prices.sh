#!/usr/bin/env bash
set -euo pipefail
#
# Refresh the vendored model-pricing snapshot used by costea's cost.sh.
#
# Source of truth: LiteLLM's model_prices_and_context_window.json
#   https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json
#
# We pull the upstream JSON, keep only the models we actually see in agent
# session logs (Anthropic Claude + OpenAI gpt-5/codex direct, no bedrock/vertex/
# azure mirrors), convert per-token costs to USD per million tokens for human
# legibility, and write the result to lib/litellm-prices.json next to this script.
#
# Run manually whenever you want to pick up upstream pricing changes:
#   bash skills/costea/scripts/lib/refresh-prices.sh
#

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT="$SCRIPT_DIR/litellm-prices.json"
URL="https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json"

echo "Fetching $URL ..." >&2
tmp=$(mktemp /tmp/litellm-prices.XXXXXX.json)
trap 'rm -f "$tmp"' EXIT

curl -sSfL "$URL" -o "$tmp"
size_bytes=$(wc -c < "$tmp")
echo "  fetched ${size_bytes} bytes" >&2

# Keep only direct-provider Anthropic + OpenAI entries that are mode=chat.
# Reject bedrock/vertex/azure mirrors, region-prefixed variants, and snapshot @-keys.
jq '
  to_entries
  | map(select((.value | type) == "object"))
  | map(select(.value.litellm_provider == "anthropic" or .value.litellm_provider == "openai"))
  | map(select(.value.mode == "chat" or .value.mode == "responses" or .value.mode == null))
  | map(select(.key | test("^(anthropic|bedrock|vertex|azure|openrouter|databricks|deepinfra|cohere|together_ai|fireworks_ai|invokeai|us\\.|eu\\.|apac\\.)") | not))
  | map(select(.key | contains("@") | not))
  | map(select(.key | contains("/") | not))
  | map({
      key: .key,
      value: {
        provider:     .value.litellm_provider,
        input:        ((.value.input_cost_per_token             // 0) * 1000000),
        output:       ((.value.output_cost_per_token            // 0) * 1000000),
        cache_read:   ((.value.cache_read_input_token_cost      // 0) * 1000000),
        cache_write:  ((.value.cache_creation_input_token_cost  // 0) * 1000000)
      }
    })
  | from_entries
' "$tmp" > "$OUT"

echo "" >&2
echo "Wrote $OUT" >&2
echo "  $(jq 'length' "$OUT") models, $(wc -c < "$OUT") bytes" >&2
echo "" >&2
echo "Sample Claude entries:" >&2
jq -r 'to_entries | map(select(.key | test("opus-4|haiku-4|sonnet-4"))) | .[] | "  \(.key): in=$\(.value.input)/MTok out=$\(.value.output)/MTok cr=$\(.value.cache_read)/MTok"' "$OUT" >&2
